import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'sessions_service.dart';

class SessionsServiceLauncher extends ServiceLauncherBase {

  SessionsServiceLauncher() : super('sessions');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    super.initialize(commandLineArguments);
    final service = SessionManagementService(
      dbConnection: databaseConnection,
      services: services,
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