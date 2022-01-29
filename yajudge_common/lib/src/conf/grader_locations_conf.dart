import 'package:yaml/yaml.dart';

class GraderLocationProperties {
  String workDir = './work';
  String coursesCacheDir = './cache';
  String osImageDir = './alpine';

  GraderLocationProperties();

  factory GraderLocationProperties.fromYamlConfig(YamlMap conf) {
    var result = GraderLocationProperties();
    if (conf.containsKey('work_dir'))
      result.workDir = conf['work_dir'];
    if (conf.containsKey('cache_directory'))
      result.coursesCacheDir = conf['cache_directory'];
    if (conf.containsKey('system_environment'))
      result.osImageDir = conf['system_environment'];
    return result;
  }
}