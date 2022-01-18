import 'package:yaml/yaml.dart';

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

  factory DatabaseProperties.fromYamlConfig(YamlMap conf) {
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

