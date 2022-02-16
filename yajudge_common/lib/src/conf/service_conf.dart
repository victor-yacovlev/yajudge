import 'package:yaml/yaml.dart';

import 'config_file.dart';

class ServiceProperties {
  final String logFilePath;
  final String pidFilePath;
  final String systemdSlice;
  final String runAsUser;
  final String runAsGroup;

  ServiceProperties({
    required this.logFilePath,
    required this.pidFilePath,
    required this.systemdSlice,
    required this.runAsUser,
    required this.runAsGroup,
  });

  factory ServiceProperties.fromYamlConfig(YamlMap conf) {
    String logFilePath = 'grader.log';
    String pidFilePath = 'grader.pid';
    String systemdSlice = 'yajudge';
    String runAsUser = '';
    String runAsGroup = '';
    if (conf['log_file'] is String) {
      logFilePath = expandPathEnvVariables(conf['log_file']);
    }
    if (conf['pid_file'] is String) {
      pidFilePath = expandPathEnvVariables(conf['pid_file']);
    }
    if (conf['systemd_slice'] is String) {
      systemdSlice = conf['systemd_slice'];
    }
    if (conf['user'] is String) {
      runAsUser = conf['user'];
    }
    if (conf['group'] is String) {
      runAsGroup = conf['group'];
    }
    return ServiceProperties(
      logFilePath: logFilePath,
      pidFilePath: pidFilePath,
      systemdSlice: systemdSlice,
      runAsUser: runAsUser,
      runAsGroup: runAsGroup
    );
  }

}