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

TextReading? findReadingByKey(CourseData courseData, String key) {
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
  return null;
}

ProblemData? findProblemByKey(CourseData courseData, String key) {
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
  return null;
}

ProblemData? findProblemById(CourseData courseData, String problemId) {
  for (Section section in courseData.sections) {
    for (Lesson lesson in section.lessons) {
      for (ProblemData problem in lesson.problems) {
        if (problem.id == problemId) {
          return problem;
        }
      }
    }
  }
  return null;
}

ProblemMetadata? findProblemMetadataByKey(CourseData courseData, String key) {
  List<String> parts = key.substring(1).split('/');
  assert (parts.length >= 3);
  for (Section section in courseData.sections) {
    if (section.id == parts[0]) {
      for (Lesson lesson in section.lessons) {
        if (lesson.id == parts[1]) {
          for (ProblemMetadata problem in lesson.problemsMetadata) {
            if (problem.id == parts[2]) {
              return problem;
            }
          }
        }
      }
    }
  }
  return null;
}

GradingLimits parseDefaultLimits(YamlMap conf) {
  int stackSize = 0;
  int memoryMax = 0;
  int cpuTime = 0;
  int realTime = 0;
  int procs = 0;
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
    fdCountLimit: Int64(files),
    stdoutSizeLimitMb: Int64(stdoutMax),
    stderrSizeLimitMb: Int64(stderrMax),
    allowNetwork: allowNetwork,
  );
}