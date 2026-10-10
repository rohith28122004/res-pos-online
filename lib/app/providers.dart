import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/security/permissions.dart';
import '../features/settings/application/printer_service.dart';
import '../features/shifts/application/shift_service.dart';
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

class AppFailed extends AppState {
  const AppFailed(this.error);
  final Object error;
}

class AppController extends Notifier<AppState> {
  AppPaths? _paths;
  InstanceLock? _lock;
  AppRuntime? _runtime;
  int _generation = 0;

  @override
  AppState build() {
    ref.onDispose(() {
      unawaited(_runtime?.dispose());
      unawaited(_lock?.release());
    });
    unawaited(Future.microtask(_start));
    return const AppLoading();
  }

  AppPaths get paths => _paths!;

  Future<void> _start() async {
    try {
      _paths = await AppPaths.resolve();
      _lock = await InstanceLock.acquire(_paths!.lockFile);
      if (_lock == null) {
        state = const AppAlreadyRunning();
        return;
      }
      final mode = await _paths!.readMode();
      if (mode == null) {
        state = const AppChooseMode();
        return;
      }
      await _open(mode);
    } on Object catch (e) {
      state = AppFailed(e);
    }
  }

  Future<void> _open(AppMode mode) async {
    state = const AppLoading();
    try {
      final rt = await AppRuntime.open(_paths!, mode);
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

  Future<void> chooseMode(AppMode mode) async {
    await _paths!.writeMode(mode);
    await _open(mode);
  }

  Future<void> setupCompleted() async {
    final rt = _runtime!;
    await rt.startBackground();
    state = AppReady(rt, ++_generation);
  }

  Future<void> switchMode(AppMode mode) async {
    ref.read(sessionProvider.notifier).logout();
    await _runtime?.dispose();
    _runtime = null;
    await _paths!.writeMode(mode);
    await _open(mode);
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
