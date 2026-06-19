import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config.dart';
import '../core/device_id.dart';
import '../core/supabase_service.dart';
import 'auth_state.dart';

/// Persists the validated access code (the app's "session credential").
/// Abstracted so tests can inject an in-memory store. The device_id lives in
/// [DeviceIdProvider] under a different key and is intentionally NOT touched
/// here — logout keeps the device registered.
abstract class SessionStore {
  Future<String?> readCode();
  Future<void> writeCode(String code);
  Future<void> clearCode();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'zen_code';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readCode() => _storage.read(key: _key);
  @override
  Future<void> writeCode(String code) => _storage.write(key: _key, value: code);
  @override
  Future<void> clearCode() => _storage.delete(key: _key);
}

/// Validates the access code via [SupabaseService], persists it on success,
/// and silently re-validates on launch.
class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required SupabaseService service,
    required SessionStore store,
    required Future<String> Function() deviceId,
    required Future<String> Function() deviceName,
  })  : _service = service,
        _store = store,
        _deviceId = deviceId,
        _deviceName = deviceName,
        super(const AuthState.restoring());

  final SupabaseService _service;
  final SessionStore _store;
  final Future<String> Function() _deviceId;
  final Future<String> Function() _deviceName;

  static final RegExp _codeRe =
      RegExp('^[${AppConfig.codeAlphabet}]{${AppConfig.codeLength}}\$');

  bool _isValidShape(String code) => _codeRe.hasMatch(code);

  /// Validate a user-entered code. Persists it on success.
  Future<void> redeem(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (!_isValidShape(code)) {
      state = state.copyWith(status: AuthStatus.error, errorCode: 'INVALID_CODE', busy: false);
      return;
    }
    state = state.copyWith(busy: true);
    await _validate(code, persistOnSuccess: true);
  }

  /// Re-validate a stored code at launch. No-op -> unauthenticated if none.
  Future<void> restore() async {
    final stored = await _store.readCode();
    if (stored == null || stored.isEmpty) {
      state = const AuthState.unauthenticated();
      return;
    }
    state = const AuthState.restoring();
    await _validate(stored, persistOnSuccess: false, isRestore: true);
  }

  Future<void> _validate(String code,
      {required bool persistOnSuccess, bool isRestore = false}) async {
    try {
      final id = await _deviceId();
      final name = await _deviceName();
      final r = await _service.redeemAccessCode(code, id, name);
      if (persistOnSuccess) await _store.writeCode(code);
      state = AuthState(
        status: AuthStatus.authenticated,
        accountId: r.accountId,
        maxDevices: r.maxDevices,
        deviceCount: r.deviceCount,
      );
    } on BackendException catch (e) {
      state = _mapError(e, isRestore: isRestore);
      if (e.code == 'INVALID_CODE') {
        await _store.clearCode();
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorCode: 'EXCEPTION',
        errorDetail: e.toString(),
      );
    }
  }

  AuthState _mapError(BackendException e, {required bool isRestore}) {
    switch (e.code) {
      case 'DEVICE_LIMIT_REACHED':
        return const AuthState(status: AuthStatus.deviceLimit, errorCode: 'DEVICE_LIMIT_REACHED');
      case 'ACCOUNT_BLOCKED':
        return const AuthState(status: AuthStatus.blocked, errorCode: 'ACCOUNT_BLOCKED');
      case 'ACCOUNT_EXPIRED':
        return const AuthState(status: AuthStatus.expired, errorCode: 'ACCOUNT_EXPIRED');
      case 'NETWORK':
        return AuthState(
            status: isRestore ? AuthStatus.offline : AuthStatus.error,
            errorCode: 'NETWORK',
            errorDetail: e.detail);
      case 'INVALID_CODE':
      default:
        return AuthState(status: AuthStatus.error, errorCode: e.code, errorDetail: e.detail);
    }
  }

  /// Self-service registration: create a brand-new access code tagged with
  /// [label] (the owner's name). Returns the new code so the UI can show it;
  /// does NOT log in (the caller redeems it after the user notes the code).
  /// On failure returns null and the error is reflected in [state].
  Future<String?> createCode(String label) async {
    final name = label.trim();
    if (name.isEmpty) {
      state = state.copyWith(
          status: AuthStatus.error, errorCode: 'LABEL_REQUIRED', busy: false);
      return null;
    }
    state = state.copyWith(busy: true);
    try {
      final code = await _service.createAccessCode(name);
      state = state.copyWith(busy: false);
      return code;
    } on BackendException catch (e) {
      state = _mapError(e, isRestore: false);
      return null;
    }
  }

  /// Current stored code (for source RPCs that need it). Null if none.
  Future<String?> currentCode() => _store.readCode();

  Future<void> logout() async {
    await _store.clearCode();
    state = const AuthState.unauthenticated();
  }
}

/// App-wide providers. [deviceIdProvider] wraps the secure-storage device id.
final supabaseServiceProvider = Provider<SupabaseService>((ref) => SupabaseService());

final deviceIdProvider = Provider<DeviceIdProvider>((ref) => DeviceIdProvider());

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final svc = ref.watch(supabaseServiceProvider);
  final dev = ref.watch(deviceIdProvider);
  return AuthController(
    service: svc,
    store: SecureSessionStore(),
    deviceId: dev.deviceId,
    deviceName: dev.deviceName,
  );
});
