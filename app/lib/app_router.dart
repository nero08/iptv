import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_state.dart';
import 'auth/device_limit_screen.dart';
import 'auth/login_screen.dart';
import 'home/home_shell.dart';
import 'splash_screen.dart';

/// Top-level gate that switches the visible screen based on [AuthState].
///
/// The access-code flow is a small state machine, so a direct switch is clearer
/// than go_router redirects. go_router is still used for in-app navigation
/// (Live/VOD/Series/detail/player) inside the authenticated [HomeShell]
/// (wired in later tasks).
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Restore a stored session exactly once, after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    switch (state.status) {
      case AuthStatus.restoring:
        return const SplashScreen();
      case AuthStatus.authenticated:
        return const HomeShell();
      case AuthStatus.deviceLimit:
      case AuthStatus.blocked:
      case AuthStatus.expired:
        return DeviceLimitScreen(status: state.status);
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
      case AuthStatus.offline:
        return const LoginScreen();
    }
  }
}
