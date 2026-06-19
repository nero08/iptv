/// Auth lifecycle states for the access-code login.
enum AuthStatus {
  /// Restoring a stored session at launch.
  restoring,

  /// No valid code stored - show the login screen.
  unauthenticated,

  /// Code validated and device registered.
  authenticated,

  /// Code rejected (INVALID_CODE) or other non-terminal error to show inline.
  error,

  /// Account exists but device cap exceeded for a new device.
  deviceLimit,

  /// Account is blocked.
  blocked,

  /// Account is expired.
  expired,

  /// Network failure during validation - keep stored code, allow retry.
  offline,
}

/// Immutable auth state exposed by [AuthController].
class AuthState {
  const AuthState({
    required this.status,
    this.accountId,
    this.maxDevices,
    this.deviceCount,
    this.errorCode,
    this.errorDetail,
    this.busy = false,
  });

  final AuthStatus status;
  final String? accountId;
  final int? maxDevices;
  final int? deviceCount;

  /// Raw backend code for the current error/terminal state (for UI mapping).
  final String? errorCode;

  /// Raw detail / message from the exception - shown verbatim in debug UI.
  final String? errorDetail;

  /// True while a redeem/restore network call is in flight.
  final bool busy;

  const AuthState.restoring() : this(status: AuthStatus.restoring);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    String? accountId,
    int? maxDevices,
    int? deviceCount,
    String? errorCode,
    String? errorDetail,
    bool? busy,
  }) {
    return AuthState(
      status: status ?? this.status,
      accountId: accountId ?? this.accountId,
      maxDevices: maxDevices ?? this.maxDevices,
      deviceCount: deviceCount ?? this.deviceCount,
      errorCode: errorCode,
      errorDetail: errorDetail,
      busy: busy ?? this.busy,
    );
  }
}
