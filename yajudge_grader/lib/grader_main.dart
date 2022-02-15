import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'src/chrooted_runner.dart';
import 'src/grader_service.dart';
import 'src/grader_extra_configs.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

Future<GraderService> initializeGrader(ArgResults parsedArguments, bool useLogFile, bool usePidFile) async {
  String? configFileName = parsedArguments['config'];
  if (configFileName == null) {
    configFileName = findConfigFile('grader-server');
  }
  if (configFileName == null) {
    print('No config file specified\n');
    io.exit(1);
  }

  GradingLimits? overrideLimits;
  if (parsedArguments['limits'] != null) {
    final limitsFileName = expandPathEnvVariables(parsedArguments['limits']!);
    final limitsConf = loadYaml(io.File(limitsFileName).readAsStringSync());
    overrideLimits = limitsFromYaml(limitsConf);
  }

  final config = parseYamlConfig(configFileName);
  final rpcProperties = RpcProperties.fromYamlConfig(config['rpc']);
  final locationProperties = GraderLocationProperties.fromYamlConfig(config['locations']);
  final identityProperties = GraderIdentityProperties.fromYamlConfig(config['identity']);

  if (useLogFile) {
    final String? logFilePath = expandPathEnvVariables(config['log_file']);
    if (logFilePath != null) {
      final logFile = io.File(logFilePath);
      initializeLogger(logFile.openWrite(mode: io.FileMode.append));
    }
    else {
      initializeLogger(io.stdout);
    }
  }

  if (usePidFile) {
    String? pidFilePath = expandPathEnvVariables(config['pid_file']);
    if (pidFilePath == null) {
      pidFilePath = 'grader.pid'; // in current directory
    }
    io.File(pidFilePath).writeAsStringSync('${io.pid}');
  }

  GradingLimits defaultLimits;
  if (config['default_limits'] is YamlMap) {
    YamlMap limitsConf = config['default_limits'];
    defaultLimits = limitsFromYaml(limitsConf);
  }
  else {
    defaultLimits = GradingLimits();
  }

  SecurityContext defaultSecurityContext;
  if (config['default_security_context'] is YamlMap) {
    YamlMap securityContextConf = config['default_security_context'];
    defaultSecurityContext = securityContextFromYaml(securityContextConf);
  }
  else {
    defaultSecurityContext = SecurityContext();
  }

  CompilersConfig compilersConfig;
  if (config['compilers'] is YamlMap) {
    YamlMap compilersConf = config['compilers'];
    compilersConfig = CompilersConfig.fromYaml(compilersConf);
  } else {
    compilersConfig = CompilersConfig.createDefault();
  }

  final graderService = GraderService(
    rpcProperties: rpcProperties,
    locationProperties: locationProperties,
    identityProperties: identityProperties,
    defaultLimits: defaultLimits,
    defaultSecurityContext: defaultSecurityContext,
    compilersConfig: compilersConfig,
    overrideLimits: overrideLimits,
  );

  ChrootedRunner.initialCgroupSetup();

  return graderService;
}

void initializeLogger(io.IOSink? target) {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (target != null) {
      target.writeln(
          '${record.time}: ${record.level.name} - ${record.message}');
    }
  });
}


Future<void> serverMain(List<String> arguments) async {
  final parser = ArgParser();
  parser.addOption('config', abbr: 'C', help: 'config file name');
  parser.addOption('limits', abbr: 'l', help: 'custom problem limits');
  final parsedArguments = parser.parse(arguments);

  GraderService service = await initializeGrader(parsedArguments, true, true);

  String name = service.identityProperties.name;
  Logger.root.info('started grader server "$name" at PID = ${io.pid}');
  if (!io.Platform.isLinux) {
    Logger.root.warning('running grader on systems other than Linux is completely unsecure!');
  }

  service.serveSupervised();
}

Future<void> toolMain(List<String> arguments) async {
  final parser = ArgParser();
  parser.addOption('config', abbr: 'C', help: 'config file name');
  parser.addOption('limits', abbr: 'l', help: 'custom problem limits');
  parser.addOption('course', abbr: 'c', help: 'course data id');
  parser.addOption('problem', abbr: 'p', help: 'problem id');
  parser.addFlag('verbose', abbr: 'v', help: 'verbose log to stdout');
  final parsedArguments = parser.parse(arguments);

  if (parsedArguments['course'] == null) {
    print('No course data id specified\n');
    io.exit(1);
  }

  if (parsedArguments['problem'] == null) {
    print('No problem id specified\n');
    io.exit(1);
  }

  if (parsedArguments.rest.isEmpty) {
    print('Requires at least one solution file name\n');
    io.exit(1);
  }

  String courseDataId = parsedArguments['course'];
  String problemId = parsedArguments['problem'];

  List<File> solutionFiles = [];
  for (final fileName in parsedArguments.rest) {
    final file = io.File(fileName);
    if (!file.existsSync()) {
      print('File $fileName not found\n');
      io.exit(1);
    }
    final content = file.readAsBytesSync();
    solutionFiles.add(File(name: path.basename(fileName), data: content));
  }

  final fakeSubmission = Submission(
    course: Course(dataId: courseDataId),
    problemId: problemId,
    solutionFiles: FileSet(files: solutionFiles),
  );

  final service = await initializeGrader(parsedArguments, false, false);

  final processed = await service.processSubmission(fakeSubmission);
  print(processed.status.name + '\n');
  final findFirstTest = () {
    for (final test in processed.testResults) {
      if (test.status == processed.status) {
        return test;
      }
    }
    return TestResult();
  };

  if (processed.status == SolutionStatus.STYLE_CHECK_ERROR) {
    print(processed.styleErrorLog);
  }
  else if (processed.status == SolutionStatus.COMPILATION_ERROR) {
    print(processed.buildErrorLog);
  }
  else if (processed.status == SolutionStatus.RUNTIME_ERROR) {
    final broken = findFirstTest();
    print(broken.stdout + '\n' + broken.stderr);
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

