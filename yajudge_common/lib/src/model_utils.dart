import 'package:grpc/grpc.dart';
import 'package:fixnum/fixnum.dart';
import 'package:yaml/yaml.dart';
import './generated/yajudge.pb.dart';

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

Lesson findLessonByKey(CourseData courseData, String key) {
  if (key.startsWith('/')) {
    key = key.substring(1);
  }
  List<String> parts = key.split('/');
  parts.removeWhere((element) => element.isEmpty);
  Section section = Section();
  String lessonId;
  if (courseData.sections.length==1 && courseData.sections.single.id.isEmpty) {
    section = courseData.sections.single;
    assert (parts.length >= 1);
    lessonId = parts[0];
  }
  else {
    assert(parts.length >= 2);
    String sectionId = parts[0];
    lessonId = parts[1];
    for (final entry in courseData.sections) {
      if (entry.id == sectionId) {
        section = entry;
        break;
      }
    }
  }

  Lesson lesson = Lesson();
  for (final entry in section.lessons) {
    if (entry.id == lessonId) {
      lesson = entry;
      break;
    }
  }

  return lesson;
}

ProblemStatus findProblemStatus(CourseStatus course, String problemId) {
  for (final section in course.sections) {
    for (final lesson in section.lessons) {
      for (final problem in lesson.problems) {
        if (problem.problemId == problemId) {
          return problem;
        }
      }
    }
  }
  return ProblemStatus();
}

TextReading findReadingByKey(CourseData courseData, String key) {
  List<String> parts = key.substring(1).split('/');
  assert (parts.length >= 3);
  for (Section section in courseData.sections) {
    if (section.id == parts[0]) {
      for (Lesson lesson in section.lessons) {
        if (lesson.id == parts[1]) {
          for (TextReading reading in lesson.readings) {
            if (reading.id == parts[2]) {
              return reading;
            }
          }
        }
      }
    }
  }
  return TextReading();
}


ProblemData findProblemByKey(CourseData courseData, String key) {
  List<String> parts = key.substring(1).split('/');
  assert (parts.length >= 3);
  for (Section section in courseData.sections) {
    if (section.id == parts[0]) {
      for (Lesson lesson in section.lessons) {
        if (lesson.id == parts[1]) {
          for (ProblemData problem in lesson.problems) {
            if (problem.id == parts[2]) {
              return problem;
            }
          }
        }
      }
    }
  }
  return ProblemData();
}

ProblemData findProblemById(CourseData courseData, String problemId) {
  for (Section section in courseData.sections) {
    for (Lesson lesson in section.lessons) {
      for (ProblemData problem in lesson.problems) {
        if (problem.id == problemId) {
          return problem;
        }
      }
    }
  }
  return ProblemData();
}

ProblemMetadata findProblemMetadataById(CourseData courseData, String problemId) {
  for (Section section in courseData.sections) {
    for (Lesson lesson in section.lessons) {
      for (ProblemMetadata problem in lesson.problemsMetadata) {
        if (problem.id == problemId) {
          return problem;
        }
      }
    }
  }
  return ProblemMetadata();
}


bool submissionsCountLimitIsValid(SubmissionsCountLimit countLimit) {
  return countLimit.attemptsLeft!=0 || countLimit.nextTimeReset!=0;
}

GradingLimits limitsFromYaml(YamlMap conf) {
  int stackSize = 0;
  int memoryMax = 0;
  int cpuTime = 0;
  int realTime = 0;
  int procs = 0;
  int procStartDelay = 0;
  int files = 0;
  int stdoutMax = 0;
  int stderrMax = 0;
  bool allowNetwork = false;

  if (conf['stack_size_limit_mb'] is int)
    stackSize = conf['stack_size_limit_mb'];
  if (conf['memory_max_limit_mb'] is int)
    memoryMax = conf['memory_max_limit_mb'];
  if (conf['cpu_time_limit_sec'] is int)
    cpuTime = conf['cpu_time_limit_sec'];
  if (conf['real_time_limit_sec'] is int)
    realTime = conf['real_time_limit_sec'];
  if (conf['proc_count_limit'] is int)
    procs = conf['proc_count_limit'];
  if (conf['new_proc_delay_msec'] is int)
    procStartDelay = conf['new_proc_delay_msec'];
  if (conf['fd_count_limit'] is int)
    files = conf['fd_count_limit'];
  if (conf['stdout_size_limit_mb'] is int)
    stdoutMax = conf['stdout_size_limit_mb'];
  if (conf['stderr_size_limit_mb'] is int)
    stderrMax = conf['stderr_size_limit_mb'];
  if (conf['allow_network'] is bool)
    allowNetwork = conf['allow_network'].toString().toLowerCase()=='true';
  return GradingLimits(
    stackSizeLimitMb: Int64(stackSize),
    memoryMaxLimitMb: Int64(memoryMax),
    cpuTimeLimitSec: Int64(cpuTime),
    realTimeLimitSec: Int64(realTime),
    procCountLimit: Int64(procs),
    newProcDelayMsec: Int64(procStartDelay),
    fdCountLimit: Int64(files),
    stdoutSizeLimitMb: Int64(stdoutMax),
    stderrSizeLimitMb: Int64(stderrMax),
    allowNetwork: allowNetwork,
  );
}

GradingLimits mergeLimitsFromYaml(GradingLimits source, YamlMap conf) {
  return source.copyWith((s) {
    if (conf['stack_size_limit_mb'] is int)
      s.stackSizeLimitMb = Int64(conf['stack_size_limit_mb']);
    if (conf['memory_max_limit_mb'] is int)
      s.memoryMaxLimitMb = Int64(conf['memory_max_limit_mb']);
    if (conf['cpu_time_limit_sec'] is int)
      s.cpuTimeLimitSec = Int64(conf['cpu_time_limit_sec']);
    if (conf['real_time_limit_sec'] is int)
      s.realTimeLimitSec = Int64(conf['real_time_limit_sec']);
    if (conf['proc_count_limit'] is int)
      s.procCountLimit = Int64(conf['proc_count_limit']);
    if (conf['new_proc_delay_msec'] is int)
      s.newProcDelayMsec = Int64(conf['new_proc_delay_msec']);
    if (conf['fd_count_limit'] is int)
      s.fdCountLimit = Int64(conf['fd_count_limit']);
    if (conf['stdout_size_limit_mb'] is int)
      s.stdoutSizeLimitMb = Int64(conf['stdout_size_limit_mb']);
    if (conf['stderr_size_limit_mb'] is int)
      s.stderrSizeLimitMb = Int64(conf['stderr_size_limit_mb']);
    if (conf['allow_network'] is bool)
      s.allowNetwork = conf['allow_network'].toString().toLowerCase()=='true';
  });
}

String limitsToYamlString(GradingLimits limits, [int level = 0]) {
  String indent = level > 0 ? '  ' * level : '';
  String result = '';
  if (limits.stackSizeLimitMb > 0)
    result += '${indent}stack_size_limit_mb: ${limits.stackSizeLimitMb}\n';
  if (limits.memoryMaxLimitMb > 0)
    result += '${indent}memory_max_limit_mb: ${limits.memoryMaxLimitMb}\n';
  if (limits.cpuTimeLimitSec > 0)
    result += '${indent}cpu_time_limit_sec: ${limits.cpuTimeLimitSec}\n';
  if (limits.realTimeLimitSec > 0)
    result += '${indent}real_time_limit_sec: ${limits.realTimeLimitSec}\n';
  if (limits.procCountLimit > 0)
    result += '${indent}proc_count_limit: ${limits.procCountLimit}\n';
  if (limits.newProcDelayMsec > 0)
    result += '${indent}new_proc_delay_msec: ${limits.newProcDelayMsec}\n';
  if (limits.fdCountLimit > 0)
    result += '${indent}fd_count_limit: ${limits.fdCountLimit}\n';
  if (limits.stdoutSizeLimitMb > 0)
    result += '${indent}stdout_size_limit_mb: ${limits.stdoutSizeLimitMb}\n';
  if (limits.stderrSizeLimitMb > 0)
    result += '${indent}stderr_size_limit_mb: ${limits.stderrSizeLimitMb}\n';
  if (limits.allowNetwork)
    result += '${indent}allow_network: ${limits.allowNetwork}\n';
  return result;
}

SecurityContext securityContextFromYaml(YamlMap conf) {
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
  if (securityContext.allowedFunctions.isNotEmpty)
    result += '${indent}allowed_functions: ${securityContext.allowedFunctions.join(' ')}\n';
  if (securityContext.forbiddenFunctions.isNotEmpty)
    result += '${indent}forbidden_functions: ${securityContext.forbiddenFunctions.join(' ')}\n';
  return result;
}
