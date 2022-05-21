import 'package:yaml/yaml.dart';
import 'config_file.dart';

class GraderLocationProperties {
  String workDir = './work';
  String cacheDir = './cache';
  String osImageDir = './alpine';

  GraderLocationProperties();

  factory GraderLocationProperties.fromYamlConfig(YamlMap conf, String nameVariable) {
    var result = GraderLocationProperties();
    if (conf.containsKey('working_directory')) {
      result.workDir = expandPathEnvVariables(conf['working_directory'], nameVariable);
    }
    if (conf.containsKey('cache_directory')) {
      result.cacheDir = expandPathEnvVariables(conf['cache_directory'], nameVariable);
    }
    if (conf.containsKey('system_environment')) {
      result.osImageDir = expandPathEnvVariables(conf['system_environment'], nameVariable);
    }
    return result;
  }
}