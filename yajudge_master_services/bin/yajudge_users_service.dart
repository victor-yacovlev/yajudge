import 'package:yajudge_master_services/yajudge_master_services.dart';

void main(List<String> arguments) {
  final launcher = UsersServiceLauncher();
  launcher.initialize(arguments).then((_) => launcher.start());
}
