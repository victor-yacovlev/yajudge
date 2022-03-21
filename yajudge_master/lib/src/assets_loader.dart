import 'generated/assets.gen.dart' as assets;
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:convert' as convert;
import 'dart:io' as io;

final assetsLoader = AssetsLoader();

class AssetsLoader {
  static FileSet? _fileSet;

  AssetsLoader() {
    if (_fileSet == null) {
      final b64 = assets.fileset;
      final compressed = convert.base64.decode(b64);
      final proto = io.gzip.decode(compressed);
      _fileSet = FileSet.fromBuffer(proto);
    }
  }

  File file(String name) {
    for (final f in _fileSet!.files) {
      if (f.name == name) {
        return f;
      }
    }
    return File();
  }

  List<int> fileAsBytes(String name) {
    return file(name).data;
  }

  String fileAsString(String name) {
    return convert.utf8.decode(fileAsBytes(name));
  }
}