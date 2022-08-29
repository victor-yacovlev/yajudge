import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'deadlines_service.dart';

class DeadlinesServiceLauncher extends ServiceLauncherBase {

  DeadlinesServiceLauncher() : super('deadlines');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    final service = DeadlinesManagementService(
      connection: databaseConnection,
      secretKey: rpcProperties.privateToken,
      services: services,
    );
    super.service = service;
    super.markMethodAllowNotLoggedUser('GetSubmissionDeadlines');
    super.markMethodAllowNotLoggedUser('GetLessonSchedules');
    super.markMethodPrivate('InsertNewSubmission');
  }

}