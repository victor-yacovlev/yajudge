import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'submissions_service.dart';

class SubmissionsServiceLauncher extends ServiceLauncherBase {
  SubmissionsServiceLauncher() : super('submissions');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    final service = SubmissionManagementService(
      services: services,
      connection: databaseConnection,
      secretKey: rpcProperties.privateToken,
    );
    super.service = service;
    super.markMethodPrivate('UpdateGraderOutput');
    super.markMethodPrivate('GetSubmissionsToGrade');
    super.markMethodPrivate('TakeSubmissionToGrade');
    super.markMethodPrivate('UpdateGraderOutput');
    super.markMethodPrivate('ReceiveSubmissionsToProcess');
    super.markMethodPrivate('SetExternalServiceStatus');
  }
}
