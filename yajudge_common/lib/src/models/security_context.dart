import 'package:yaml/yaml.dart';

import '../../yajudge_common.dart';

SecurityContext securityContextFromYaml(dynamic confOrNull) {
  if (confOrNull == null || confOrNull !is YamlMap) {
    return SecurityContext();
  }
  YamlMap conf = confOrNull;
  List<String> forbiddenFunctions = [];
  List<String> allowedFunctions = [];

  if (conf['forbidden_functions'] is YamlList) {
    YamlList list = conf['forbidden_functions'];
    for (final entry in list) {
      String name = entry;
      if (!forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  else if (conf['forbidden_functions'] is String) {
    final parts = (conf['forbidden_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  if (conf['allowed_functions'] is YamlList) {
    YamlList list = conf['allowed_functions'];
    for (final entry in list) {
      String name = entry;
      if (!allowedFunctions.contains(name)) {
        allowedFunctions.add(name);
      }
    }
  }
  else if (conf['allowed_functions'] is String) {
    final parts = (conf['allowed_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !allowedFunctions.contains(name)) {
        allowedFunctions.add(name);
      }
    }
  }
  return SecurityContext(
    forbiddenFunctions: forbiddenFunctions,
    allowedFunctions: allowedFunctions,
  );
}

SecurityContext mergeSecurityContext(SecurityContext source, SecurityContext update) {
  List<String> forbiddenFunctions = source.forbiddenFunctions;
  for (final name in update.forbiddenFunctions) {
    if (!forbiddenFunctions.contains(name)) {
      forbiddenFunctions.add(name);
    }
  }
  for (final name in update.allowedFunctions) {
    if (forbiddenFunctions.contains(name)) {
      forbiddenFunctions.remove(name);
    }
  }
  return SecurityContext(forbiddenFunctions: forbiddenFunctions);
}

SecurityContext mergeSecurityContextFromYaml(SecurityContext source, YamlMap conf) {
  List<String> forbiddenFunctions = source.forbiddenFunctions;
  if (conf['forbidden_functions'] is YamlList) {
    YamlList list = conf['forbidden_functions'];
    for (final entry in list) {
      String name = entry;
      if (!forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  else if (conf['forbidden_functions'] is String) {
    final parts = (conf['forbidden_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  if (conf['allowed_functions'] is YamlList) {
    YamlList list = conf['allowed_functions'];
    for (final entry in list) {
      String name = entry;
      if (forbiddenFunctions.contains(name)) {
        forbiddenFunctions.remove(name);
      }
    }
  }
  else if (conf['allowed_functions'] is String) {
    final parts = (conf['allowed_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && forbiddenFunctions.contains(name)) {
        forbiddenFunctions.remove(name);
      }
    }
  }
  return SecurityContext(
      forbiddenFunctions: forbiddenFunctions
  );
}

String securityContextToYamlString(SecurityContext securityContext, [int level = 0]) {
  String indent = level > 0 ? '  ' * level : '';
  String result = '';
  if (securityContext.allowedFunctions.isNotEmpty) {
    result += '${indent}allowed_functions: ${securityContext.allowedFunctions.join(' ')}\n';
  }
  if (securityContext.forbiddenFunctions.isNotEmpty) {
    result += '${indent}forbidden_functions: ${securityContext.forbiddenFunctions.join(' ')}\n';
  }
  return result;
}