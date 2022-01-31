import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yajudge_grader/src/chrooted_runner.dart';
import 'src/grader_service.dart';

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
  final graderService = GraderService(
      rpcProperties: rpcProperties,
      locationProperties: locationProperties,
      identityProperties: identityProperties,
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