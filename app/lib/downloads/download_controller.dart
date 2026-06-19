import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_db.dart';
import '../sources/source_repository.dart';

/// Manages VOD/episode downloads to app-internal storage (no permission needed
/// on Android 13+). Tracks progress + status in drift; supports offline play.
class DownloadController {
  DownloadController(this._db, {Dio? dio}) : _dio = dio ?? Dio();
  final AppDatabase _db;
  final Dio _dio;
  final Map<String, CancelToken> _active = {};

  /// In-memory progress 0..1 by itemKey (UI watches this).
  final progress = <String, double>{};

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'downloads'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<Download>> list() => _db.select(_db.downloads).get();

  Future<void> start({
    required String itemKey,
    required String title,
    required String url,
    required String ext,
  }) async {
    final dir = await _dir();
    final safe = itemKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = p.join(dir.path, '$safe.$ext');
    final token = CancelToken();
    _active[itemKey] = token;

    await _db.into(_db.downloads).insert(
          DownloadsCompanion.insert(
              itemKey: itemKey,
              title: title,
              filePath: path,
              status: const Value('downloading')),
          mode: InsertMode.insertOrReplace,
        );
    try {
      await _dio.download(url, path, cancelToken: token,
          onReceiveProgress: (rec, total) {
        if (total > 0) progress[itemKey] = rec / total;
      });
      final bytes = await File(path).length();
      await _update(itemKey, status: 'done', bytes: bytes);
    } catch (e) {
      // Only DioExceptions can be cancellations; any other error (disk full,
      // TLS handshake, FileSystemException) must fall through to 'error' — a
      // forced `e as DioException` cast here would itself throw and skip cleanup.
      if (e is DioException && CancelToken.isCancel(e)) {
        await _delete(itemKey, path);
      } else {
        await _update(itemKey, status: 'error');
      }
    } finally {
      _active.remove(itemKey);
      progress.remove(itemKey);
    }
  }

  Future<void> cancel(String itemKey) async {
    _active[itemKey]?.cancel('user');
  }

  Future<void> remove(String itemKey) async {
    final row = await (_db.select(_db.downloads)
          ..where((t) => t.itemKey.equals(itemKey)))
        .getSingleOrNull();
    await _delete(itemKey, row?.filePath);
  }

  Future<String?> localPath(String itemKey) async {
    final row = await (_db.select(_db.downloads)
          ..where((t) => t.itemKey.equals(itemKey) & t.status.equals('done')))
        .getSingleOrNull();
    if (row == null) return null;
    return await File(row.filePath).exists() ? row.filePath : null;
  }

  Future<void> _update(String itemKey, {String? status, int? bytes}) async {
    await (_db.update(_db.downloads)..where((t) => t.itemKey.equals(itemKey)))
        .write(DownloadsCompanion(
      status: status != null ? Value(status) : const Value.absent(),
      bytes: bytes != null ? Value(bytes) : const Value.absent(),
    ));
  }

  Future<void> _delete(String itemKey, String? path) async {
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await (_db.delete(_db.downloads)..where((t) => t.itemKey.equals(itemKey)))
        .go();
  }
}

final downloadControllerProvider = Provider<DownloadController>(
    (ref) => DownloadController(ref.watch(appDatabaseProvider)));

final downloadsListProvider = FutureProvider.autoDispose<List<Download>>((ref) {
  return ref.watch(downloadControllerProvider).list();
});
