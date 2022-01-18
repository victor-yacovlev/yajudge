import 'package:yaml/yaml.dart';

class MasterLocationProperties {
  late final String coursesRoot;

  MasterLocationProperties({required this.coursesRoot});

  factory MasterLocationProperties.fromYamlConfig(YamlMap conf) {
    return MasterLocationProperties(coursesRoot: conf['courses_root']);
  }
}
