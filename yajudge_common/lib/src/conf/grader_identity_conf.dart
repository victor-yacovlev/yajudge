import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:yaml/yaml.dart';

import '../generated/yajudge.pb.dart';

class GraderIdentityProperties {
  final String name;
  late final Arch arch;

  GraderIdentityProperties(this.name) {
    final archName = Process.runSync('arch', []).stdout.toString().trim();
    if (archName == 'i386' && Platform.isMacOS) {
      arch = Arch.ARCH_X86_64;
    } else if (archName.startsWith('i') && archName.endsWith('86')) {
      arch = Arch.ARCH_X86;
    } else if (archName == 'x86_64') {
      arch = Arch.ARCH_X86_64;
    } else if (archName == 'aarch64' || archName == 'arm64') {
      arch = Arch.ARCH_AARCH64;
    } else if (archName.startsWith('arm')) {
      arch = Arch.ARCH_ARMV7;
    } else {
      throw GrpcError.internal('this arch not supported: $archName');
    }
  }

  factory GraderIdentityProperties.fromYamlConfig(YamlMap? conf) {
    String name = '';
    if (conf != null && conf.containsKey('name')) {
      name = conf['name'];
    }
    return GraderIdentityProperties(name);
  }
}
