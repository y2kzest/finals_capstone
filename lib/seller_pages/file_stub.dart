// Stub so fill_business_info.dart compiles on web where dart:io is unavailable.
// The real dart:io File class is used only on mobile/desktop (guarded by kIsWeb).

import 'dart:typed_data';

class File {
  final String path;
  File(this.path);
  Future<Uint8List> readAsBytes() async => Uint8List(0);
}
