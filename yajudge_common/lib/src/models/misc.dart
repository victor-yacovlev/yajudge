import 'package:yaml/yaml.dart';

import '../../yajudge_common.dart';

Map<String,String> propertiesFromYaml(dynamic conf) {
  Map<String,String> result = {};
  if (conf is YamlMap) {
    final props = conf;
    for (final property in props.entries) {
      final propertyName = property.key.toString();
      final propertyValue = property.value.toString();
      result[propertyName] = propertyValue;
    }
  }
  return result;
}

String propertiesToYaml(Map<String,String> props) {
  String result = '';
  for (final key in props.keys) {
    final value = props[key];
    result += '$key: \'$value\'\n';
  }
  return result;
}

class CourseDataCacheItem {
  CourseData? data;
  DateTime? lastModified;
  DateTime? lastChecked;
  Object? loadError;

  CourseDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}

class ProblemDataCacheItem {
  ProblemData? data;
  DateTime? lastModified;
  DateTime? lastChecked;
  Object? loadError;

  ProblemDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}


bool submissionsCountLimitIsValid(SubmissionsCountLimit countLimit) {
  return countLimit.attemptsLeft!=0 || countLimit.nextTimeReset!=0;
}


enum ProgrammingLanguage {
  unknown,
  c,
  cxx,
  java,
  python,
  bash,
  go,
  gnuAsm,
}

