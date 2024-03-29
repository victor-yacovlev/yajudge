import 'dart:io';

import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml/yaml.dart';

import '../service_launcher.dart';
import 'content_service.dart';

class ContentServiceLauncher extends ServiceLauncherBase {

  ContentServiceLauncher() : super('content');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    MasterLocationProperties locationProperties;
    try {
      YamlMap locationConf = configFile!['locations']!;
      locationProperties = MasterLocationProperties.fromYamlConfig(locationConf);
    }
    catch (e) {
      Logger.root.shout('error reading location properties: $e');
      exit(1);
    }
    service = CoursesContentProviderService(locationProperties);
  }

}