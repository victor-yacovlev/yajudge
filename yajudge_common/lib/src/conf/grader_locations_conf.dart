import 'package:yaml/yaml.dart';
import 'config_file.dart';

class GraderLocationProperties {
  String workDir = './work';
  String coursesCacheDir = './cache';
  String osImageDir = './alpine';

  GraderLocationProperties();

  factory GraderLocationProperties.fromYamlConfig(YamlMap conf) {
    var result = GraderLocationProperties();
    if (conf.containsKey('working_directory'))
      result.workDir = expandPathEnvVariables(conf['working_directory']);
    if (conf.containsKey('cache_directory'))
      result.coursesCacheDir = expandPathEnvVariables(conf['cache_directory']);
    if (conf.containsKey('system_environment'))
      result.osImageDir = expandPathEnvVariables(conf['system_environment']);
    return result;
  }
}