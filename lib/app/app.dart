import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/lock_screen.dart';
import '../features/setup/presentation/setup_screens.dart';
import '../shared/widgets/common.dart';
import 'providers.dart';
import 'shell.dart';
import 'theme.dart';

class CafeDeskApp extends ConsumerWidget {
  const CafeDeskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final Widget home = switch (state) {
      AppLoading() => const Scaffold(body: LoadingView(label: 'Opening CaféDesk…')),
      AppAlreadyRunning() => const _AlreadyRunning(),
      AppChooseMode() => const WelcomeScreen(),
      AppNeedsSetup() => const SetupWizard(),
      AppReady(:final generation) => _Authenticated(key: ValueKey(generation)),
      AppFailed(:final error) => Scaffold(
        body: ErrorView(error: error, onRetry: () => ref.read(appControllerProvider.notifier).retry()),
      ),
    };
    return MaterialApp(
      title: 'CaféDesk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: home,
    );
  }
}

class _Authenticated extends ConsumerWidget {
  const _Authenticated({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(sessionProvider);
    if (actor == null) return const LockScreen();
    if (actor.mustChangePassword) return InactivityGuard(child: PasswordChangeRequiredScreen(actor: actor));
    return InactivityGuard(child: AppShell(key: ValueKey(actor.staffId)));
  }
}

class _AlreadyRunning extends StatelessWidget {
  const _AlreadyRunning();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: EmptyState(
      icon: Icons.copy_all_outlined,
      title: 'CaféDesk is already open',
      message:
          'Only one CaféDesk window can use the data on this computer at a time. '
          'Switch to the window that is already open, or close it and start CaféDesk again.',
    ),
  );
}
