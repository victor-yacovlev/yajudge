import '../../yajudge_common.dart';

extension CourseDataExtension on CourseData {

  void cleanPrivateContent() {
    // must be called only after deepCopy

    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          problem.cleanPrivateContent();
        }
      }
    }
  }

  Lesson findLessonByKey(String key) {
    if (key.startsWith('/')) {
      key = key.substring(1);
    }
    List<String> parts = key.split('/');
    parts.removeWhere((element) => element.isEmpty);
    Section section = Section();
    String lessonId;
    if (sections.length==1 && sections.single.id.isEmpty) {
      section = sections.single;
      assert (parts.isNotEmpty);
      lessonId = parts[0];
    }
    else {
      assert(parts.length >= 2);
      String sectionId = parts[0];
      lessonId = parts[1];
      for (final entry in sections) {
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

  TextReading findReadingByKey(String key) {
    final parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (final section in sections) {
      if (section.id == parts[0]) {
        for (final lesson in section.lessons) {
          if (lesson.id == parts[1]) {
            for (final reading in lesson.readings) {
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

  ProblemData findProblemByKey(String key) {
    final parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (final section in sections) {
      if (section.id == parts[0]) {
        for (final lesson in section.lessons) {
          if (lesson.id == parts[1]) {
            for (final problem in lesson.problems) {
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

  ProblemData findProblemById(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          if (problem.id == problemId) {
            return problem;
          }
        }
      }
    }
    return ProblemData();
  }

  ProblemMetadata findProblemMetadataById(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problemsMetadata) {
          if (problem.id == problemId) {
            return problem;
          }
        }
      }
    }
    return ProblemMetadata();
  }

  Lesson findEnclosingLessonForProblem(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problemsMetadata) {
          if (problem.id == problemId) {
            return lesson;
          }
        }
      }
    }
    return Lesson();
  }

  List<Lesson> allLessons() {
    List<Lesson> result = [];
    for (final section in sections) {
      result.addAll(section.lessons);
    }
    return result;
  }

}