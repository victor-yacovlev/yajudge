import 'package:yajudge_common/yajudge_common.dart';

import '../service_launcher.dart';
import 'review_service.dart';

class ReviewServiceLauncher extends ServiceLauncherBase {

  ReviewServiceLauncher() : super('review');
  late final UserManagementClient userManager;
  late final SubmissionManagementClient submissionManager;

  @override
  Future<void> initialize(List<String> commandLineArguments) async {
    await super.initialize(commandLineArguments);
    userManager = createExternalApi('UserManagement', (c,i) => UserManagementClient(c, interceptors: i));
    submissionManager = createExternalApi('SubmissionManagement', (c,i) => SubmissionManagementClient(c, interceptors: i));
    final service = CodeReviewManagementService(
      submissionManager: submissionManager,
      userManager: userManager,
      connection: databaseConnection,
      secretKey: rpcProperties.privateToken,
    );
    super.service = service;
  }

}