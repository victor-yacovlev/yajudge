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
import 'package:crypto/crypto.dart' as crypto;

Future<GraderService> initializeGrader(ArgResults parsedArguments, bool useLogFile, bool usePidFile) async {
  String configFileName = getConfigFileName(parsedArguments);
  print('Using config file $configFileName');

  GradingLimits? overrideLimits;
  if (parsedArguments.command!.name=='run' && parsedArguments.command!['limits'] != null) {
    final limitsFileName = expandPathEnvVariables(parsedArguments.command!['limits']!, '');
    final limitsConf = loadYaml(io.File(limitsFileName).readAsStringSync());
    overrideLimits = GradingLimitsExtension.fromYaml(limitsConf);
  }

  if (!io.File(configFileName).existsSync()) {
    print('Config file not exists');
    io.exit(1);
  }
  final config = parseYamlConfig(configFileName);
  final rpcProperties = RpcProperties.fromYamlConfig(config['rpc']);

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

  var locationProperties = GraderLocationProperties.fromYamlConfig(config['locations'], graderInstanceName);
  final serviceProperties = ServiceProperties.fromYamlConfig(config['service'], graderInstanceName);

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

  String pidFilePath = '';
  if (usePidFile) {
    pidFilePath = getPidFileName(parsedArguments, graderInstanceName);
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

  bool processInboxOnly = false;
  if (parsedArguments.command != null) {
    ArgResults daemonArgs = parsedArguments.command!;
    processInboxOnly = daemonArgs['inbox'];
    if (processInboxOnly) {
      Logger.root.info('Will process only local inbox submissions');
    }
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
    overrideLimits: overrideLimits,
    serviceProperties: serviceProperties,
    usePidFile: usePidFile,
    processLocalInboxOnly: processInboxOnly,
  );

  return graderService;
}

String getConfigFileName(ArgResults parsedArguments) {
  String? configFileName = parsedArguments['config'];
  configFileName ??= findConfigFile('grader');
  if (configFileName.isEmpty) {
    print('No config file specified');
    io.exit(1);
  }
  return configFileName;
}

String getPidFileName(ArgResults parsedArguments, String graderName) {
  String? pidFileName = parsedArguments['pid'];
  if (pidFileName == null) {
    String configFileName = getConfigFileName(parsedArguments);
    final conf = loadYaml(io.File(configFileName).readAsStringSync());
    if (conf['service'] is YamlMap) {
      final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], graderName);
      pidFileName = serviceProperties.pidFilePath;
    }
  }
  if (pidFileName == null) {
    print("No pid file specified");
    io.exit(1);
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

Future<void> startServerOnLinux(ArgResults parsedArguments, List<String> sourceArguments) async {
  final executableArgs = realGraderExecutablePath().split(' ');
  int startIndex = sourceArguments.indexOf('start');
  List<String> newArguments = List.from(sourceArguments);
  newArguments[startIndex] = 'daemon';
  String configFileName = getConfigFileName(parsedArguments);
  final conf = loadYaml(io.File(configFileName).readAsStringSync());
  String sliceName = 'yajudge';
  String graderName = 'default';
  if (parsedArguments['name'] != null) {
    graderName = parsedArguments['name'];
  }
  if (conf['service'] is YamlMap) {
    final serviceProperties = ServiceProperties.fromYamlConfig(conf, graderName);
    sliceName = serviceProperties.systemdSlice;
  }
  final systemdArguments = ['--user', '--slice=$sliceName'];
  final futureProcess = io.Process.start(
    'systemd-run',
    systemdArguments + executableArgs + newArguments,
    mode: io.ProcessStartMode.detached,
  );
  futureProcess.then((final process) {
    print('Started yajudge grader daemon via systemd-run in slice $sliceName');
    io.exit(0);
  });
}

Future<void> startServerOnNotLinux(ArgResults parsedArguments, List<String> sourceArguments) async {
  String executablePath = realGraderExecutablePath();
  int startIndex = sourceArguments.indexOf('start');
  List<String> newArguments = List.from(sourceArguments);
  newArguments[startIndex] = 'daemon';
  String command;
  if (executablePath.endsWith('.dart')) {
    final parts = executablePath.split(' ');
    command = parts[0];
    newArguments = parts.sublist(1) + newArguments;
  }
  else {
    command = executablePath;
  }
  final futureProcess = io.Process.start(
    command,
    newArguments,
    mode: io.ProcessStartMode.detached,
  );
  futureProcess.then((final process) {
    print('Started yajudge grader daemon');
    io.exit(0);
  });
}

Future<void> stopServer(ArgResults parsedArguments) async {
  String configFileName = getConfigFileName(parsedArguments);
  final conf = loadYaml(io.File(configFileName).readAsStringSync());
  int pid = 0;
  String pidFilePath = '';
  String graderName = 'default';
  if (parsedArguments['name'] != null) {
    graderName = parsedArguments['name'];
  }
  if (conf['service'] is YamlMap) {
    final serviceProperties = ServiceProperties.fromYamlConfig(conf['service'], graderName);
    pidFilePath = serviceProperties.pidFilePath;
  }
  if (pidFilePath.isEmpty || pidFilePath=='disabled') {
    print('No pid file name specified in configuration. Cant stop');
    io.exit(1);
  }
  final pidFile = io.File(pidFilePath);
  if (!pidFile.existsSync()) {
    print('PID file not exists. Might be not running');
    io.exit(0);
  }
  String pidValue = pidFile.readAsStringSync().trim();
  if (pidValue.isEmpty) {
    print('PID file is empty. Might be not running');
    io.exit(0);
  }
  pid = int.parse(pidValue);
  int attemptsLeft = 10;
  final retryTimeout = Duration(seconds: 1);
  final waitTimeout = Duration(milliseconds: 100);
  bool processRunning = true;
  final statusFile = io.File('/proc/$pid/status');
  io.stdout.write('Stopping grader process');
  while (attemptsLeft > 0) {
    io.stdout.write('.');
    io.Process.killPid(pid, io.ProcessSignal.sigterm);
    io.sleep(waitTimeout);
    processRunning = statusFile.existsSync();
    if (!processRunning) {
      print(' Process ended with SIGTERM signal');
      break;
    }
    io.sleep(retryTimeout);
    attemptsLeft--;
  }
  if (processRunning) {
    io.Process.killPid(pid, io.ProcessSignal.sigkill);
    print(' Process ended with SIGKILL signal');
  }
  if (pidFile.existsSync()) {
    pidFile.deleteSync();
  }
  io.exit(0);
}

String realGraderExecutablePath() {
  String procPidExePath = '/proc/${io.pid}/exe';
  final exeLink = io.Link(procPidExePath);
  String targetExecutablePath = exeLink.targetSync();
  if (targetExecutablePath.endsWith('/dart')) {
    final binaryCmdLine = io.File('/proc/${io.pid}/cmdline').readAsBytesSync();
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
      start = end+1;
    }
    return '$targetExecutablePath $dartFileName';
  }
  else {
    return targetExecutablePath;
  }
}



Future<void> serverMain(ArgResults parsedArguments) async {
  GraderService service = await initializeGrader(parsedArguments, true, true);
  Logger.root.info('Grader successfully initialized');
  String name = service.identityProperties.name;
  Logger.root.info('started grader server "$name" at PID = ${io.pid}');
  if (!io.Platform.isLinux) {
    Logger.root.warning('running grader on systems other than Linux is completely unsecure!');
  }
  service.serveSupervised();
}

Future<void> toolMain(ArgResults mainArguments) async {
  final subcommandArguments = mainArguments.command!;
  
  if (subcommandArguments['course'] == null) {
    print('No course data id specified\n');
    io.exit(1);
  }

  if (subcommandArguments['problem'] == null) {
    print('No problem id specified\n');
    io.exit(1);
  }

  if (subcommandArguments.rest.isEmpty) {
    print('Requires at least one solution file name\n');
    io.exit(1);
  }

  String courseDataId = subcommandArguments['course'];
  String problemId = subcommandArguments['problem'];

  List<File> solutionFiles = [];
  for (final fileName in subcommandArguments.rest) {
    final file = io.File(fileName);
    if (!file.existsSync()) {
      print('File $fileName not found\n');
      io.exit(1);
    }
    final content = file.readAsBytesSync();
    solutionFiles.add(File(name: path.basename(fileName), data: content));
  }

  final submission = Submission(
    course: Course(dataId: courseDataId),
    problemId: problemId,
    solutionFiles: FileSet(files: solutionFiles),
  );

  GradingLimits limits = GradingLimits();

  if (subcommandArguments['limits'] != null) {
    String limitsFileName = subcommandArguments['limits'];
    final conf = loadYaml(io.File(limitsFileName).readAsStringSync());
    if (conf is YamlMap) {
      limits = GradingLimitsExtension.fromYaml(conf);
    }
  }

  String graderName = 'default';
  if (mainArguments['name'] != null) {
    graderName = mainArguments['name'];
  }

  String configFileName = getConfigFileName(mainArguments);
  String pidFileName = getPidFileName(mainArguments, graderName);
  int pid = 0;
  bool serviceRunning = false;
  final pidFile = io.File(pidFileName);
  if (pidFile.existsSync()) {
    pid = int.parse(pidFile.readAsStringSync().trim());
  }
  if (pid != 0) {
    String statusPath = '/proc/$pid/status';
    serviceRunning = io.File(statusPath).existsSync();
  }
  if (!serviceRunning) {
    print('No grader service running');
    io.exit(1);
  }
  final conf = loadYaml(io.File(configFileName).readAsStringSync());
  final locationProperties = GraderLocationProperties.fromYamlConfig(conf['locations'], graderName);
  String workDirPath = locationProperties.workDir;
  final inboxDir = io.Directory('$workDirPath/inbox');
  final doneDir = io.Directory('$workDirPath/done');
  if (!inboxDir.existsSync()) {
    inboxDir.createSync(recursive: true);
  }

  final localGraderSubmission = LocalGraderSubmission(
    submission: submission,
    gradingLimits: limits,
  );

  Uint8List requestData = localGraderSubmission.writeToBuffer();
  final hash = crypto.sha256.convert(requestData).toString();
  final inboxFile = io.File('${inboxDir.path}/$hash');
  inboxFile.writeAsBytesSync(requestData);
  print('Queued local submission $hash to grader');

  final doneFile = io.File('${doneDir.path}/$hash');
  io.stdout.write('Waiting for grader done ');
  while (!doneFile.existsSync()) {
    io.sleep(Duration(seconds: 1));
    io.stdout.write('.');
  }
  print(' got answer from grader');

  final processedData = doneFile.readAsBytesSync();
  doneFile.deleteSync();
  final processed = Submission.fromBuffer(processedData);

  print('${processed.status.name}\n');
  TestResult findFirstTest() {
    for (final test in processed.testResults) {
      if (test.status == processed.status) {
        return test;
      }
    }
    return TestResult();
  }

  if (processed.status == SolutionStatus.STYLE_CHECK_ERROR) {
    print(processed.styleErrorLog);
  }
  else if (processed.status == SolutionStatus.COMPILATION_ERROR) {
    print(processed.buildErrorLog);
  }
  else if (processed.status == SolutionStatus.RUNTIME_ERROR) {
    final broken = findFirstTest();
    print('${broken.stdout}\n${broken.stderr}');
  }
  else if (processed.status == SolutionStatus.VALGRIND_ERRORS) {
    final broken = findFirstTest();
    print(broken.valgrindOutput);
  }
  else if (processed.status == SolutionStatus.WRONG_ANSWER) {
    final broken = findFirstTest();
    print(broken.checkerOutput);
  }
  io.exit(0);
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
  if (parsedArguments.command == null) {
    print('Requires one of subcommands: start, stop, daemon or run\n');
    print('Command line arguments passed: $arguments');
    io.exit(127);
  }
  if (parsedArguments.command!.name! == 'run') {
    return toolMain(parsedArguments);
  }
  else if (parsedArguments.command!.name! == 'daemon') {
    print('Starting grader daemon at PID = ${io.pid}');
    return serverMain(parsedArguments);
  }
  else if (parsedArguments.command!.name! == 'start') {
    if (io.Platform.isLinux) {
      startServerOnLinux(parsedArguments, arguments);
    }
    else {
      startServerOnNotLinux(parsedArguments, arguments);
    }
  }
  else if (parsedArguments.command!.name! == 'stop') {
    stopServer(parsedArguments);
  }
}

