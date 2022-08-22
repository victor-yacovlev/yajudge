import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'src/chrooted_runner.dart';
import 'src/grader_service.dart';
import 'src/grader_extra_configs.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

Future<GraderService> initializeGrader(ArgResults parsedArguments, bool useLogFile) async {
  String configFileName = getConfigFileName(parsedArguments);
  print('Using config file $configFileName');

  if (!io.File(configFileName).existsSync()) {
    print('Config file not exists');
    io.exit(1);
  }

  final config = parseYamlConfig(configFileName);

  var identityProperties = GraderIdentityProperties.fromYamlConfig(config['identity']);
  String graderInstanceName = 'default';
  if (parsedArguments['name'] != null) {
    graderInstanceName = parsedArguments['name'];
  }
  else if (identityProperties.name.isNotEmpty) {
    graderInstanceName = identityProperties.name;
  }
  String hostName = io.Platform.localHostname;
  String graderFullName = '$graderInstanceName@$hostName';
  identityProperties = GraderIdentityProperties(graderFullName);

  print('Using $graderFullName as full grader name');

  final rpcProperties = RpcProperties.fromYamlConfig(config['rpc'],
    parentConfigFileName: configFileName,
    instanceName: graderInstanceName,
  );


  var locationProperties = GraderLocationProperties.fromYamlConfig(config['locations'], graderInstanceName);
  ServiceProperties serviceProperties;
  if (config['service'] is YamlMap) {
    serviceProperties =
        ServiceProperties.fromYamlConfig(config['service'], graderInstanceName);
  } else {
    serviceProperties = ServiceProperties.fromYamlConfig(YamlMap(), graderInstanceName);
  }

  print('Configs parsed successfully');

  if (useLogFile) {
    print('Configuring logger');
    final logFilePath = getLogFileName(parsedArguments, graderInstanceName);
    GraderService.configureLogger(logFilePath, '');
    if (logFilePath.isNotEmpty && logFilePath!='stdout') {
      // duplicate initialization messages to log file
      Logger.root.info('Starting grader daemon at PID = ${io.pid}');
      Logger.root.info('Using config file $configFileName');
    }
  }

  final pidFilePath = getPidFileName(parsedArguments, graderInstanceName);
  if (pidFilePath != null) {
    Logger.root.info('Using PID file $pidFilePath');
    try {
      io.File(pidFilePath).writeAsStringSync('${io.pid}');
      print('Using PID file $pidFilePath: written value ${io.pid}');
    }
    catch (e) {
      print('Cant create PID file $pidFilePath: $e');
    }
  }

  GradingLimits defaultLimits;
  if (config['default_limits'] is YamlMap) {
    YamlMap limitsConf = config['default_limits'];
    defaultLimits = GradingLimitsExtension.fromYaml(limitsConf);
  }
  else {
    defaultLimits = GradingLimits();
  }

  SecurityContext defaultSecurityContext = SecurityContext();
  final defaultSecurityContextNode = config['default_security_context'];
  if (defaultSecurityContextNode is YamlMap) {
    defaultSecurityContext = securityContextFromYaml(defaultSecurityContextNode);
  }

  DefaultBuildProperties defaultBuildProperties = DefaultBuildProperties({});
  final defaultBuildPropertiesNode = config['default_build_properties'];
  if (defaultBuildPropertiesNode is YamlMap) {
    defaultBuildProperties = DefaultBuildProperties.fromYaml(defaultBuildPropertiesNode);
  }

  DefaultRuntimeProperties defaultRuntimeProperties = DefaultRuntimeProperties({});
  final defaultRuntimePropertiesNode = config['default_runtime_properties'];
  if (defaultRuntimeProperties is YamlMap) {
    defaultRuntimeProperties = DefaultRuntimeProperties.fromYaml(defaultRuntimePropertiesNode);
  }

  JobsConfig jobsConfig;
  if (config['jobs'] is YamlMap) {
    YamlMap jobsConf = config['jobs'];
    jobsConfig = JobsConfig.fromYaml(jobsConf);
  } else {
    jobsConfig = JobsConfig.createDefault();
  }

  if (rpcProperties.privateToken.isEmpty) {
    Logger.root.shout('private access token not set in configuration. Exiting');
    io.exit(1);
  }

  if (io.Platform.isLinux) {
    Logger.root.info('Checking for linux cgroup capabilities');
    String cgroupInitializationError = ChrootedRunner.initializeLinuxCgroup(graderInstanceName);
    Logger.root.info('Will use cgroup root: ${ChrootedRunner.cgroupRoot}');
    print('Will use cgroup root: ${ChrootedRunner.cgroupRoot}');
    if (cgroupInitializationError.isEmpty) {
      Logger.root.info('Linux cgroup requirements met');
    }
    else {
      // Allow log flushed
      Logger.root.shout('Linux cgroup requirements not met: $cgroupInitializationError. Exiting');
      print('Linux cgroup requirements not met: $cgroupInitializationError. Exiting');
      io.sleep(Duration(seconds: 2));
      io.exit(1);
    }
  }

  final graderService = GraderService(
    rpcProperties: rpcProperties,
    locationProperties: locationProperties,
    identityProperties: identityProperties,
    jobsConfig: jobsConfig,
    defaultLimits: defaultLimits,
    defaultSecurityContext: defaultSecurityContext,
    defaultBuildProperties: defaultBuildProperties,
    defaultRuntimeProperties: defaultRuntimeProperties,
    overrideLimits: null,
    serviceProperties: serviceProperties,
  );

  return graderService;
}

io.Directory getYajudgeRootDir() {
  final graderExecutablePath = realGraderExecutablePath();
  final graderExecutableFile = io.File(graderExecutablePath).absolute;
  final graderProjectDir = graderExecutableFile.parent.parent;
  final graderProjectDirName = path.basename(graderProjectDir.path);
  io.Directory yajudgeRootDir;
  if (graderProjectDirName == 'yajudge_grader') {
    yajudgeRootDir = graderProjectDir.parent;
  } else {
    yajudgeRootDir = graderProjectDir;
  }
  return yajudgeRootDir;
}

String getConfigFileName(ArgResults parsedArguments) {
  String? configFileName = parsedArguments['config'];
  String? instanceName = parsedArguments['name'] ?? 'default';
  if (configFileName == null && instanceName != null) {
    final yajudgeRootDir = getYajudgeRootDir();
    final confDir = io.Directory(path.join(yajudgeRootDir.path, "conf"));
    final confDevelDir = io.Directory(path.join(yajudgeRootDir.path, "conf-devel"));
    io.Directory? realConfDir;
    if (confDevelDir.existsSync()) {
      realConfDir = confDevelDir;
    }
    else if (confDir.existsSync()) {
      realConfDir = confDir;
    }
    else {
      print('No config file specified and no conf directory under $yajudgeRootDir');
      io.exit(1);
    }
    configFileName = path.join(realConfDir.path, instanceName, 'grader.yaml');
  }
  if (configFileName == null || configFileName.isEmpty) {
    print('No config file specified');
    io.exit(1);
  }
  return configFileName;
}

String? getPidFileName(ArgResults parsedArguments, String graderName) {
  String? pidFileName = parsedArguments['pid'];
  if (pidFileName == null) {
    String configFileName = getConfigFileName(parsedArguments);
    final conf = loadYaml(io.File(configFileName).readAsStringSync());
    if (conf['service'] is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], graderName);
      pidFileName = serviceProperties.pidFilePath;
    }
  }
  return pidFileName;
}

String getLogFileName(ArgResults parsedArguments, String graderName) {
  String? logFileName = parsedArguments['log'];
  if (logFileName == null) {
    String configFileName = getConfigFileName(parsedArguments);
    final conf = loadYaml(io.File(configFileName).readAsStringSync());
    if (conf['service'] is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], graderName);
      logFileName = serviceProperties.logFilePath;
      if (logFileName.endsWith('/stdout')) {
        logFileName = 'stdout';
      }
    }
  }
  logFileName ??= 'stdout';
  return logFileName;
}


void initializeLogger(io.IOSink? target) {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) async {
    String messageLine = '${record.time}: ${record.level.name} - ${record.message}\n';
    List<int> bytes = utf8.encode(messageLine);
    if (target != null) {
      try {
        target.add(bytes);
      }
      catch (error) {
        print('LOG: $messageLine');
        print('Got logger error: $error');
      }
    }
  });
  if (target != null) {
    Timer.periodic(Duration(milliseconds: 250), (timer) {
      try {
        target.flush();
      } catch (_) {}
    });
  }
}


String realGraderExecutablePath() {
  if (!io.Platform.isLinux) {
    return io.Platform.script.path;
  }
  else {
    String procPidExePath = '/proc/${io.pid}/exe';
    final exeLink = io.Link(procPidExePath);
    String targetExecutablePath = exeLink.targetSync();
    if (targetExecutablePath.endsWith('/dart')) {
      final binaryCmdLine = io.File('/proc/${io.pid}/cmdline')
          .readAsBytesSync();
      int start = 0;
      int end = -1;
      String dartFileName = '';
      Uint8List binaryArgument = Uint8List(0);
      String argument = '';
      while (dartFileName.isEmpty && start < binaryCmdLine.length) {
        end = binaryCmdLine.indexOf(0, start);
        if (-1 == end) {
          end = binaryCmdLine.length;
        }
        binaryArgument = binaryCmdLine.sublist(start, end);
        argument = utf8.decode(binaryArgument);
        if (!argument.startsWith('-') && argument.endsWith('.dart')) {
          dartFileName = argument;
        }
        start = end + 1;
      }
      return '$targetExecutablePath $dartFileName';
    }
    else {
      return targetExecutablePath;
    }
  }
}



Future<void> serverMain(ArgResults parsedArguments) async {
  GraderService service = await initializeGrader(parsedArguments, true);
  Logger.root.info('Grader successfully initialized');
  String name = service.identityProperties.name;
  Logger.root.info('started grader server "$name" at PID = ${io.pid}');
  if (!io.Platform.isLinux) {
    Logger.root.warning('running grader on systems other than Linux is completely unsecure!');
  }
  service.serveSupervised();
}


ArgResults parseArguments(List<String> arguments) {
  final mainParser = ArgParser();
  mainParser.addOption('config', abbr: 'C', help: 'config file name');
  mainParser.addOption('log', abbr: 'L', help: 'log file name');
  mainParser.addOption('pid', abbr: 'P', help: 'pid file name');
  mainParser.addOption('name', abbr: 'N', help: 'grader name in case of multiple instances running same host');

  final runParser = ArgParser();
  runParser.addOption('limits', abbr: 'l', help: 'custom problem limits');
  runParser.addOption('course', abbr: 'c', help: 'course data id');
  runParser.addOption('problem', abbr: 'p', help: 'problem id');
  runParser.addFlag('verbose', abbr: 'v', help: 'verbose log to stdout');

  final daemonParser = ArgParser();
  daemonParser.addFlag('inbox', abbr: 'i', help: 'process only local inbox submissions');

  mainParser.addCommand('run', runParser);
  mainParser.addCommand('daemon', daemonParser);
  mainParser.addCommand('start');
  mainParser.addCommand('stop');

  final parsedArguments = mainParser.parse(arguments);
  return parsedArguments;
}

Future<void> main(List<String> arguments) async {
  final parsedArguments = parseArguments(arguments);
  print('Starting grader daemon at PID = ${io.pid}');
  return serverMain(parsedArguments);
}

