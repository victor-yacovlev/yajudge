import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'deadlines_service.dart';

class DeadlinesServiceLauncher extends ServiceLauncherBase {

  late final CourseContentProviderClient contentProvider;
  late final UserManagementClient userManager;
  late final CourseManagementClient courseManager;

  DeadlinesServiceLauncher() : super('deadlines');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    userManager = createExternalApi('UserManagement', (c,i) => UserManagementClient(c, interceptors: i));
    contentProvider = createExternalApi('CourseContentProvider', (c,i) => CourseContentProviderClient(c, interceptors: i));
    courseManager = createExternalApi('CourseManagement', (c,i) => CourseManagementClient(c, interceptors: i));
    final service = DeadlinesManagementService(
      connection: databaseConnection,
      contentProvider: contentProvider,
      userManager: userManager,
      courseManager: courseManager,
      secretKey: rpcProperties.privateToken,
    );
    super.service = service;
    super.markMethodAllowNotLoggedUser('GetSubmissionDeadlines');
    super.markMethodAllowNotLoggedUser('GetLessonSchedules');
    super.markMethodPrivate('InsertNewSubmission');
  }

}