import 'dart:convert';
import 'dart:math';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:protobuf/protobuf.dart';
import 'package:hex/hex.dart';

import '../../yajudge_common.dart';

extension UserExtension on User {

  String get fullName {
    return '$lastName $firstName $midName'.trimRight();
  }

  static User? fromEncryptedBase64(String b64Data, String secretKey) {
    try {
      final normalizedSecretKey =  HEX.encode(sha256.convert(utf8.encode(secretKey)).bytes);
      final compressed = base64Decode(b64Data);
      final encrypted = Uint8List.fromList(io.gzip.decode(compressed.toList()));
      final encrypter = _initializeEncrypter(normalizedSecretKey);
      final iv = IV.fromUtf8(normalizedSecretKey.substring(0, 16));
      final userProto = encrypter.decryptBytes(Encrypted(encrypted), iv: iv);
      final result = User.fromBuffer(userProto);
      return result;
    }
    catch (_) {
      return null;
    }
  }

  String toEncryptedBase64(String secretKey) {
    final normalizedSecretKey =  HEX.encode(sha256.convert(utf8.encode(secretKey)).bytes);
    final userWithoutPassword = deepCopy()..clearPassword();
    final userProto = userWithoutPassword.writeToBuffer();
    if (userProto.length == 0) {
      return '';
    }
    final encrypter = _initializeEncrypter(normalizedSecretKey);
    final iv = IV.fromUtf8(normalizedSecretKey.substring(0, 16));
    final encrypted = encrypter.encryptBytes(userProto.toList(), iv: iv).bytes.toList();
    final compressed = io.gzip.encode(encrypted);
    final b64Data = base64Encode(compressed);
    return b64Data;
  }

  static Encrypter _initializeEncrypter(String secretKey) {
    final keyHash = sha256.convert(utf8.encode(secretKey)).bytes;
    Key key = Key(Uint8List.fromList(keyHash));
    Algorithm algorithm = AES(key);
    Encrypter encrypter = Encrypter(algorithm);
    return encrypter;
  }

}

String makePasswordHash(String password, dynamic salt) {
  // Note on ')' typo after $salt
  // This is a bug that should be kept for compatibility reasons
  String salted = '$password $salt)';
  String hexDigest = sha512.convert(utf8.encode(salted)).toString().toLowerCase();
  return hexDigest;
}

String generateRandomPassword() {
  final String alphabet = '01234567abcdef';
  String password = '';
  Random random = Random.secure();
  for (int i=0; i<8; i++) {
    int runeNum = random.nextInt(alphabet.length - 1);
    String rune = alphabet[runeNum];
    password += rune;
  }
  return password;
}