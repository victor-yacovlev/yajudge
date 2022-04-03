import 'dart:async';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'dart:io' as io;
import 'package:yajudge_common/yajudge_common.dart';
import 'src/master_service.dart';
import 'package:postgres/postgres.dart';
import 'package:yaml/yaml.dart';
import 'src/database_initialization.dart' as dbInit;

Future<void> main(List<String> arguments) async {
  print('Starting at pid ${io.pid} with arguments: $arguments');

  ArgResults parsedArguments = parseArguments(arguments);


  String configFileName = getConfigFileName(parsedArguments);
  print('Using config file $configFileName');
  dynamic config;
  try {
    config = parseYamlConfig(configFileName);
    print('Successfully parsed config file');
  }
  catch (e) {
    print('Cant parse config file $configFileName: $e');
    io.exit(1);
  }

  print('Configuring logger');
  final logFilePath = getLogFileName(parsedArguments);
  if (logFilePath.isNotEmpty && logFilePath!='stdout') {
    print('Using log file $logFilePath');
    final logFile = io.File(logFilePath);
    try {
      logFile.writeAsStringSync(
        '=== Using this file for master service log ===',
        mode: io.FileMode.append,
        flush: true,
      );
    }
    catch (e) {
      print('Cant use $logFilePath as log file: $e');
      io.exit(1);
    }
    initializeLogger(logFile.openWrite(mode: io.FileMode.append));
    print('Logger initialized so next non-critical messages will be in $logFilePath');

    // duplicate initialization messages to log file
    Logger.root.info('Starting master daemon at PID = ${io.pid}');
    Logger.root.info('Using config file ${configFileName}');

  }
  else {
    print('Log file not set so will use stdout for logging');
    initializeLogger(io.stdout);
  }

  String pidFilePath = getPidFileName(parsedArguments);
  Logger.root.info('Using PID file $pidFilePath');
  try {
    io.File(pidFilePath).writeAsStringSync('${io.pid}');
    print('Using PID file $pidFilePath: written value ${io.pid}');
  }
  catch (e) {
    Logger.root.severe('Cant create PID file $pidFilePath: $e');
  }

  RpcProperties rpcProperties;
  try {
    rpcProperties = RpcProperties.fromYamlConfig(config['rpc']);
  }
  catch (e) {
    final message = 'Cant get RPC properties from config: $e';
    print(message);
    Logger.root.shout(message);
    io.exit(1);
  }
  if (rpcProperties.privateToken.isEmpty) {
    final message = 'Fatal error: private rpc token is empty. Check your configuration';
    print(message);
    Logger.root.shout(message);
    io.exit(1);
  }
  final locationProperties = MasterLocationProperties.fromYamlConfig(config['locations']);
  
  DemoModeProperties? demoModeProperties;
  if (config['demo_mode'] is YamlMap) {
    demoModeProperties = DemoModeProperties.fromYamlConfig(config['demo_mode']);
    Logger.root.info('Will run in demo mode using course ${demoModeProperties.publicCourse}');
  }

  DatabaseProperties databaseProperties;
  try {
    databaseProperties = DatabaseProperties.fromYamlConfig(config['database']);
  }
  catch (e) {
    final message = 'Cant get database properties from config: $e';
    print(message);
    Logger.root.shout(message);
    io.exit(1);
  }
  final postgreSQLConnection = PostgreSQLConnection(
    databaseProperties.host,
    databaseProperties.port,
    databaseProperties.dbName,
    username: databaseProperties.user,
    password: databaseProperties.password,
  );
  final futureConnectionOpen = postgreSQLConnection.open();
  futureConnectionOpen.catchError((error) {
    final message = '''Fatal error: no connection to database: $error   
    Maybe you have not created database or user/password matching configuration.
    
    Run the following:
    > psql postgres  # might require root privileges
    postgres=# create database ${databaseProperties.dbName};
    postgres=# create user ${databaseProperties.user} with password 'password value stored in secret file';
    postgres=# grant all privileges on database ${databaseProperties.dbName} to ${databaseProperties.user}; 
    ''';
    print(message);
    Logger.root.shout(message);
    Future.delayed(Duration(seconds: 2), () {
      io.exit(1);
    });
  });

  futureConnectionOpen.then((_) async {
    Logger.root.fine('opened connection to database');
    Logger.root.info('starting master service on ${rpcProperties.host}:${rpcProperties.port}');
    try {
      final masterService = MasterService(
        connection: postgreSQLConnection,
        rpcProperties: rpcProperties,
        locationProperties: locationProperties,
        demoModeProperties: demoModeProperties,
      );
      ArgResults? command = parsedArguments.command;
      bool initDbMode = command!=null && command.name=='initialize-database';
      if (initDbMode) {
        await dbInit.initializeDatabase(masterService);
        io.exit(0);
      }
      bool databaseOk = await dbInit.checkTablesExists(masterService);
      if (!databaseOk) {
        final message = 'Database not initialized properly. Run yajudge-master with initialize-database subcommand';
        print(message);
        Logger.root.shout(message);
        io.exit(1);
      }
      bool createAdminMode = command!=null && command.name=='create-admin';
      if (createAdminMode) {
        if (command.rest.length < 2) {
          print('create-admin requires two additional arguments: email and password');
          io.exit(1);
        }
        String email = command.rest[0];
        String password = command.rest[1];
        await dbInit.createAdministratorUser(masterService, email, password);
        io.exit(0);
      }
      Logger.root.info('master service ready');
      masterService.serveSupervised();
    } catch (error) {
      print('cant start master server: $error');
      Logger.root.shout('cant start master server: $error');
      io.exit(1);
    }
  });
}

String getConfigFileName(ArgResults parsedArguments) {
  String? configFileName = parsedArguments['config'];
  if (configFileName == null) {
    configFileName = findConfigFile('master');
  }
  if (configFileName.isEmpty) {
    print('No config file specified');
    io.exit(1);
  }
  return configFileName;
}

String getPidFileName(ArgResults parsedArguments) {
  String? pidFileName = parsedArguments['pid'];
  if (pidFileName == null) {
    String configFileName = getConfigFileName(parsedArguments);
    final conf = loadYaml(io.File(configFileName).readAsStringSync());
    if (conf['service'] is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], '');
      pidFileName = serviceProperties.pidFilePath;
    }
  }
  if (pidFileName == null) {
    print("No pid file specified");
    io.exit(1);
  }
  return pidFileName;
}

String getLogFileName(ArgResults parsedArguments) {
  String? logFileName = parsedArguments['log'];
  if (logFileName == null) {
    String configFileName = getConfigFileName(parsedArguments);
    final conf = loadYaml(io.File(configFileName).readAsStringSync());
    if (conf['service'] is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], '');
      logFileName = serviceProperties.logFilePath;
    }
  }
  if (logFileName == null) {
    logFileName = 'stdout';
  }
  return logFileName;
}

void initializeLogger(io.IOSink? target) {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) async {
    String messageLine = '${record.time}: ${record.level.name} - ${record
        .message}\n';
    List<int> bytes = utf8.encode(messageLine);
    if (target != null) {
      target.add(bytes);
    }
  });
  if (target != null) {
    Timer.periodic(Duration(milliseconds: 250), (timer) {
      target.flush();
    });
  }
}

ArgResults parseArguments(List<String> arguments) {
  final mainParser = ArgParser();
  mainParser.addOption('config', abbr: 'C', help: 'config file name');
  mainParser.addOption('log', abbr: 'L', help: 'log file name');
  mainParser.addOption('pid', abbr: 'P', help: 'pid file name');

  final runParser = ArgParser();
  final daemonParser = ArgParser();

  mainParser.addCommand('daemon', daemonParser);
  mainParser.addCommand('start');
  mainParser.addCommand('stop');
  mainParser.addCommand('initialize-database');
  mainParser.addCommand('create-admin');

  final parsedArguments = mainParser.parse(arguments);
  return parsedArguments;
}
