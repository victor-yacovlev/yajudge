import 'package:path/path.dart';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

String findConfigFile(String baseName) {
  String homeDir = Platform.environment['HOME']!;
  List<String> variants = [
    homeDir + '/.config/yajudge/' + baseName + '.yaml',
    '/etc/yajudge/' + baseName + '.yaml'
  ];
  for (String item in variants) {
    if (File(item).existsSync()) {
      return path.normalize(item);
    }
  }
  return '';
}

dynamic parseYamlConfig(String fileName) {
  File file = File(fileName);
  String content = file.readAsStringSync();
  return loadYaml(content, sourceUrl: Uri(path: fileName));
}

String expandPathEnvVariables(String source, String nameVariable) {
  String binDir = path.absolute(dirname(Platform.script.path));
  String expanded = source;
  final rxEnvVar = RegExp(r'(\$[A-Z0-9_a-z]+)');
  Map<String,String> env = Map.from(Platform.environment);
  env['YAJUDGE_BINDIR'] = binDir;
  if (!env.containsKey('RUNTIME_DIRECTORY')) {
    env['RUNTIME_DIRECTORY'] = '/run/yajudge';
  }
  if (!env.containsKey('CACHE_DIRECTORY')) {
    env['CACHE_DIRECTORY'] = '/var/cache/yajudge';
  }
  if (!env.containsKey('STATE_DIRECTORY')) {
    env['STATE_DIRECTORY'] = '/var/lib/yajudge';
  }
  if (!env.containsKey('LOGS_DIRECTORY')) {
    env['LOGS_DIRECTORY'] = '/var/log/yajudge';
  }
  if (!env.containsKey('CONFIGURATION_DIRECTORY')) {
    env['CONFIGURATION_DIRECTORY'] = '/etc/yajudge';
  }
  if (!env.containsKey('SERVE_DIRECTORY')) {
    env['SERVE_DIRECTORY'] = '/srv/yajudge';
  }
  env['NAME'] = nameVariable;
  while (rxEnvVar.hasMatch(expanded)) {
    RegExpMatch match = rxEnvVar.firstMatch(expanded)!;
    String key = match.group(1)!.substring(1);
    if (env.containsKey(key)) {
      String value = env[key]!;
      expanded = expanded.replaceAll(r'$'+key, value);
    }
  }
  return path.absolute(expanded);
}

String readPrivateTokenFromFile(String fileName) {
  final expanded = expandPathEnvVariables(fileName, '');
  return File(expanded).readAsStringSync().trim();
}
