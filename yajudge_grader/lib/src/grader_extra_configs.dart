import 'package:fixnum/fixnum.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml/yaml.dart';
import 'package:protobuf/protobuf.dart';
import 'dart:io';

class JobsConfig {
  final bool archSpecificOnly;
  final int workers;

  JobsConfig({
    required this.archSpecificOnly,
    required this.workers,
  });

  factory JobsConfig.fromYaml(YamlMap conf) {
    bool archSpecificOnly = false;
    int workers = 0;
    if (conf['arch_specific_only'] is bool) {
      archSpecificOnly = true;
    }
    if (conf['workers'] is int) {
      workers = conf['workers'];
    }
    return JobsConfig(
      archSpecificOnly: archSpecificOnly,
      workers: workers,
    );
  }

  factory JobsConfig.createDefault() {
    return JobsConfig(
      archSpecificOnly: false,
      workers: 0,
    );
  }

}

class TargetProperties {
  final String compiler;
  final String executable;
  final Map<String,String> properties;

  TargetProperties({
    this.compiler = '',
    this.executable = '',
    required this.properties
  });

  factory TargetProperties.createDefaultForCompiler(String compiler) {
    return TargetProperties(compiler: compiler, properties: {});
  }

  factory TargetProperties.createDefaultForRuntime(String executable) {
    return TargetProperties(executable: executable, properties: {});
  }

  factory TargetProperties.fromMap(Map<String,String> properties) {
    return TargetProperties(properties: properties);
  }

  factory TargetProperties.fromYaml(YamlMap conf) {
    String compiler = '';
    String executable = '';
    Map<String,String> properties = {};
    for (final property in conf.entries) {
      final key = property.key.toString().replaceAll('-', '_');
      final value = property.value.toString();
      if (key == 'compiler') {
        compiler = value;
      }
      else if (key == 'executable') {
        executable = value;
      }
      else {
        properties[key] = value;
      }
    }
    return TargetProperties(
      compiler: compiler,
      executable: executable,
      properties: properties
    );
  }

  TargetProperties mergeWith(TargetProperties other) {
    Map<String,String> newProperties = Map.from(properties);
    for (final otherEntry in other.properties.entries) {
      final key = otherEntry.key;
      if (newProperties.containsKey(otherEntry.key)) {
        final String oldValue = newProperties[key]!;
        Set<String> items = oldValue.split(' ').toSet();
        final String otherValue = otherEntry.value;
        Set<String> newItems = otherValue.split(' ').toSet();
        items = items.union(newItems);
        final newValue = items.join(' ');
        newProperties[key] = newValue;
      }
      else {
        newProperties[key] = otherEntry.value;
      }
    }
    return TargetProperties(compiler: compiler, properties: newProperties);
  }

  List<String> property(String name) {
    if (properties.containsKey(name.replaceAll('-', '_'))) {
      return properties[name]!.split(' ');
    }
    else {
      return [];
    }
  }

}


class DefaultBuildProperties {
  final Map<ProgrammingLanguage,TargetProperties> properties;

  DefaultBuildProperties(this.properties);

  factory DefaultBuildProperties.fromYaml(YamlMap conf) {
    Map<ProgrammingLanguage,TargetProperties> result = {};
    for (final entry in conf.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      final language = _guessLanguageByName(key);
      if (value is YamlMap && language != ProgrammingLanguage.unknown) {
        final properties = TargetProperties.fromYaml(value);
        result[language] = properties;
      }
    }
    return DefaultBuildProperties(result);
  }

  TargetProperties propertiesForLanguage(ProgrammingLanguage language) {
    if (properties.containsKey(language)) {
      return properties[language]!;
    }
    else {
      return _defaultForLanguage(language);
    }
  }

  TargetProperties _defaultForLanguage(ProgrammingLanguage language) {
    switch (language) {
      case ProgrammingLanguage.c:
        return TargetProperties.createDefaultForCompiler('gcc');
      case ProgrammingLanguage.cxx:
        return TargetProperties.createDefaultForCompiler('g++');
      case ProgrammingLanguage.java:
        return TargetProperties.createDefaultForCompiler('javac');
      case ProgrammingLanguage.python:
        return TargetProperties.createDefaultForCompiler('');
      case ProgrammingLanguage.bash:
        return TargetProperties.createDefaultForCompiler('');
      case ProgrammingLanguage.go:
        return TargetProperties.createDefaultForCompiler('go');
      case ProgrammingLanguage.gnuAsm:
        return TargetProperties.createDefaultForCompiler('gcc');
      default:
        throw Exception('dont know how to handle unknown programming language');
    }
  }

  static ProgrammingLanguage _guessLanguageByName(String name) {
    switch (name.toLowerCase().replaceAll('_', '').replaceAll('-', '')) {
      case 'c':
        return ProgrammingLanguage.c;
      case 'cpp':
      case 'cxx':
      case 'c++':
      case 'cc':
        return ProgrammingLanguage.cxx;
      case 'java':
        return ProgrammingLanguage.java;
      case 'python':
        return ProgrammingLanguage.python;
      case 'shell':
      case 'bash':
        return ProgrammingLanguage.bash;
      case 'go':
      case 'golang':
        return ProgrammingLanguage.go;
      case 's':
      case 'gnuasm':
        return ProgrammingLanguage.gnuAsm;
      default:
        return ProgrammingLanguage.unknown;
    }
  }
}

class DefaultRuntimeProperties {
  final Map<ExecutableTarget,TargetProperties> properties;

  DefaultRuntimeProperties(this.properties);

  factory DefaultRuntimeProperties.fromYaml(YamlMap conf) {
    Map<ExecutableTarget,TargetProperties> result = {};
    for (final entry in conf.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      final target = _guessTargetByName(key);
      if (value is YamlMap && target != ExecutableTarget.AutodetectExecutable) {
        final properties = TargetProperties.fromYaml(value);
        result[target] = properties;
      }
    }
    return DefaultRuntimeProperties(result);
  }

  TargetProperties propertiesForRuntime(ExecutableTarget target) {
    if (properties.containsKey(target)) {
      return properties[target]!;
    }
    else {
      return _defaultForTarget(target);
    }
  }

  static ExecutableTarget _guessTargetByName(key) {
    return executableTargetFromString(key);
  }

  TargetProperties _defaultForTarget(ExecutableTarget target) {
    switch (target) {
      case ExecutableTarget.ShellScript:
        return TargetProperties.createDefaultForRuntime('bash');
      case ExecutableTarget.JavaClass:
        return TargetProperties.createDefaultForRuntime('java');
      case ExecutableTarget.JavaJar:
        return TargetProperties.createDefaultForRuntime('java');
      case ExecutableTarget.Native:
        return TargetProperties.createDefaultForRuntime('');
      case ExecutableTarget.NativeWithSanitizers:
        return TargetProperties.createDefaultForRuntime('');
      case ExecutableTarget.NativeWithSanitizersAndValgrind:
        return TargetProperties.createDefaultForRuntime('valgrind');
      case ExecutableTarget.NativeWithValgrind:
        return TargetProperties.createDefaultForRuntime('valgrind');
      case ExecutableTarget.PythonScript:
        throw UnimplementedError('python runtime not implemented yet');
      case ExecutableTarget.QemuSystemImage:
        throw UnimplementedError('qemu system image runtime not implemented yet');
      default:
        throw Exception('cant get properties for unknown runtime');
    }
  }
}
