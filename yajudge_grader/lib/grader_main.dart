import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'src/chrooted_runner.dart';
import 'src/grader_service.dart';
import 'src/grader_extra_configs.dart';
import 'package:yaml/yaml.dart';

Future<void> main([List<String>? arguments]) async {
  ArgParser parser = ArgParser();
  parser.addOption('config');
  String? configFileName;
  if (arguments != null) {
    ArgResults options = parser.parse(arguments);
    configFileName = options['config'];
  }
  if (configFileName==null || configFileName.isEmpty) {
    configFileName = findConfigFile('grader-server');
  }
  if (configFileName==null) {
    print('No config file specified\n');
    exit(1);
  }
  final config = parseYamlConfig(configFileName);
  final rpcProperties = RpcProperties.fromYamlConfig(config['rpc']);
  final locationProperties = GraderLocationProperties.fromYamlConfig(config['locations']);
  final identityProperties = GraderIdentityProperties.fromYamlConfig(config['identity']);
  GradingLimits defaultLimits;
  if (config['default_limits'] is YamlMap) {
    YamlMap limitsConf = config['default_limits'];
    defaultLimits = parseDefaultLimits(limitsConf);
  } else {
    defaultLimits = GradingLimits();
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
    compilersConfig: compilersConfig,
  );
  ChrootedRunner.initialCgroupSetup();
  String name = identityProperties.name;
  graderService.serveSupervised();
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.time}: ${record.level.name} - ${record.message}');
  });
  Logger.root.info('started grader server "$name" at PID = $pid');
  if (!Platform.isLinux) {
    Logger.root.warning('running grader on systems other than Linux is completely unsecure!');
  }
}

