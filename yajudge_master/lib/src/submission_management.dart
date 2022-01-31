import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:fixnum/fixnum.dart';
import 'master_service.dart';

class SubmissionManagementService extends SubmissionManagementServiceBase {

  final Logger log = Logger('SubmissionManager');
  final PostgreSQLConnection connection;
  final MasterService parent;


  SubmissionManagementService({
    required this.parent,
    required this.connection,
  });

  @override
  Future<CheckCourseStatusResponse> checkCourseStatus(ServiceCall call, CheckCourseStatusRequest request) async {
    Map<String,SolutionStatus> result = Map();
    List<dynamic> rows = await connection.query(
      '''
      select problem_id,status from submissions
      where users_id=%users_id and courses_id=%courses_id
      order by timestamp 
      ''',
      substitutionValues: {
        'users_id': request.user.id.toInt(),
        'courses_id': request.course.id.toInt(),
      }
    );
    for (List<dynamic> fields in rows) {
      String problemId = fields[0];
      SolutionStatus status = SolutionStatus.valueOf(fields[1])!;
      if (result.containsKey(problemId)) {
        if (status!=SolutionStatus.OK && status!=SolutionStatus.DISQUALIFIED && status!=SolutionStatus.PLAGIARISM_DETECTED) {
          result[problemId] = status;
        }
      } else {
        result[problemId] = status;
      }
    }
    return CheckCourseStatusResponse(
      problemStatuses: result.entries.map((e) => ProblemStatus(
          problemId: e.key, status: e.value
      ))
    );
  }

  @override
  Future<SubmissionsCountLimit> checkSubmissionsCountLimit(ServiceCall call, CheckSubmissionsLimitRequest request) async {
    int courseId = request.course.id.toInt();
    int userId = request.user.id.toInt();
    String problemId = request.problemId;
    // min time = current time - one hour
    int minTime = DateTime.now().subtract(Duration(hours: 1)).toUtc().millisecondsSinceEpoch ~/ 1000;
    List<dynamic> rows = await connection.query(
      '''
      select timestamp 
      from submissions 
      where users_id=@users_id and courses_id=@courses_id and problem_id=@problem_id and timestamp>=@timestamp 
      order by timestamp
      ''',
      substitutionValues: {
        'users_id': userId,
        'courses_id': courseId,
        'problem_id': problemId,
        'timestamp': minTime,
      }
    );
    int submissionsCount = 0;
    int earliestSubmission = 0;
    for (List<dynamic> fields in rows) {
      submissionsCount += 1;
      int currentSubmission = fields[0];
      if (currentSubmission>=minTime && (currentSubmission<=earliestSubmission || earliestSubmission==0)) {
        earliestSubmission = currentSubmission;
      }
    }
    CourseContentResponse courseContent = await parent.courseManagementService.getCoursePublicContent(
        call, CourseContentRequest(courseDataId: request.course.dataId)
    );
    int limit = courseContent.data.maxSubmissionsPerHour - submissionsCount;
    if (limit < 0) {
      limit = 0;
    }
    int nextTimeReset = earliestSubmission;
    if (nextTimeReset != 0) {
      nextTimeReset += 60 * 60;
    }
    return SubmissionsCountLimit(
      attemptsLeft: limit,
      nextTimeReset: Int64(nextTimeReset),
      serverTime: Int64(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000),
    );
  }

  @override
  Future<SubmissionList> getSubmissions(ServiceCall call, SubmissionFilter request) async {
    User currentUser = await parent.userManagementService.getUserFromContext(call);
    List<Enrollment> enrollments = await parent.courseManagementService.getUserEnrollments(currentUser);
    Enrollment? courseEnroll;
    for (Enrollment e in enrollments) {
      if (e.course.id == request.course.id) {
        courseEnroll = e;
        break;
      }
    }
    if (request.user.defaultRole != Role.ROLE_ADMINISTRATOR) {
      if (courseEnroll == null) {
        throw GrpcError.permissionDenied(
            'user ${request.user.id} not enrolled to ${request.course.id}');
      }
      if (courseEnroll.role == Role.ROLE_STUDENT &&
          request.user.id != currentUser.id) {
        throw GrpcError.permissionDenied('cant access not own submissions');
      }
    }
    Course course;
    if (courseEnroll != null) {
      course = courseEnroll.course;
    } else {
      course = request.course;
    }
    String query =
      '''
    select submissions.id, users_id, problem_id, timestamp, status,
       users.first_name, users.last_name, users.mid_name,
       users.group_name 
    from submissions, users
    where users_id=users.id 
      ''';
    List<String> conditions = List.empty(growable: true);
    Map<String,dynamic> queryArguments = Map();
    conditions.add('courses_id=@courses_id');
    queryArguments['courses_id'] = request.course.id.toInt();
    if (request.user.id != 0) {
      conditions.add('users_id=@users_id');
      queryArguments['users_id'] = request.user.id.toInt();
    }
    if (request.problemId.isNotEmpty) {
      conditions.add('problem_id=@problem_id');
      queryArguments['problem_id'] = request.problemId;
    }
    if (request.status != SolutionStatus.ANY_STATUS) {
      conditions.add('status=@status');
      queryArguments['status'] = request.status.value;
    }
    query += ' and ' + conditions.join(' and ');
    List<dynamic> rows = await connection.query(query, substitutionValues: queryArguments);
    List<Submission> result = [];
    for (List<dynamic> fields in rows) {
      int id = fields[0];
      int usersId = fields[1];
      String problemId = fields[2];
      int timestamp = fields[3];
      int problemStatus = fields[4];
      String firstName = fields[5];
      String lastName = fields[6];
      String? midName = fields[7];
      String? groupName = fields[8];
      User submittedUser = User(
        id: Int64(usersId),
        firstName: firstName,
        lastName: lastName,
        midName: midName!=null? midName : '',
        groupName: groupName!=null? groupName : '',
      );
      List<File> submissionFiles = await getSubmissionFiles(id);
      Submission submission = Submission(
        id: Int64(id),
        user: submittedUser,
        course: course,
        problemId: problemId,
        timestamp: Int64(timestamp),
        status: SolutionStatus.valueOf(problemStatus)!,
        solutionFiles: FileSet(files: submissionFiles),
      );
      result.add(submission);
    }
    return SubmissionList(submissions: result);
  }


  @override
  Future<Submission> submitProblemSolution(ServiceCall call, Submission request) async {
    User currentUser = await parent.userManagementService.getUserFromContext(call);
    List<Enrollment> enrollments = await parent.courseManagementService.getUserEnrollments(currentUser);
    Enrollment? courseEnroll;
    for (Enrollment e in enrollments) {
      if (e.course.id == request.course.id) {
        courseEnroll = e;
        break;
      }
    }
    if (courseEnroll==null && request.user.defaultRole != Role.ROLE_ADMINISTRATOR) {
      throw GrpcError.permissionDenied('user ${request.user.id} not enrolled to ${request.course.id}');
    }
    SubmissionsCountLimit limit = await checkSubmissionsCountLimit(
      call, CheckSubmissionsLimitRequest(
        user: currentUser,
        course: request.course,
        problemId: request.problemId,
      )
    );
    if (limit.attemptsLeft == 0) {
      throw GrpcError.resourceExhausted('submissions attempts left');
    }
    CourseData courseData = (await parent.courseManagementService.getCoursePublicContent(
      call, CourseContentRequest(courseDataId: request.course.dataId)
    )).data;
    int maxFileSize = courseData.maxSubmissionFileSize;
    for (File file in request.solutionFiles.files) {
      int fileSize = file.data.length;
      if (fileSize > maxFileSize) {
        throw GrpcError.resourceExhausted('max file size limit exceeded');
      }
    }
    List<dynamic> submissionsRows = await connection.query(
      '''
      insert into submissions(users_id,courses_id,problem_id,status,timestamp)
      values (@users_id,@courses_id,@problem_id,@status,@timestamp)
      returning id
      ''',
      substitutionValues: {
        'users_id': currentUser.id.toInt(),
        'courses_id': request.course.id.toInt(),
        'problem_id': request.problemId,
        'status': SolutionStatus.SUBMITTED.value,
        'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      }
    );
    int submissionId = submissionsRows[0][0];
    for (File file in request.solutionFiles.files) {
      await connection.query(
        '''
        insert into submission_files(file_name,submissions_id,content)
        values (@file_name,@submissions_id,@content)
        ''',
        substitutionValues: {
          'file_name': file.name,
          'submissions_id': submissionId,
          'content': utf8.decode(file.data),
        }
      );
    }
    return Submission(id: Int64(submissionId));
  }

  void assignGrader(int submissionId, String graderName) {
    connection.query('''
      update submissions
      set status=@status, grader_name=@grader_name
      where id=@id
      ''',
      substitutionValues: {
        'id': submissionId,
        'status': SolutionStatus.GRADER_ASSIGNED.value,
        'grader_name': graderName,
      }
    );
  }

  void unassignGrader(String graderName) {
    connection.query('''
      update submissions
      set status=@new_status, grader_name=null
      where status=@assigned_status and grader_name=@grader_name
      ''',
        substitutionValues: {
          'assigned_status': SolutionStatus.GRADER_ASSIGNED.value,
          'new_status': SolutionStatus.SUBMITTED.value,
          'grader_name': graderName,
        }
    );
  }

  @override
  Future<Submission> updateGraderOutput(ServiceCall? call, Submission request) async {
    log.info('got response from grader ${request.graderName} on ${request.id}: status = ${request.status.name}');
    await connection.transaction((connection) async {
      await connection.query(
        '''
        update submissions set status=@status, grader_name=@grader_name 
        where id=@id
        ''',
        substitutionValues: {
          'status': request.status.value,
          'grader_name': request.graderName,
          'id': request.id.toInt(),
        }
      );
      for (TestResult test in request.testResult) {
        connection.query(
          '''
insert into submission_results(
                               submissions_id,
                               test_number,
                               stdout,
                               stderr,
                               status,
                               standard_match,
                               killed_by_timer,
                               signal_killed,
                               valgrind_errors,
                               valgrind_output
)
values (@submissions_id,@test_number,@stdout,@stderr,
        @status,@standard_match,@killed_by_timer,
        @signal_killed,@valgrind_errors,@valgrind_output)          
          ''',
          substitutionValues: {
            'submissions_id': request.id.toInt(),
            'test_number': test.testNumber,
            'stdout': test.stdout,
            'stderr': test.stderr,
            'status': test.status,
            'standard_match': test.standardMatch,
            'killed_by_timer': test.killedByTimer,
            'signal_killed': test.signalKilled,
            'valgrind_errors': test.valgrindErrors,
            'valgrind_output': test.valgrindOutput,
          }
        );
      }
    });
    return request;
  }

  Future<List<File>> getSubmissionFiles(int submissionId) async {
    List<dynamic> rows = await connection.query(
      'select file_name, content from submission_files where submissions_id=@id',
      substitutionValues: {'id': submissionId}
    );
    Iterable<File> result = rows.map((e) {
      List<dynamic> fields = e;
      String fileName = fields[0];
      String content = fields[1];
      return File(name: fileName, data: utf8.encode(content));
    });
    return List.from(result);
  }

  Future<List<Submission>> getSubmissionsToGrade() async {
    List<dynamic> rows = await connection.query(
      '''
      select submissions.id, users_id, courses_id, problem_id, course_data 
      from submissions, courses
      where status=@status and courses_id=courses.id
      order by timestamp
      ''',
      substitutionValues: {'status': SolutionStatus.SUBMITTED.value}
    );
    List<Submission> result = [];
    for (final e in rows) {
      List<dynamic> fields = e;
      int id = fields[0];
      int usersId = fields[1];
      int coursesId = fields[2];
      String problemId = fields[3];
      String courseData = fields[4];
      List<File> files = await getSubmissionFiles(id);
      result.add(Submission(
        id: Int64(id),
        user: User(id: Int64(usersId)),
        course: Course(id: Int64(coursesId), dataId: courseData),
        problemId: problemId,
        solutionFiles: FileSet(files: files),
      ));
    };
    return result;
  }

  Future<List<Submission>> getUnfinishedSubmissionToGrade(String graderName) async {
    List<dynamic> rows = await connection.query(
        '''
      select submissions.id, users_id, courses_id, problem_id, course_data 
      from submissions, courses
      where status=@status and grader_name=@grader_name and courses_id=courses.id
      order by timestamp
      limit 1
      ''',
        substitutionValues: {
          'status': SolutionStatus.GRADER_ASSIGNED.value,
          'grader_name': graderName,
        }
    );
    List<Submission> result = [];
    for (final e in rows) {
      List<dynamic> fields = e;
      int id = fields[0];
      int usersId = fields[1];
      int coursesId = fields[2];
      String problemId = fields[3];
      String courseData = fields[4];
      List<File> files = await getSubmissionFiles(id);
      result.add(Submission(
        id: Int64(id),
        user: User(id: Int64(usersId)),
        course: Course(id: Int64(coursesId), dataId: courseData),
        problemId: problemId,
        solutionFiles: FileSet(files: files),
      ));
    }
    return result;
  }

  @override
  Future<Submission> takeSubmissionToGrade(ServiceCall call, GraderProperties request) async {
    List<Submission> unfinished = await getUnfinishedSubmissionToGrade(request.name);
    if (unfinished.isNotEmpty) {
      Submission submission = unfinished.first;
      log.info('submission ${submission.id} sent to grader ${request.name}');
      return submission;
    }
    List<Submission> newSubmissions = await getSubmissionsToGrade();
    for (Submission submission in newSubmissions) {
      ProblemData problemData = await getProblemDataForSubmission(submission);
      if (graderMatch(request, problemData.gradingOptions)) {
        assignGrader(submission.id.toInt(), request.name);
        log.info('submission ${submission.id} assigned and sent to grader ${request.name}');
        return submission;
      }
    }
    return Submission(id: Int64(0));
  }

  bool graderMatch(GraderProperties grader, GradingOptions options) {
    return grader.platform.arch == options.platformRequired.arch ||
      options.platformRequired.arch == Arch.ARCH_ANY;
  }

  Future<ProblemData> getProblemDataForSubmission(Submission sub) async {
    String courseDataId;
    if (sub.course.dataId.isEmpty) {
      List<dynamic> rows = await parent.connection.query(
          'select course_data from courses where id=@id',
          substitutionValues: {'id': sub.course.id.toInt()}
      );
      courseDataId = rows[0][0];
    } else {
      courseDataId = sub.course.dataId;
    }
    final request = ProblemContentRequest(
      courseDataId: courseDataId,
      problemId: sub.problemId,
    );
    final response = await parent.courseManagementService.getProblemFullContent(null, request);
    return response.data;
  }

}
