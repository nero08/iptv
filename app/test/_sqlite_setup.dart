import 'dart:ffi';

import 'package:sqlite3/open.dart';

/// Host-side test setup: drift's NativeDatabase needs a loadable libsqlite3.
/// `sqlite3_flutter_libs` only ships the Android .so, so on the Linux test host
/// we point the loader at the system library (the unversioned symlink is often
/// absent, but libsqlite3.so.0 exists).
void useSystemSqlite() {
  open.overrideFor(OperatingSystem.linux, () {
    for (final candidate in const [
      'libsqlite3.so',
      'libsqlite3.so.0',
      '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
      '/lib/x86_64-linux-gnu/libsqlite3.so.0',
    ]) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (_) {
        // try next
      }
    }
    throw StateError('No system libsqlite3 found for tests');
  });
}
