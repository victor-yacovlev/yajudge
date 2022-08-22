import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';

extension ServiceCallExtension on ServiceCall {

  String get session {
    final metadata = clientMetadata ?? {};
    final value = metadata.containsKey('session')? metadata['session']! : '';
    return value;
  }

  set session(String cookie) {
    clientMetadata!['session'] = cookie;
  }

  User? getSessionUser(String secretKey) {
    final b64Data = clientMetadata!['session_user'];
    if (b64Data == null || b64Data.isEmpty) {
      return null;
    }
    return UserExtension.fromEncryptedBase64(b64Data, secretKey);
  }


}