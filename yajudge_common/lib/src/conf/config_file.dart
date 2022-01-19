import 'package:path/path.dart';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

String? findConfigFile(String baseName) {
  String binDir = dirname(Platform.script.path);
  String homeDir = Platform.environment['HOME']!;
  List<String> variants = [
    homeDir + '/.config/yajudge/' + baseName + '.yaml',
    binDir + '/../../conf/' + baseName + '.yaml',
    binDir + '/../conf/' + baseName + '.yaml',
    '/etc/yajudge/' + baseName + '.yaml'
  ];
  for (String item in variants) {
    if (File(item).existsSync()) {
      return path.normalize(item);
    }
  }
  return null;
}

dynamic parseYamlConfig(String fileName) {
  File file = File(fileName);
  String content = file.readAsStringSync();
  return loadYaml(content, sourceUrl: Uri(path: fileName));
}