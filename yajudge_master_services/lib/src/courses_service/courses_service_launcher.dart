import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'courses_service.dart';

class CourseServiceLauncher extends ServiceLauncherBase {

  late final CourseContentProviderClient contentProvider;
  late final UserManagementClient users;

  CourseServiceLauncher() : super('courses');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    users = createExternalApi('UserManagement', (c,i) => UserManagementClient(c, interceptors: i));
    contentProvider = createExternalApi('CourseContentProvider', (c,i) => CourseContentProviderClient(c, interceptors: i));
    final service = CourseManagementService(
      connection: databaseConnection,
      userManagement: users,
      contentProvider: contentProvider,
      secretKey: rpcProperties.privateToken,
    );
    super.service = service;
    super.markMethodAllowNotLoggedUser('GetUserEnrollments');
    super.markMethodAllowNotLoggedUser('GetGroupEnrollments');
    super.markMethodAllowNotLoggedUser('GetAllGroupsEnrollments');
  }

}