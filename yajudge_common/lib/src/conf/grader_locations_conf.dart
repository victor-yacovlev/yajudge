import 'package:yaml/yaml.dart';

class GraderLocationProperties {
  String workDir = './work';
  String coursesCacheDir = './cache';
  String osImageDir = './os';

  GraderLocationProperties();

  factory GraderLocationProperties.fromYamlConfig(YamlMap conf) {
    var result = GraderLocationProperties();
    if (conf.containsKey('work_dir'))
      result.workDir = conf['work_dir'];
    if (conf.containsKey('courses_cache_dir'))
      result.coursesCacheDir = conf['courses_cache_dir'];
    if (conf.containsKey('os_image_dir'))
      result.osImageDir = conf['os_image_dir'];
    return result;
  }
}