import '../service_launcher.dart';
import 'users_service.dart';

class UsersServiceLauncher extends ServiceLauncherBase {

  UsersServiceLauncher() : super('users');

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    service = UserManagementService(
      dbConnection: databaseConnection,
      secretKey: rpcProperties.privateToken,
    );
  }

}