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

String expandPathEnvVariables(String source) {
  String binDir = path.normalize(path.absolute(dirname(Platform.script.path)));
  String expanded = source;
  final rxEnvVar = RegExp(r'(\$[A-Z0-9_a-z]+)');
  Map<String,String> env = Map.from(Platform.environment);
  env['YAJUDGE_BINDIR'] = binDir;
  while (rxEnvVar.hasMatch(expanded)) {
    RegExpMatch match = rxEnvVar.firstMatch(expanded)!;
    String key = match.group(1)!.substring(1);
    if (Platform.environment.containsKey(key)) {
      String value = Platform.environment[key]!;
      expanded = expanded.replaceAll(r'$'+key, value);
    }
  }
  return path.normalize(path.absolute(expanded));
}