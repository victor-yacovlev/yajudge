import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'courses_service.dart';

class CourseServiceLauncher extends ServiceLauncherBase {

  CourseServiceLauncher() : super('courses');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    final service = CourseManagementService(
      connection: databaseConnection,
      services: services,
      secretKey: rpcProperties.privateToken,
    );
    super.service = service;
    super.markMethodAllowNotLoggedUser('GetUserEnrollments');
    super.markMethodAllowNotLoggedUser('GetGroupEnrollments');
    super.markMethodAllowNotLoggedUser('GetAllGroupsEnrollments');
  }

}