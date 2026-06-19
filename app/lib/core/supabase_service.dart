import 'package:dio/dio.dart';

import 'config.dart';

/// Thrown when a backend RPC returns a PostgREST error. [code] is the backend's
/// `message` (e.g. INVALID_CODE, ACCOUNT_BLOCKED, ACCOUNT_EXPIRED,
/// DEVICE_LIMIT_REACHED, DEVICE_NOT_REGISTERED, INVALID_OR_INACTIVE), or
/// `NETWORK` for connectivity failures.
class BackendException implements Exception {
  BackendException(this.code, [this.detail]);
  final String code;
  final String? detail;

  bool get isNetwork => code == 'NETWORK';

  @override
  String toString() => 'BackendException($code${detail != null ? ': $detail' : ''})';
}

/// Result of `redeem_access_code`.
class RedeemResult {
  RedeemResult({
    required this.accountId,
    required this.status,
    required this.maxDevices,
    required this.deviceCount,
  });

  final String accountId;
  final String status;
  final int maxDevices;
  final int deviceCount;

  factory RedeemResult.fromJson(Map<String, dynamic> j) => RedeemResult(
        accountId: j['account_id'] as String,
        status: j['status'] as String,
        maxDevices: (j['max_devices'] as num).toInt(),
        deviceCount: (j['device_count'] as num).toInt(),
      );
}

/// Thin PostgREST RPC client for the two anon RPCs the app uses. All calls send
/// the `apikey` header (Supabase anon key) and POST a JSON body to
/// `/rest/v1/rpc/<fn>`.
class SupabaseService {
  SupabaseService({Dio? dio, String? anonKey})
      : _anonKey = anonKey ?? AppConfig.anonKey,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.backendUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;
  final String _anonKey;

  Future<List<dynamic>> _rpc(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>(
        '/rest/v1/rpc/$fn',
        data: body,
        options: Options(
          headers: {
            'apikey': _anonKey,
            'Content-Type': 'application/json',
          },
          // We handle non-2xx ourselves to map PostgREST error JSON.
          validateStatus: (_) => true,
        ),
      );
      final data = res.data;
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        if (data is List) return data;
        if (data is Map) return [data];
        return const [];
      }
      // Error path: PostgREST returns {message, code, details, hint}.
      throw BackendException(_extractMessage(data), _extractDetail(data));
    } on DioException catch (e) {
      if (e.error is BackendException) throw e.error as BackendException;
      // Connectivity / timeout / DNS — distinct from a backend rejection.
      throw BackendException('NETWORK', e.message);
    }
  }

  static String _extractMessage(dynamic data) {
    if (data is Map && data['message'] is String) return data['message'] as String;
    return 'UNKNOWN';
  }

  static String? _extractDetail(dynamic data) {
    if (data is Map && data['details'] is String) return data['details'] as String;
    return null;
  }

  /// Validate an access code + register/refresh the device. Throws
  /// [BackendException] on rejection.
  Future<RedeemResult> redeemAccessCode(
      String code, String deviceId, String? deviceName) async {
    final rows = await _rpc('redeem_access_code', {
      'p_code': code,
      'p_device_id': deviceId,
      if (deviceName != null) 'p_device_name': deviceName,
    });
    if (rows.isEmpty) throw BackendException('EMPTY_RESPONSE');
    return RedeemResult.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Self-service: mint a new access code tagged with [label] (the owner's
  /// name, so the admin knows who it belongs to). Returns the generated code.
  /// The new account has no IPTV source until an admin assigns one.
  Future<String> createAccessCode(String label) async {
    final rows = await _rpc('create_access_code', {'p_label': label});
    if (rows.isEmpty) throw BackendException('EMPTY_RESPONSE');
    final m = Map<String, dynamic>.from(rows.first as Map);
    return m['access_code'] as String;
  }

  /// Fetch the account's active IPTV sources (gated by code + registered
  /// device). Returns raw row maps; [SourceRepository] maps them to models.
  Future<List<Map<String, dynamic>>> getSourcesForCode(
      String code, String deviceId) async {
    final rows = await _rpc('get_sources_for_code', {
      'p_code': code,
      'p_device_id': deviceId,
    });
    return rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList(growable: false);
  }
}
