import 'dart:io';
import 'package:grpc/grpc.dart';
import '../generated/yajudge.pb.dart';
import 'package:yaml/yaml.dart';

class GraderIdentityProperties {
  final String name;
  final List<String>? runtimes;
  final List<String>? compilers;
  late final Arch arch;
  late final OS os;
  
  GraderIdentityProperties(this.name, {this.runtimes, this.compilers}) {
    if (Platform.isLinux) {
      os = OS.OS_LINUX;
    }
    else if (Platform.isMacOS) {
      os = OS.OS_DARWIN;
    }
    else if (Platform.isWindows) {
      os = OS.OS_WINDOWS;
      arch = Arch.ARCH_X86;
    }
    else {
      throw GrpcError.internal('this OS not supported: ${Platform.operatingSystem}');
    }
    if (os != OS.OS_WINDOWS) {
      final archName = Process.runSync('arch', []).stdout.toString().trim();
      if (archName=='i386' && os==OS.OS_DARWIN) {
        arch = Arch.ARCH_X86_64;
      }
      else if (archName.startsWith('i') && archName.endsWith('86')) {
        arch = Arch.ARCH_X86;
      }
      else if (archName=='x86_64') {
        arch = Arch.ARCH_X86_64;
      }
      else if (archName=='aarch64') {
        arch = Arch.ARCH_AARCH64;
      }
      else if (archName.startsWith('arm')) {
        arch = Arch.ARCH_ARMV7;
      }
      else {
        throw GrpcError.internal('this arch not supported: $archName');
      }
    }
  }

  factory GraderIdentityProperties.fromYamlConfig(YamlMap? conf) {
    List<String>? runtimes;
    List<String>? compilers;
    String name;
    if (conf != null && conf.containsKey('name')) {
      name = conf['name'];
    } else {
      name = Platform.localHostname;
    }
    return GraderIdentityProperties(name, runtimes: runtimes, compilers: compilers);
  }
}