import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'progress_service.dart';

class ProgressServiceLauncher extends ServiceLauncherBase {

  ProgressServiceLauncher() : super('progress');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    final service = ProgressCalculatorService(
      connection: databaseConnection,
      services: services,
    );
    super.service = service;
    super.markMethodPrivate('NotifyProblemStatusChanged');
  }

}