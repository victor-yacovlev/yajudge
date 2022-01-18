import 'package:grpc/grpc.dart';

import './generated/yajudge.pb.dart';

class CourseDataCacheItem {
  final CourseData? data;
  final DateTime? lastModified;
  final DateTime? lastChecked;
  final GrpcError? loadError;

  CourseDataCacheItem({
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