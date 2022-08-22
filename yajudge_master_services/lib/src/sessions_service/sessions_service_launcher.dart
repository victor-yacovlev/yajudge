import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'sessions_service.dart';

class SessionsServiceLauncher extends ServiceLauncherBase {

  late final UserManagementClient userManagementClient;
  late final CourseManagementClient courseManagementClient;

  SessionsServiceLauncher() : super('sessions');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    super.initialize(commandLineArguments);
    userManagementClient = createExternalApi('UserManagement', (c,i) => UserManagementClient(c, interceptors: i));
    courseManagementClient = createExternalApi('CourseManagement', (c,i) => CourseManagementClient(c, interceptors: i));
    final service = SessionManagementService(
      dbConnection: databaseConnection,
      coursesManager: courseManagementClient,
      usersManager: userManagementClient,
      secretKey: rpcProperties.privateToken,
    );
    super.markMethodAllowNotLoggedUser('Authorize');
    super.service = service;
  }

  @override
  Future<void> start() {
    return serve(service);
  }

}