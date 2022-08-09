import 'dart:io';

import 'package:yaml/yaml.dart';

import 'config_file.dart';

class DatabaseProperties {
  late final String engine;
  late final String host;
  late final int port;
  late final String user;
  late final String password;
  late final String dbName;

  DatabaseProperties({
    required this.engine,
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.dbName,
  });

  factory DatabaseProperties.fromYamlConfig(dynamic confArgument, {
    String parentConfigFileName = '', String instanceName = '',
  }) {
    YamlMap conf;
    if (confArgument is String) {
      final parentConfigFile = File(parentConfigFileName);
      final parentConfigDirectory = parentConfigFile.parent;
      final targetFileTemplate = '${parentConfigDirectory.path}/$confArgument';
      final targetFileName = expandPathEnvVariables(targetFileTemplate, instanceName);
      conf = parseYamlConfig(targetFileName);
    }
    else {
      conf = confArgument as YamlMap;
    }
    String engine = conf.containsKey('engine')? conf['engine'] : 'postgres';
    int port = 0;
    if (conf.containsKey('port')) {
      port = conf['port'] as int;
    } else {
      switch (engine) {
        case 'postgres':
          port = 5432; break;
        case 'mysql':
        case 'mariadb':
          port = 3306; break;
      }
    }
    String host = conf.containsKey('host')? conf['host'] : 'localhost';
    String user = conf.containsKey('user')? conf['user'] : '';
    String password = conf.containsKey('password')? conf['password'] : '';
    String dbName = conf.containsKey('name')? conf['name'] : '';
    if (conf.containsKey('password_file')) {
      password = readPrivateTokenFromFile(conf['password_file']);
    }
    return DatabaseProperties(
        engine: engine,
        host: host,
        port: port,
        user: user,
        password: password,
        dbName: dbName,
        );
  }
}

