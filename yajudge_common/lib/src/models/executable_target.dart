import '../../yajudge_common.dart';

ExecutableTarget executableTargetFromString(dynamic conf) {
  String c = '';
  if (conf is String) {
    c = conf.toLowerCase().replaceAll('-', '_');
  }
  switch (c) {
    case 'bash_script':
    case 'bash':
    case 'shell':
    case 'shell_script':
      return ExecutableTarget.ShellScript;
    case 'python_script':
    case 'python':
      return ExecutableTarget.PythonScript;
    case 'native':
    case 'unchecked':
      return ExecutableTarget.Native;
    case 'valgrind':
      return ExecutableTarget.NativeWithValgrind;
    case 'sanitizers':
    case 'sanitized':
      return ExecutableTarget.NativeWithSanitizers;
    case 'checked':
      return ExecutableTarget.NativeWithSanitizersAndValgrind;
    case 'java':
    case 'jre':
    case 'java_class':
    case 'class':
      return ExecutableTarget.JavaClass;
    case 'java_jar':
    case 'jar':
      return ExecutableTarget.JavaJar;
    case 'qemu_system':
    case 'qemu_image':
    case 'qemu_system_image':
      return ExecutableTarget.QemuSystemImage;
    default:
      return ExecutableTarget.AutodetectExecutable;
  }
}

String executableTargetToString(ExecutableTarget target) {
  switch (target) {
    case ExecutableTarget.AutodetectExecutable:
      return 'auto';
    case ExecutableTarget.ShellScript:
      return 'shell';
    case ExecutableTarget.JavaClass:
      return 'java';
    case ExecutableTarget.JavaJar:
      return 'java-jar';
    case ExecutableTarget.Native:
      return 'native';
    case ExecutableTarget.NativeWithSanitizers:
      return 'sanitizers';
    case ExecutableTarget.NativeWithValgrind:
      return 'valgrind';
    case ExecutableTarget.NativeWithSanitizersAndValgrind:
      return 'checked';
    case ExecutableTarget.PythonScript:
      return 'python';
    case ExecutableTarget.QemuSystemImage:
      return 'qemu-system';
    default:
      return 'auto';
  }
}