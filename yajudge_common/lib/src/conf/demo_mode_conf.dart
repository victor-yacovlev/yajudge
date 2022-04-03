import 'package:yaml/yaml.dart';

class DemoModeProperties {
  late final String publicCourse;
  late final String userNamePattern;
  
  DemoModeProperties({required this.publicCourse, required this.userNamePattern});

  factory DemoModeProperties.fromYamlConfig(YamlMap conf) {
    String publicCourse = '';
    String userNamePattern = 'User%id';
    if (conf['public_course'] is String) {
      publicCourse = conf['public_course'];
    }
    if (conf['user_name_pattern'] is String) {
      userNamePattern = conf['user_name_pattern'];
    }
    return DemoModeProperties(publicCourse: publicCourse, userNamePattern: userNamePattern);
  }
}