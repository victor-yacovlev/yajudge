import '../../yajudge_common.dart';

extension UserExtension on User {

  String get fullName {
    return '$lastName $firstName $midName'.trimRight();
  }

}