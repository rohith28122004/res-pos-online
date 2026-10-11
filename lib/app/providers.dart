import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/host/host_connectivity.dart';
import '../core/security/permissions.dart';
import '../features/settings/application/printer_service.dart';
import '../features/shifts/application/shift_service.dart';
import 'device_runtime.dart';
import 'runtime.dart';

sealed class AppState {
  const AppState();
}

class AppLoading extends AppState {
  const AppLoading();
}

/// Another CaféDesk window already has this data directory open.
class AppAlreadyRunning extends AppState {
  const AppAlreadyRunning();
}

class AppChooseMode extends AppState {
  const AppChooseMode();
}

class AppNeedsSetup extends AppState {
  const AppNeedsSetup(this.runtime);
  final AppRuntime runtime;
}

class AppReady extends AppState {
  const AppReady(this.runtime, this.generation);
  final AppRuntime runtime;

  /// Bumped after a restore so every screen rebuilds on the new connection.
  final int generation;
}

/// This install is a waiter phone or kitchen display.
class AppDevice extends AppState {
  const AppDevice(this.device);
  final DeviceRuntime device;
}

class AppFailed extends AppState {
  const AppFailed(this.error);
  final Object error;
}

class AppController extends Notifier<AppState> {
  /// [paths] replaces the app's data folder (device tests use a temporary one).
  AppController({AppPaths? paths}) : _given = paths;

  final AppPaths? _given;
  AppPaths? _paths;
  InstanceLock? _lock;
  AppRuntime? _runtime;
  DeviceRuntime? _device;
  int _generation = 0;

  @override
  AppState build() {
    ref.onDispose(() {
      unawaited(_runtime?.dispose());
      unawaited(_device?.dispose());
      unawaited(_lock?.release());
    });
    unawaited(Future.microtask(_start));
    return const AppLoading();
  }

  AppPaths get paths => _paths!;

  Future<void> _start() async {
    try {
      _paths = _given ?? await AppPaths.resolve();
      _lock = await InstanceLock.acquire(_paths!.lockFile);
      if (_lock == null) {
        state = const AppAlreadyRunning();
        return;
      }
      // The demo café and its built-in sign-ins were removed: delete its
      // sample database. Real POS data is in a different file.
      await _paths!.deleteOldDemo();
      final mode = await _paths!.readMode();
      if (mode == 'device') {
        await _openDevice();
        return;
      }
      if (mode != 'production') {
        if (mode != null) await _paths!.clearMode();
        state = const AppChooseMode();
        return;
      }
      await _open();
    } on Object catch (e) {
      state = AppFailed(e);
    }
  }

  Future<void> _open() async {
    state = const AppLoading();
    try {
      final rt = await AppRuntime.open(_paths!);
      _runtime = rt;
      if (await rt.services.setup.isSetupComplete()) {
        await rt.startBackground();
        state = AppReady(rt, ++_generation);
      } else {
        state = AppNeedsSetup(rt);
      }
    } on Object catch (e) {
      state = AppFailed(e);
    }
  }

  Future<void> _openDevice() async {
    state = const AppLoading();
    try {
      final d = await DeviceRuntime.open(_paths!);
      _device = d;
      await d.sync.start();
      state = AppDevice(d);
    } on Object catch (e) {
      state = AppFailed(e);
    }
  }

  /// Use this install as a waiter phone or kitchen display.
  Future<void> chooseDeviceMode() async {
    await _paths!.writeDeviceMode();
    await _openDevice();
  }

  /// Unpairs and returns to the first screen.
  Future<void> leaveDeviceMode() async {
    final d = _device;
    if (d != null) {
      await d.sync.unpair();
      await d.dispose();
    }
    _device = null;
    await _paths!.clearMode();
    state = const AppChooseMode();
  }

  /// Use this install as the café's main till (POS).
  Future<void> choosePos() async {
    await _paths!.writePosMode();
    await _open();
  }

  Future<void> setupCompleted() async {
    final rt = _runtime!;
    await rt.startBackground();
    state = AppReady(rt, ++_generation);
  }

  /// After a restore the runtime already holds the reopened connection.
  Future<void> reloadAfterRestore() async {
    ref.read(sessionProvider.notifier).logout();
    final rt = _runtime!;
    await rt.startBackground();
    state = AppReady(rt, ++_generation);
  }

  Future<void> retry() async {
    state = const AppLoading();
    await _start();
  }
}

final appControllerProvider = NotifierProvider<AppController, AppState>(AppController.new);

AppRuntime _runtimeOf(AppState s) => switch (s) {
  AppReady(:final runtime) => runtime,
  AppNeedsSetup(:final runtime) => runtime,
  _ => throw StateError('The app is not ready'),
};

final runtimeProvider = Provider<AppRuntime>((ref) => _runtimeOf(ref.watch(appControllerProvider)));

final servicesProvider = Provider<Services>((ref) {
  ref.watch(appControllerProvider);
  return ref.watch(runtimeProvider).services;
});

class SessionController extends Notifier<Actor?> {
  @override
  Actor? build() => null;

  void login(Actor actor) => state = actor;
  void logout() => state = null;
}

final sessionProvider = NotifierProvider<SessionController, Actor?>(SessionController.new);

/// The signed-in actor. Only use below the lock screen.
Actor requireActor(WidgetRef ref) {
  final a = ref.read(sessionProvider);
  if (a == null) throw StateError('Not signed in');
  return a;
}

final settingsStreamProvider = StreamProvider<RestaurantSettingsRow?>(
  (ref) => ref.watch(servicesProvider).settings.watch(),
);

final installationProvider = FutureProvider<InstallationRow>((ref) => ref.watch(servicesProvider).ctx.installation());

final currentShiftProvider = StreamProvider<ShiftRow?>((ref) => ref.watch(servicesProvider).shifts.watchCurrentShift());

final printCountsProvider = StreamProvider<PrintQueueCounts>(
  (ref) => ref.watch(servicesProvider).printers.watchCounts(),
);

final shiftSummaryProvider = FutureProvider.family<ShiftSummary, String>(
  (ref, id) => ref.watch(servicesProvider).shifts.summary(id),
);

/// Phone and cloud connections of this POS, updated as they change.
final hostStatusProvider = StreamProvider<HostStatus>((ref) async* {
  final host = ref.watch(runtimeProvider).host;
  yield host.status;
  await for (final _ in host.changes) {
    yield host.status;
  }
});

/// The device runtime (waiter / kitchen mode only).
final deviceRuntimeProvider = Provider<DeviceRuntime>((ref) {
  final s = ref.watch(appControllerProvider);
  if (s is AppDevice) return s.device;
  throw StateError('Not in device mode');
});
