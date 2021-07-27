import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

import 'connection.dart';
import 'users.dart';
part 'courses.g.dart';

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class YFile {
  String name = '';
  List<int> data = List.empty(growable: true);
  String description = '';

  YFile();
  factory YFile.fromJson(Map<String,dynamic> json) => _$YFileFromJson(json);
  Map<String,dynamic> toJson() => _$YFileToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class FileSet {
  List<YFile> files = List.empty(growable: true);

  FileSet();
  factory FileSet.fromJson(Map<String,dynamic> json) => _$FileSetFromJson(json);
  Map<String,dynamic> toJson() => _$FileSetToJson(this);
}


@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class ProblemData {
  String id = '';
  String title = '';
  String uniqueId = '';
  String statementText = '';
  String statementContentType = '';
  FileSet statementFiles = FileSet();
  FileSet solutionFiles = FileSet();

  ProblemData();
  factory ProblemData.fromJson(Map<String,dynamic> json) => _$ProblemDataFromJson(json);
  Map<String,dynamic> toJson() => _$ProblemDataToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class ProblemMetadata {
  String id = '';
  double fullScoreMultiplier = 1.0;
  bool blocksNextProblems = false;
  bool skipSolutionDefence = false;
  bool skipCodeReview = false;

  ProblemMetadata();
  factory ProblemMetadata.fromJson(Map<String,dynamic> json) => _$ProblemMetadataFromJson(json);
  Map<String,dynamic> toJson() => _$ProblemMetadataToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class TextReading {
  String id = '';
  String title = '';
  String contentType = '';
  String data = '';

  TextReading();
  factory TextReading.fromJson(Map<String,dynamic> json) => _$TextReadingFromJson(json);
  Map<String,dynamic> toJson() => _$TextReadingToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Lesson {
  String id = '';
  String name = '';
  String description = '';
  int openDate = 0;
  int softDeadline = 0;
  int hardDeadline = 0;
  List<TextReading> readings = List.empty(growable: true);
  List<ProblemData> problems = List.empty(growable: true);
  List<ProblemMetadata> problemsMetadata = List.empty(growable: true);

  Lesson();
  factory Lesson.fromJson(Map<String,dynamic> json) => _$LessonFromJson(json);
  Map<String,dynamic> toJson() => _$LessonToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Section {
  String id = '';
  String name = '';
  String? description;
  int openDate = 0;
  int softDeadline = 0;
  int hardDeadline = 0;
  List<Lesson> lessons = List.empty(growable: true);

  Section();
  factory Section.fromJson(Map<String,dynamic> json) => _$SectionFromJson(json);
  Map<String,dynamic> toJson() => _$SectionToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CourseData {
  String id = '';
  String? description;
  List<Section> sections = List.empty(growable: true);

  CourseData();
  factory CourseData.fromJson(Map<String,dynamic> json) => _$CourseDataFromJson(json);
  Map<String,dynamic> toJson() => _$CourseDataToJson(this);

  TextReading? findReadingByKey(String key) {
    List<String> parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (Section section in sections) {
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

  ProblemData? findProblemByKey(String key) {
    List<String> parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (Section section in sections) {
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

  ProblemMetadata? findProblemMetadataByKey(String key) {
    List<String> parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (Section section in sections) {
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

}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Course {
  int id;
  String name;
  CourseData courseData;
  String urlPrefix;

  Course() : id=0, name='', courseData=CourseData(), urlPrefix='';
  factory Course.fromJson(Map<String,dynamic> json) => _$CourseFromJson(json);
  Map<String,dynamic> toJson() => _$CourseToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Enrollment {
  Course course;
  User user;
  int role;

  Enrollment() : course = Course(), user = User(), role = 0;
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CoursesFilter {
  User user;
  Course course;
  bool partialStringMatch;

  CoursesFilter() : user = User(), course = Course(), partialStringMatch = true;
  Map<String,dynamic> toJson() => _$CoursesFilterToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CourseListEntry {
  Course course;
  int role;

  CourseListEntry() : course = Course(), role = UserRole_Any;
  factory CourseListEntry.fromJson(Map<String,dynamic> json) => _$CourseListEntryFromJson(json);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CoursesList {
  List<CourseListEntry> courses;

  CoursesList() : courses = List.empty(growable: true);
  factory CoursesList.fromJson(Map<String,dynamic> json) => _$CoursesListFromJson(json);
}

const CourseContentStatus_HAS_DATA = 0;
const CourseContentStatus_NOT_CHANGED = 1;

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CourseContentRequest {
  String courseDataId;
  int cachedTimestamp;

  CourseContentRequest() : courseDataId='', cachedTimestamp=0;
  factory CourseContentRequest.fromJson(Map<String,dynamic> json) => _$CourseContentRequestFromJson(json);
  Map<String,dynamic> toJson() => _$CourseContentRequestToJson(this);
}

@JsonSerializable(includeIfNull: true, fieldRename: FieldRename.snake)
class CourseContentResponse {
  String courseDataId;
  int status;
  CourseData? data;
  int lastModified;

  CourseContentResponse() : courseDataId='', status=0, data=null, lastModified=0;
  factory CourseContentResponse.fromJson(Map<String,dynamic> json) => _$CourseContentResponseFromJson(json);
  Map<String,dynamic> toJson() => _$CourseContentResponseToJson(this);
}

class CoursesService extends ServiceBase {
  CoursesService(RpcConnection connection)
      : super('CourseManagement', connection) {
    if (_instance == null) {
      _instance = this;
    }
  }

  static CoursesService? _instance;
  static CoursesService get instance { assert (_instance != null); return _instance!; }

  Future<CoursesList> getCourses(CoursesFilter coursesFilter) async {
    Future res = callUnaryMethod('GetCourses', coursesFilter);
    try {
      var dataJson = await res;
      CoursesList list = CoursesList.fromJson(dataJson);
      return list;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<CourseContentResponse> getCoursePublicContent(CourseContentRequest request) async {
    Future res = callUnaryMethod('GetCoursePublicContent', request);
    try {
      var dataJson = await res;
      CourseContentResponse response = CourseContentResponse.fromJson(dataJson);
      return response;
    } catch (err) {
      return Future.error(err);
    }
  }

}
