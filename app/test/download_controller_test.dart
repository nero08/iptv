import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zen_player/data/app_db.dart';
import 'package:zen_player/downloads/download_controller.dart';

import '_sqlite_setup.dart';

/// Adapter that streams fixed bytes back so dio.download writes a real file.
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);
  final List<int> bytes;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody(
        Stream.value(Uint8List.fromList(bytes)),
        200,
        headers: {
          Headers.contentLengthHeader: ['${bytes.length}'],
        },
      );
}

class _NoopAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s,
          Future<void>? c) async =>
      ResponseBody.fromString('', 200);
}

/// A Dio whose `download` throws a caller-supplied error — lets us drive the
/// controller's catch block deterministically (including a NON-DioException,
/// which a forced `e as DioException` cast would crash on).
class _ThrowingDio with DioMixin implements Dio {
  _ThrowingDio(this._error) {
    options = BaseOptions();
    httpClientAdapter = _NoopAdapter();
  }
  final Object _error;

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async =>
      throw _error;
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  setUpAll(useSystemSqlite);

  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('zen_dl_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });
  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('happy path: a download transitions downloading -> done with byte count',
      () async {
    final bytes = List<int>.generate(2048, (i) => i % 256);
    final dio = Dio(BaseOptions(baseUrl: 'http://t.local'));
    dio.httpClientAdapter = _BytesAdapter(bytes);
    final c = DownloadController(db, dio: dio);

    await c.start(
        itemKey: 's1|vod|1',
        title: 'Movie',
        url: 'http://t.local/m.mp4',
        ext: 'mp4');

    final rows = await c.list();
    expect(rows, hasLength(1));
    expect(rows.single.status, 'done');
    expect(rows.single.bytes, bytes.length);
    expect(await File(rows.single.filePath).exists(), true);
  });

  test('a non-DioException sets status=error and does NOT throw', () async {
    // Regression: a forced `e as DioException` cast crashed here for any
    // non-Dio error (disk full / FS error), skipping cleanup.
    final c =
        DownloadController(db, dio: _ThrowingDio(const FileSystemException('full')));

    // Must complete normally (the bug made this throw a TypeError).
    await c.start(
        itemKey: 's1|vod|2', title: 'Movie', url: 'http://t/m.mp4', ext: 'mp4');

    final rows = await c.list();
    expect(rows.single.status, 'error');
  });

  test('a cancellation deletes the drift row', () async {
    final cancel = DioException(
        requestOptions: RequestOptions(path: '/m'),
        type: DioExceptionType.cancel);
    final c = DownloadController(db, dio: _ThrowingDio(cancel));

    await c.start(
        itemKey: 's1|vod|3', title: 'Movie', url: 'http://t/m.mp4', ext: 'mp4');

    expect(await c.list(), isEmpty);
  });
}
