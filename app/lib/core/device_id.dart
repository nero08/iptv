import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Provides a stable per-install device identifier (generated once, stored in
/// secure storage) and a human-readable device name. The device_id is the key
/// the backend uses to enforce `max_devices`, so it must survive app restarts
/// (but is intentionally regenerated on a full data wipe / reinstall).
class DeviceIdProvider {
  DeviceIdProvider({FlutterSecureStorage? storage, DeviceInfoPlugin? deviceInfo})
      : _storage = storage ?? const FlutterSecureStorage(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static const _key = 'zen_device_id';

  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;

  String? _cached; // in-memory cache — hot path on every RPC

  /// Returns the stable device id, generating+persisting one on first call.
  Future<String> deviceId() async {
    if (_cached != null) return _cached!;
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }
    final generated = const Uuid().v4();
    await _storage.write(key: _key, value: generated);
    _cached = generated;
    return generated;
  }

  /// A best-effort human-readable device name (brand/model) for the backend's
  /// device list. Falls back to a generic label if unavailable.
  Future<String> deviceName() async {
    try {
      final android = await _deviceInfo.androidInfo;
      final brand = android.brand;
      final model = android.model;
      final label = [brand, model].where((s) => s.isNotEmpty).join(' ').trim();
      return label.isEmpty ? 'Android device' : label;
    } catch (_) {
      return 'Android device';
    }
  }
}
