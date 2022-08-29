import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart';
import 'package:yaml/yaml.dart';
import 'package:grpc/grpc.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;

import 'services_connector.dart';


abstract class ServiceLauncherBase {

  Future<void> start() {
    return serve(service);
  }

  Future<void> stop() async {
    final serviceName = service.$name;
    final endpoint = rpcProperties.endpoints[serviceName]!;
    if (endpoint.isUnix) {
      final socketFile = io.File(endpoint.unixPath);
      socketFile.deleteSync();
    }
  }

  @protected
  late final RpcProperties rpcProperties;
  @protected
  late final PostgreSQLConnection databaseConnection;
  @protected
  late final DatabaseProperties _databaseProperties;
  @protected
  final String serviceName;
  @protected
  late final String instanceName;
  @protected
  YamlMap? configFile;
  @protected
  late final String? configFileName;
  @protected
  late final io.File? _pidFile;
  @protected
  final Map<String,ArgParser> extraArgParsers;
  final Set<String> _notLoggedMethods = {};
  final Set<String> _servicePrivateMethods = {};
  @protected
  late final Service service;
  @protected
  late final ServicesConnector services;

  @protected
  ServiceLauncherBase(
    this.serviceName,
    {
      this.extraArgParsers = const <String,ArgParser>{},
    }
  );

  @protected
  @mustCallSuper
  Future<void> initialize(List<String> commandLineArguments) async {
    final arguments = _parseArguments(commandLineArguments);
    instanceName = (arguments['name'] as String?) ?? 'default';
    configFileName = (arguments['config'] as String?) ?? _findServiceConfigFile(
        '$serviceName.yaml', instanceName
    );
    if (configFileName!=null && configFileName!.isNotEmpty) {
      try {
        configFile = parseYamlConfig(configFileName!) as YamlMap;
      }
      catch (e) {
        print('FATAL: Cant parse service config file $configFileName: $e');
        io.exit(1);
      }
    }

    String logFileName = _guessOutFileName('log', instanceName);
    String? pidFileName = _guessOutFileName('pid', instanceName);

    final serviceConf = configFile?['service'];
    if (serviceConf is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(
          serviceConf, ''
      );
      pidFileName = serviceProperties.pidFilePath;
      logFileName = serviceProperties.logFilePath;
    }
    if (arguments['pid'] is String) {
      pidFileName = arguments['pid'];
    }
    if (arguments['log'] is String) {
      logFileName = arguments['log'];
    }

    _initializeLogging(logFileName);

    if (pidFileName != null) {
      _pidFile = io.File(pidFileName);
    }
    final rpcConfig = configFile?['rpc'] as YamlMap?;
    if (rpcConfig != null) {
      try {
        rpcProperties = RpcProperties.fromYamlConfig(rpcConfig,
          parentConfigFileName: configFileName!,
          instanceName: instanceName,
        );
      }
      catch (e) {
        Logger.root.shout('cant parse RPC config $e');
        io.exit(1);
      }
    }
    else {
      // no root config file, so use endpoints.yaml and private-token.txt
      final endpointsFile = _findServiceConfigFile('endpoints.yaml', instanceName);
      final tokenFile = _findServiceConfigFile('private-token.txt', instanceName);
      if (endpointsFile == null) {
        Logger.root.shout('no endpoints.yaml found for this configuration');
        io.exit(1);
      }
      if (tokenFile == null) {
        Logger.root.shout('no private-token.txt found for this configuration');
        io.exit(1);
      }
      try {
        final endpointsConf = parseYamlConfig(endpointsFile) as YamlMap;
        final privateToken = io.File(tokenFile).readAsStringSync().trim();
        rpcProperties = RpcProperties.fromEndpointsYamlAndPrivateToken(endpointsConf, privateToken);
      }
      catch (e) {
        Logger.root.shout('cant read endpoints config or private token file: $e');
        io.exit(1);
      }
    }
    Logger.root.info('using rpc configuration $rpcProperties');

    services = ServicesConnector(rpcProperties);

    _setupSignals();
    _createPidFile();
    _openDatabaseConnection();

    Logger.root.fine('service $serviceName ($instanceName) processed basic initialization');
  }

  ArgResults _parseArguments(List<String> commandLineArguments) {
    final mainParser = ArgParser();
    mainParser.addOption('config', abbr: 'C', help: 'config file name');
    mainParser.addOption('log', abbr: 'L', help: 'log file name');
    mainParser.addOption('pid', abbr: 'P', help: 'pid file name');
    mainParser.addOption('name', abbr: 'N', help: 'instance name');

    for (final entry in extraArgParsers.entries) {
      mainParser.addCommand(entry.key, entry.value);
    }

    return mainParser.parse(commandLineArguments);
  }

  Future<void> _openDatabaseConnection() async {
    dynamic dbConfig = configFile?['database'];
    String? databaseConfigFileName = configFileName;
    if (dbConfig == null) {
      // read dedicated database.yaml
      databaseConfigFileName = _findServiceConfigFile('database.yaml', instanceName);
      if (databaseConfigFileName == null) {
        Logger.root.shout('no database configuration file for this instance');
        io.exit(1);
      }
      dbConfig = parseYamlConfig(databaseConfigFileName);
    }
    try {
      _databaseProperties = DatabaseProperties.fromYamlConfig(dbConfig,
        parentConfigFileName: databaseConfigFileName!,
        instanceName: instanceName,
      );
    }
    catch (e) {
      Logger.root.shout('cant parse database config: $e');
      io.exit(1);
    }
    try {
      databaseConnection = PostgreSQLConnection(
        _databaseProperties.host,
        _databaseProperties.port,
        _databaseProperties.dbName,
        username: _databaseProperties.user,
        password: _databaseProperties.password,
      );
      await databaseConnection.open();
      Logger.root.fine('opened database connection');
    }
    catch (e) {
      Logger.root.shout('cant open database connection: $e');
      io.exit(1);
    }
  }

  void _initializeLogging(String logFileName) {
    Logger.root.level = Level.ALL;
    io.RandomAccessFile? logFileSink;
    if (logFileName.isNotEmpty && logFileName!='stdout') {
      final logFile = io.File(logFileName);
      final logDir = logFile.parent;
      if (!logDir.existsSync()) {
        try {
          logDir.createSync(recursive: true);
        }
        catch (e) {
          print('FATAL: Cant create directory ${logDir.path} for logs: $e');
          io.exit(1);
        }
      }
      try {
        logFileSink = logFile.openSync(mode: io.FileMode.writeOnlyAppend);
      }
      catch (e) {
        print('FATAL: Cant open log file $logFileName: $e');
        io.exit(1);
      }
      print('INFO: Will use log file $logFileName for further messages');
    }
    Logger.root.onRecord.listen((record) async {
      final messageLine = '${record.time}: ${record.level} - ${record.message}\n';
      final messageBytes = utf8.encode(messageLine);
      if (logFileSink != null) {
        logFileSink.writeFromSync(messageBytes);
        logFileSink.flushSync();
      }
      else {
        io.stdout.add(messageBytes);
      }
    });
  }

  Future<void> _terminate(String reason) async {
    Logger.root.info('shutting down due to $reason...');
    const stopTimeout = Duration(seconds: 2);
    bool timedOut = false;
    void terminateRest() {
      if (timedOut) {
        Logger.root.severe('service has not stopped within $stopTimeout, forcing exit');
      }
      databaseConnection.close();
      _removePidFile();
      Logger.root.info('Bye!');
      io.exit(0);
    }
    Timer(Duration(seconds: 2), () {
      timedOut = true;
      terminateRest();
    });
    stop().then((_) => terminateRest());
  }

  void _createPidFile() {
    if (_pidFile == null) {
      return;
    }
    final pidDirectory = _pidFile!.parent;
    if (!pidDirectory.existsSync()) {
      try {
        pidDirectory.createSync(recursive: true);
      }
      catch (e) {
        Logger.root.shout('cant create directory ${pidDirectory.path} for PID file: $e');
        io.exit(1);
      }
    }
    try {
      String message = '${io.pid}\n';
      _pidFile!.writeAsStringSync(message, flush: true);
    }
    catch (e) {
      Logger.root.shout('cant write PID file ${_pidFile!.path}: $e');
      io.exit(1);
    }
  }

  void _removePidFile() {
    if (_pidFile == null) {
      return;
    }
    try {
      _pidFile!.deleteSync();
    }
    catch (e) {
      Logger.root.severe('cant remove PID file ${_pidFile!.path}: $e');
    }
  }

  void _setupSignals() {
    io.ProcessSignal.sigterm.watch().listen((_) => _terminate('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => _terminate('SIGHUP'));
    io.ProcessSignal.sighup.watch().listen((_) => services.invalidateConnections('SIGHUP'));
  }

  @protected
  Future<void> serve(Service service, [List<Interceptor> extraInterceptors = const <Interceptor>[]]) async {
    final interceptors = [_checkAuthInterceptor] + extraInterceptors;
    final apiName = service.$name;
    final endpoint = rpcProperties.endpoints[apiName];
    if (endpoint == null) {
      throw ArgumentError('service $apiName has not registered endpoint in configuration', apiName);
    }
    final grpcServer = Server([service], interceptors);
    dynamic address;
    if (!endpoint.isUnix) {
      if (endpoint.host.isEmpty) {
        address = io.InternetAddress.anyIPv4;
      }
      else {
        address = endpoint.host;
      }
      await grpcServer.serve(address: address, port: endpoint.port, shared: true);
    }
    else {
      final unixSocketFile = io.File(endpoint.unixPath);
      if (unixSocketFile.existsSync()) {
        io.Process.runSync('rm', ['-f', unixSocketFile.absolute.path]);
      }
      final socketDir = unixSocketFile.parent;
      if (socketDir.existsSync()) {
        try {
          socketDir.createSync(recursive: true);
        }
        catch (e) {
          Logger.root.shout('cant create directory for sockets: $e');
          io.exit(1);
        }
      }
      address = io.InternetAddress(endpoint.unixPath, type: io.InternetAddressType.unix);
      Timer(Duration(seconds: 1), () {
        // set full permissions on unix socket for debug purposes
        // if service is running from supervisor in release mode, then
        // permissions will be fixed by supervisor
        io.Process.runSync('chmod', ['0666', unixSocketFile.absolute.path]);
      });
      await grpcServer.serve(address: address);
    }
  }

  void markMethodAllowNotLoggedUser(String methodName) {
    _notLoggedMethods.add(methodName);
  }

  void markMethodPrivate(String methodName) {
    _servicePrivateMethods.add(methodName);
  }

  FutureOr<GrpcError?> _checkAuthInterceptor(ServiceCall call, ServiceMethod method) async {
    final simpleName = method.name.split('.').last;
    if (_notLoggedMethods.contains(simpleName)) {
      return null;
    }
    String? auth = call.clientMetadata!.containsKey('token') ? call.clientMetadata!['token'] : null;
    if (auth != null && auth == rpcProperties.privateToken) {
      // god mode on
      return null;
    }
    if (_servicePrivateMethods.contains(simpleName)) {
      if (auth == null) {
        return GrpcError.unauthenticated('no token metadata to access private method ${method.name}');
      }
      if (auth != rpcProperties.privateToken) {
        return GrpcError.unauthenticated('cant access private method ${method.name}');
      }
      return null;
    }
    String? sessionId = call.clientMetadata!.containsKey('session') ? call.clientMetadata!['session'] : null;
    if (sessionId == null || sessionId.isEmpty) {
      return GrpcError.unauthenticated('no session metadata to access ${method.name}');
    }
    return null;
  }

  String? _findServiceConfigFile(String configName, String instanceName) {
    final root = _findYajudgeRoot();
    final confDir = io.Directory(path.join(path.absolute(root.path), 'conf'));
    final confDevelDir = io.Directory(path.join(path.absolute(root.path), 'conf-devel'));
    String confDirPath;
    if (confDir.existsSync()) {
      confDirPath = confDir.path;
    }
    else if (confDevelDir.existsSync()) {
      confDirPath = confDevelDir.path;
    }
    else {
      return null;
    }
    final confFileName = path.join(confDirPath, instanceName, configName);
    final confFile = io.File(confFileName);
    if (confFile.existsSync()) {
      return confFileName;
    }
    else {
      return null;
    }
  }

  String _guessOutFileName(String category, String instanceName) {
    final root = _findYajudgeRoot();
    final categoryRoot = path.join(path.absolute(root.path), category);
    return path.join(categoryRoot, instanceName, '$serviceName.$category');
  }

  io.Directory _findYajudgeRoot() {
    final scriptUri = io.Platform.script;
    final executableFile = io.File(scriptUri.path);
    assert (executableFile.existsSync());
    final binDir = executableFile.parent;
    final topDir = binDir.parent;
    final topDirName = path.basename(topDir.path);
    if (topDirName == 'yajudge_master_services') {
      // go one directory up due to running from development subdirectory
      return topDir.parent;
    }
    else {
      // yajudge binary bundle have only one 'bin' directory
      return topDir;
    }
  }
}
