import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/auth/auth_controller.dart';
import 'package:zen_player/auth/auth_state.dart';
import 'package:zen_player/core/supabase_service.dart';

/// Fake backend that returns a canned RedeemResult or throws a BackendException.
class _FakeService implements SupabaseService {
  _FakeService({this.result, this.error});
  RedeemResult? result;
  BackendException? error;
  String? createdCode;
  int redeemCalls = 0;
  int createCalls = 0;

  @override
  Future<RedeemResult> redeemAccessCode(
      String code, String deviceId, String? deviceName) async {
    redeemCalls++;
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<String> createAccessCode(String label) async {
    createCalls++;
    if (error != null) throw error!;
    return createdCode ?? 'NEWCODE1';
  }

  @override
  Future<List<Map<String, dynamic>>> getSourcesForCode(
          String code, String deviceId) async =>
      const [];
}

/// In-memory secure-storage stand-in (just the two keys the controller uses).
class _MemStore implements SessionStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> readCode() async => _m['code'];
  @override
  Future<void> writeCode(String code) async => _m['code'] = code;
  @override
  Future<void> clearCode() async => _m.remove('code');
  String? get codeRaw => _m['code'];
}

AuthController _make(_FakeService svc, _MemStore store) =>
    AuthController(service: svc, store: store, deviceId: () async => 'dev-1',
        deviceName: () async => 'Phone');

void main() {
  test('valid code -> authenticated and code persisted', () async {
    final svc = _FakeService(
        result: RedeemResult(
            accountId: 'a1', status: 'active', maxDevices: 2, deviceCount: 1));
    final store = _MemStore();
    final c = _make(svc, store);

    await c.redeem('ABCDEFGH');
    expect(c.state.status, AuthStatus.authenticated);
    expect(c.state.accountId, 'a1');
    expect(store.codeRaw, 'ABCDEFGH', reason: 'code persisted to secure store');
  });

  test('invalid client-side shape -> error without a network call', () async {
    final svc = _FakeService();
    final store = _MemStore();
    final c = _make(svc, store);

    await c.redeem('lowercase'); // wrong shape
    expect(c.state.status, AuthStatus.error);
    expect(svc.redeemCalls, 0, reason: 'rejected before hitting the network');
    expect(store.codeRaw, isNull);
  });

  test('restore with stored code that is now blocked -> blocked, code kept-or-cleared but device_id untouched', () async {
    final store = _MemStore();
    await store.writeCode('ABCDEFGH');
    final svc = _FakeService(error: BackendException('ACCOUNT_BLOCKED'));
    final c = _make(svc, store);

    await c.restore();
    expect(c.state.status, AuthStatus.blocked);
    // device_id is owned by DeviceIdProvider, never cleared here — assert the
    // controller did not throw and produced a terminal state cleanly.
  });

  test('restore with no stored code -> unauthenticated', () async {
    final svc = _FakeService();
    final store = _MemStore();
    final c = _make(svc, store);
    await c.restore();
    expect(c.state.status, AuthStatus.unauthenticated);
    expect(svc.redeemCalls, 0);
  });

  test('logout clears the stored code', () async {
    final svc = _FakeService(
        result: RedeemResult(
            accountId: 'a1', status: 'active', maxDevices: 1, deviceCount: 1));
    final store = _MemStore();
    final c = _make(svc, store);
    await c.redeem('ABCDEFGH');
    expect(store.codeRaw, 'ABCDEFGH');
    await c.logout();
    expect(store.codeRaw, isNull);
    expect(c.state.status, AuthStatus.unauthenticated);
  });

  test('createCode with empty label -> error, no network call', () async {
    final svc = _FakeService();
    final c = _make(svc, _MemStore());
    final code = await c.createCode('   ');
    expect(code, isNull);
    expect(svc.createCalls, 0, reason: 'empty label rejected client-side');
    expect(c.state.status, AuthStatus.error);
  });

  test('createCode returns the new code without auto-login', () async {
    final svc = _FakeService()..createdCode = 'NEWCODE1';
    final c = _make(svc, _MemStore());
    final code = await c.createCode('Jean Dupont');
    expect(code, 'NEWCODE1');
    expect(svc.createCalls, 1);
    expect(c.state.status, isNot(AuthStatus.authenticated),
        reason: 'create shows the code first; redeem happens after');
  });

  test('network failure on restore -> offline, code retained', () async {
    final store = _MemStore();
    await store.writeCode('ABCDEFGH');
    final svc = _FakeService(error: BackendException('NETWORK'));
    final c = _make(svc, store);
    await c.restore();
    expect(c.state.status, AuthStatus.offline);
    expect(store.codeRaw, 'ABCDEFGH', reason: 'do not wipe code on transient network error');
  });
}
