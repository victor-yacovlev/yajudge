import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'submissions_service.dart';

class SubmissionsServiceLauncher extends ServiceLauncherBase {

  SubmissionsServiceLauncher() : super('submissions');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    final service = SubmissionManagementService(
      courseManager: createExternalApi('CourseManagement', (c,i) => CourseManagementClient(c, interceptors: i)),
      courseContentProvider: createExternalApi('CourseContentProvider', (c,i) => CourseContentProviderClient(c, interceptors: i)),
      userManager: createExternalApi('UserManagement', (c,i) => UserManagementClient(c, interceptors: i)),
      deadlinesManager: createExternalApi('DeadlinesManagement', (c,i) => DeadlinesManagementClient(c, interceptors: i)),
      progressNotifier: createExternalApi('ProgressCalculator', (c,i) => ProgressCalculatorClient(c, interceptors: i)),
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