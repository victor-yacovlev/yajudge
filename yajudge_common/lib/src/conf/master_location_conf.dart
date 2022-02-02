import 'config_file.dart';
import 'package:yaml/yaml.dart';

class MasterLocationProperties {
  late final String coursesRoot;
  late final String problemsRoot;

  MasterLocationProperties({required this.coursesRoot, required this.problemsRoot});

  factory MasterLocationProperties.fromYamlConfig(YamlMap conf) {
    return MasterLocationProperties(
      coursesRoot: expandPathEnvVariables(conf['courses_root']),
      problemsRoot: expandPathEnvVariables(conf['problems_root']),
    );
  }
}
