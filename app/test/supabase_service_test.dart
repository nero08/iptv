import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/core/supabase_service.dart';

/// A dio HttpClientAdapter stub that returns a canned response/error so we can
/// test SupabaseService's error mapping without a network call.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

SupabaseService _serviceReturning(int status, String body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _StubAdapter(
    (options) async => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ),
  );
  return SupabaseService(dio: dio, anonKey: 'anon-test');
}

void main() {
  group('SupabaseService.redeemAccessCode', () {
    test('maps PostgREST {"message":"INVALID_CODE"} to BackendException', () async {
      final svc = _serviceReturning(400, '{"message":"INVALID_CODE"}');
      expect(
        () => svc.redeemAccessCode('ABCDEFGH', 'dev-1', 'Phone'),
        throwsA(isA<BackendException>()
            .having((e) => e.code, 'code', 'INVALID_CODE')),
      );
    });

    test('parses a successful redeem response into RedeemResult', () async {
      final svc = _serviceReturning(
        200,
        '[{"account_id":"a-1","status":"active","max_devices":2,"device_count":1}]',
      );
      final r = await svc.redeemAccessCode('ABCDEFGH', 'dev-1', 'Phone');
      expect(r.accountId, 'a-1');
      expect(r.status, 'active');
      expect(r.maxDevices, 2);
      expect(r.deviceCount, 1);
    });

    test('maps DEVICE_LIMIT_REACHED', () async {
      final svc = _serviceReturning(400, '{"message":"DEVICE_LIMIT_REACHED"}');
      expect(
        () => svc.redeemAccessCode('ABCDEFGH', 'dev-1', null),
        throwsA(isA<BackendException>()
            .having((e) => e.code, 'code', 'DEVICE_LIMIT_REACHED')),
      );
    });
  });

  group('SupabaseService.createAccessCode', () {
    test('returns the generated code from create_access_code', () async {
      final svc = _serviceReturning(200, '[{"access_code":"ABCD2345"}]');
      final code = await svc.createAccessCode('Jean Dupont');
      expect(code, 'ABCD2345');
    });

    test('maps LABEL_REQUIRED to BackendException', () async {
      final svc = _serviceReturning(400, '{"message":"LABEL_REQUIRED"}');
      expect(
        () => svc.createAccessCode(''),
        throwsA(isA<BackendException>()
            .having((e) => e.code, 'code', 'LABEL_REQUIRED')),
      );
    });
  });

  group('SupabaseService.getSourcesForCode', () {
    test('parses an array of source rows', () async {
      final svc = _serviceReturning(
        200,
        '[{"id":"s-1","kind":"xtream","name":"P","server_url":"http://h:80",'
        '"username":"u","password":"p","m3u_url":null,"is_active":true}]',
      );
      final rows = await svc.getSourcesForCode('ABCDEFGH', 'dev-1');
      expect(rows, hasLength(1));
      expect(rows.first['kind'], 'xtream');
    });
  });
}
