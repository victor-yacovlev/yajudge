import 'dart:io' as io;
import 'package:yajudge_common/yajudge_common.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';

// TODO make this script integrated into dart build_runner

void build_assets() {
  final fileSet = getFileSet();
  final proto = fileSet.writeToBuffer();
  final compressed = io.gzip.encode(proto);
  final b64 = base64.encode(compressed);
  final dartSource = 'final fileset = \'$b64\';\n';
  final packageRoot = path.normalize(io.Platform.script.path +'/../../');
  final packageDir = io.Directory(packageRoot);
  final generatedDir = io.Directory(packageDir.path + '/lib/src/generated');
  if (!generatedDir.existsSync()) {
    generatedDir.createSync(recursive: true);
  }
  final assetsFile = io.File(generatedDir.path + '/assets.gen.dart');
  assetsFile.writeAsStringSync(dartSource);
}

FileSet getFileSet() {
  final packageRoot = path.normalize(io.Platform.script.path +'/../../');
  final packageDir = io.Directory(packageRoot);
  final resourcesDir = io.Directory(packageDir.path + '/resources');
  if (!resourcesDir.existsSync()) {
    return FileSet();
  }
  List<File> files = [];
  for (final entry in resourcesDir.listSync()) {
    if (entry is io.File) {
      String name = path.basename(entry.path);
      List<int> content = entry.readAsBytesSync();
      files.add(File(name: name, data: content));
    }
  }
  return FileSet(files: files);
}

void main() {
  build_assets();
}