import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';

extension ServiceCallExtension on ServiceCall {

  String get session {
    final metadata = clientMetadata ?? {};
    final value = metadata.containsKey('session')? metadata['session']! : '';
    if (value.isEmpty) {
      return '';
    }
    final parts = value.split('|');
    return parts[0];
  }

  void setSessionAndUser(String cookie, User user, String secretKey) {
    final userData = user.toEncryptedBase64(secretKey);
    final value = '$cookie|$userData';
    clientMetadata!['session'] = value;
  }

  User? getSessionUser(String secretKey) {
    final metadata = clientMetadata ?? {};
    final value = metadata.containsKey('session')? metadata['session']! : '';
    if (value.isEmpty) {
      return null;
    }
    final parts = value.split('|');
    if (parts.length < 2) {
      return null;
    }
    final b64Data = parts[1];
    if (b64Data.isEmpty) {
      return null;
    }
    return UserExtension.fromEncryptedBase64(b64Data, secretKey);
  }


}