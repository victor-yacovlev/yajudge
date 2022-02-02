import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:yajudge_common/yajudge_common.dart';
import 'src/master_service.dart';
import 'package:postgres/postgres.dart';

Future<void> main([List<String>? arguments]) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.time}: ${record.level.name} - ${record.message}');
  });
  ArgParser parser = ArgParser();
  parser.addOption('config');
  String? configFileName;
  if (arguments != null) {
    ArgResults options = parser.parse(arguments);
    configFileName = options['config'];
  }
  if (configFileName==null || configFileName.isEmpty) {
    configFileName = findConfigFile('master-server');
  }
  if (configFileName==null) {
    print('No config file specified\n');
    exit(1);
  }
  Logger.root.info('using config file $configFileName');
  MasterService? masterService;
  try {
    final config = parseYamlConfig(configFileName);
    DatabaseProperties databaseProperties = DatabaseProperties.fromYamlConfig(
        config['database']!);
    PostgreSQLConnection postgreSQLConnection = PostgreSQLConnection(
      databaseProperties.host,
      databaseProperties.port,
      databaseProperties.dbName,
      username: databaseProperties.user,
      password: databaseProperties.password,
    );
    await postgreSQLConnection.open();
    RpcProperties rpcProperties = RpcProperties.fromYamlConfig(config['rpc']);
    MasterLocationProperties locationProperties = MasterLocationProperties
        .fromYamlConfig(config['locations']);
    masterService = MasterService(
      connection: postgreSQLConnection,
      rpcProperties: rpcProperties,
      locationProperties: locationProperties,
    );
  } catch (error) {
    Logger.root.shout('cant start master server: $error');
  }
  if (masterService != null) {
    Logger.root.info('started master server at PID = $pid');
    masterService.serveSupervised();
  }
}

