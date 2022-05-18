import 'package:yaml/yaml.dart';

class DemoModeProperties {
  final String publicCourse;
  final String userNamePattern;
  final String groupAssignment;
  
  DemoModeProperties({
    required this.publicCourse,
    required this.userNamePattern,
    required this.groupAssignment,
  });

  factory DemoModeProperties.fromYamlConfig(YamlMap conf) {
    String publicCourse = '';
    String userNamePattern = 'User%id';
    String groupAssignment = 'demo';
    if (conf['public_course'] is String) {
      publicCourse = conf['public_course'];
    }
    if (conf['user_name_pattern'] is String) {
      userNamePattern = conf['user_name_pattern'];
    }
    if (conf['group_assignment'] is String) {
      groupAssignment = conf['group_assignment'];
    }
    return DemoModeProperties(
      publicCourse: publicCourse,
      userNamePattern: userNamePattern,
      groupAssignment: groupAssignment,
    );
  }
}