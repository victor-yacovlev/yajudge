import 'package:json_annotation/json_annotation.dart';

import 'connection.dart';
import 'courses.dart';
import 'users.dart';

part 'submissions.g.dart';

const SolutionStatus_Any                = 0;
const SolutionStatus_Submitted          = 1;
const SolutionStatus_GradeInProgress    = 2;
const SolutionStatus_StyleCheckError    = 3;
const SolutionStatus_CompilationError   = 4;
const SolutionStatus_VeryBad            = 5;  // no one test passed
const SolutionStatus_Acceptable         = 6;  // grade score > 0 (if accept partial solution) or score is full
const SolutionStatus_PendingReview      = 7;
const SolutionStatus_CodeReviewRejected = 8;
const SolutionStatus_AcceptedForDefence = 9;
const SolutionStatus_DefenceFailed      = 10;
const SolutionStatus_PlagiarismDetected = 11;
const SolutionStatus_Disqualified       = 12;
const SolutionStatus_CheckFailed        = 13;
const SolutionStatus_OK                 = 100;
const SolutionStatus_GraderAssigned     = 201;

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class Submission {
  int id = 0;
  User user = User();
  Course course = Course();
  int timestamp = 0;
  int status = 0;
  String problemId = '';
  FileSet solutionFiles = FileSet();

  Submission();
  factory Submission.fromJson(Map<String,dynamic> json) => _$SubmissionFromJson(json);
  Map<String,dynamic> toJson() => _$SubmissionToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CheckSubmissionsLimitRequest {
  User user = User();
  Course course = Course();
  String problemId = '';

  CheckSubmissionsLimitRequest();
  factory CheckSubmissionsLimitRequest.fromJson(Map<String,dynamic> json) => _$CheckSubmissionsLimitRequestFromJson(json);
  Map<String,dynamic> toJson() => _$CheckSubmissionsLimitRequestToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class SubmissionsCountLimit {
  int attemptsLeft = 0;
  int nextTimeReset = 0;
  int serverTime = 0;

  SubmissionsCountLimit();
  factory SubmissionsCountLimit.fromJson(Map<String,dynamic> json) => _$SubmissionsCountLimitFromJson(json);
  Map<String,dynamic> toJson() => _$SubmissionsCountLimitToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class SubmissionFilter {
  User user = User();
  Course course = Course();
  String problemId = '';
  int status = 0;

  SubmissionFilter();
  factory SubmissionFilter.fromJson(Map<String,dynamic> json) => _$SubmissionFilterFromJson(json);
  Map<String,dynamic> toJson() => _$SubmissionFilterToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class SubmissionList {
  List<Submission> submissions = List.empty(growable: true);

  SubmissionList();
  factory SubmissionList.fromJson(Map<String,dynamic> json) => _$SubmissionListFromJson(json);
  Map<String,dynamic> toJson() => _$SubmissionListToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class ProblemStatus {
  String  problemId = '';
  int solutionStatus = 0;

  ProblemStatus();
  factory ProblemStatus.fromJson(Map<String,dynamic> json) => _$ProblemStatusFromJson(json);
  Map<String,dynamic> toJson() => _$ProblemStatusToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CheckCourseStatusRequest {
  User user = User();
  Course course = Course();

  CheckCourseStatusRequest();
  factory CheckCourseStatusRequest.fromJson(Map<String,dynamic> json) => _$CheckCourseStatusRequestFromJson(json);
  Map<String,dynamic> toJson() => _$CheckCourseStatusRequestToJson(this);
}

@JsonSerializable(includeIfNull: false, fieldRename: FieldRename.snake)
class CheckCourseStatusResponse {
  List<ProblemStatus> problemStatuses = List.empty(growable: true);

  CheckCourseStatusResponse();
  factory CheckCourseStatusResponse.fromJson(Map<String,dynamic> json) => _$CheckCourseStatusResponseFromJson(json);
  Map<String,dynamic> toJson() => _$CheckCourseStatusResponseToJson(this);
}


class SubmissionService extends ServiceBase {
  SubmissionService(RpcConnection connection)
      : super('SubmissionManagement', connection) {
    if (_instance == null) {
      _instance = this;
    }
  }

  static SubmissionService? _instance;

  static SubmissionService get instance {
    assert (_instance != null);
    return _instance!;
  }

  Future<SubmissionsCountLimit> checkSubmissionsCountLimit(CheckSubmissionsLimitRequest request) async {
    Future res = callUnaryMethod('CheckSubmissionsCountLimit', request);
    try {
      var dataJson = await res;
      SubmissionsCountLimit response = SubmissionsCountLimit.fromJson(dataJson);
      return response;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<Submission> submitProblemSolution(Submission request) async {
    Future res = callUnaryMethod('SubmitProblemSolution', request);
    try {
      var dataJson = await res;
      Submission response = Submission.fromJson(dataJson);
      return response;
    } catch (err) {
      return Future.error(err);
    }
  }

  Future<SubmissionList> getSubmissions(SubmissionFilter request) async {
    Future res = callUnaryMethod('GetSubmissions', request);
    try {
      var dataJson = await res;
      SubmissionList response = SubmissionList.fromJson(dataJson);
      return response;
    } catch (err) {
      return Future.error(err);
    }
  }


}