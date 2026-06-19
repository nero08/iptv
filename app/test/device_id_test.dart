import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/core/device_id.dart';

/// In-memory FlutterSecureStorage stand-in for tests.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage() : super();
  final Map<String, String> _m = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _m[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

void main() {
  test('deviceId is stable across calls and persists across instances', () async {
    final storage = _FakeSecureStorage();
    final p1 = DeviceIdProvider(storage: storage);

    final a = await p1.deviceId();
    final b = await p1.deviceId();
    expect(a, isNotEmpty);
    expect(a, b, reason: 'same instance returns the cached id');

    // A fresh provider over the same storage must read the persisted id.
    final p2 = DeviceIdProvider(storage: storage);
    final c = await p2.deviceId();
    expect(c, a, reason: 'persisted id survives a new provider instance');
  });
}
