import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'progress_service.dart';

class ProgressServiceLauncher extends ServiceLauncherBase {

  ProgressServiceLauncher() : super('progress');

  late final SubmissionManagementClient submissionManager;
  late final CourseManagementClient courseManager;
  late final CourseContentProviderClient contentProvider;
  late final DeadlinesManagementClient deadlinesManager;

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    submissionManager = createExternalApi('SubmissionManagement', (c,i) => SubmissionManagementClient(c, interceptors: i));
    courseManager = createExternalApi('CourseManagement', (c,i) => CourseManagementClient(c, interceptors: i));
    contentProvider = createExternalApi('CourseContentProvider', (c,i) => CourseContentProviderClient(c, interceptors: i));
    deadlinesManager = createExternalApi('DeadlinesManagement', (c,i) => DeadlinesManagementClient(c, interceptors: i));
    final service = ProgressCalculatorService(
      connection: databaseConnection,
      courseManagement: courseManager,
      contentProvider: contentProvider,
      submissionManagement: submissionManager,
      deadlinesManager: deadlinesManager,
    );
    super.service = service;
    super.markMethodPrivate('NotifyProblemStatusChanged');
  }

}