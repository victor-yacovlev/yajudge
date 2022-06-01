import 'dart:async';
import 'dart:convert';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:fixnum/fixnum.dart';
import 'graders_manager.dart';
import 'master_service.dart';

class SubmissionListNotificationsEntry {
  final User user;
  final SubmissionListQuery query;
  final StreamController<SubmissionListEntry> controller;

  SubmissionListNotificationsEntry(this.user, this.query, this.controller);
}

class SubmissionManagementService extends SubmissionManagementServiceBase {

  final Logger log = Logger('SubmissionManager');
  final PostgreSQLConnection connection;
  final MasterService parent;

  final Map<String,List<StreamController<ProblemStatus>>> _problemStatusStreamControllers = {};
  final Map<String,List<StreamController<CourseStatus>>> _courseStatusStreamControllers = {};
  final Map<String,List<StreamController<Submission>>> _submissionResultStreamControllers = {};

  final Map<String,SubmissionListNotificationsEntry> _submissionListListeners = {};

  final GradersManager _gradersManager = GradersManager();

  SubmissionManagementService({
    required this.parent,
    required this.connection,
  })
  {
    Timer.periodic(Duration(seconds: 5), (_) { processSubmissionsQueue(); });
  }

  @override
  Future<CourseStatus> checkCourseStatus(ServiceCall call, CheckCourseStatusRequest request) async {
    final user = request.user;
    final course = request.course;
    return _getCourseStatus(user, course);
  }

  Future<CourseStatus> _getCourseStatus(User user, Course course) async {
    final courseDataId = course.dataId;
    final courseData = parent.courseManagementService.getCourseData(courseDataId);
    double courseScoreGot = 0.0;
    double courseScoreMax = 0.0;
    bool courseCompleted = true;
    int problemsTotal = 0;
    int problemsRequired = 0;
    int problemsSolved = 0;
    int problemsRequiredSolved = 0;

    List<SectionStatus> sectionStatuses = [];
    for (final section in courseData.sections) {
      double sectionScoreGot = 0.0;
      double sectionScoreMax = 0.0;
      bool sectionCompleted = true;
      bool lessonCompleted = true;
      bool lessonBlocked = false;

      List<LessonStatus> lessonStatuses = [];
      for (final lesson in section.lessons) {
        double lessonScoreGot = 0.0;
        double lessonScoreMax = 0.0;
        lessonBlocked = !lessonCompleted;

        List<ProblemStatus> problemStatuses = [];
        for (final problemMetadata in lesson.problemsMetadata) {
          problemsTotal ++;
          if (problemMetadata.blocksNextProblems) {
            problemsRequired ++;
          }

          final problemStatus = await _getProblemStatus(
              user: user,
              course: course,
              problemMetadata: problemMetadata,
              problemBlocked: !lessonCompleted,
          );

          if (problemStatus.completed) {
            problemsSolved ++;
            if (problemMetadata.blocksNextProblems) {
              problemsRequiredSolved ++;
            }
          }

          lessonScoreGot += problemStatus.scoreGot;
          lessonScoreMax += problemStatus.scoreMax;
          sectionScoreGot += problemStatus.scoreGot;
          sectionScoreMax += problemStatus.scoreMax;
          courseScoreGot += problemStatus.scoreGot;
          courseScoreMax += problemStatus.scoreMax;

          if (problemMetadata.blocksNextProblems && !problemStatus.completed) {
            lessonCompleted = false;
            sectionCompleted = false;
            courseCompleted = false;
          }

          problemStatuses.add(problemStatus);
        }

        lessonStatuses.add(LessonStatus(
          lessonId: lesson.id,
          completed: lessonCompleted,
          blocksNext: !lessonCompleted,
          blockedByPrevious: lessonBlocked,
          scoreGot: lessonScoreGot,
          scoreMax: lessonScoreMax,
          problems: problemStatuses,
        ));

      }

      sectionStatuses.add(SectionStatus(
        sectionId: section.id,
        completed: sectionCompleted,
        blocksNext: false, // TODO add course-specific parameter
        scoreGot: sectionScoreGot,
        scoreMax: sectionScoreMax,
        lessons: lessonStatuses,
      ));

    }

    return CourseStatus(
      course: course,
      user: user,
      scoreGot: courseScoreGot,
      scoreMax: courseScoreMax,
      sections: sectionStatuses,
      problemsRequired: problemsRequired,
      problemsSolved: problemsSolved,
      problemsTotal: problemsTotal,
      problemsRequiredSolved: problemsRequiredSolved,
    );
  }

  Future<ProblemStatus> _getProblemStatus({
    required User user,
    required Course course,
    required ProblemMetadata problemMetadata,
    bool problemBlocked = false,
    bool withSubmissions = false,
  }) async {

    final usersId = user.id.toInt();
    final coursesId = course.id.toInt();

    List<dynamic> rows = [];

    try {
      rows = await connection.query(
          '''
      select id,status,timestamp from submissions
      where users_id=@users_id and courses_id=@courses_id and problem_id=@problem_id
      order by id asc 
      ''',
          substitutionValues: {
            'users_id': usersId,
            'courses_id': coursesId,
            'problem_id': problemMetadata.id,
          }
      );
    } catch (error) {
      log.severe('sql query at checkCourseStatus: $error');
    }

    final finalStatuses = [SolutionStatus.OK, SolutionStatus.DISQUALIFIED];
    List<Submission> submissions = [];
    SolutionStatus problemStatus = SolutionStatus.ANY_STATUS_OR_NULL;
    bool completed = false;
    double scoreGot = 0.0;
    Int64 submitted = Int64(0);
    for (List<dynamic> fields in rows) {
      int id = fields[0];
      SolutionStatus status = SolutionStatus.valueOf(fields[1])!;
      Int64 timestamp = Int64(fields[2]);
      if (finalStatuses.contains(status)) {
        problemStatus = status;
        submitted = timestamp;
      }
      if (status == SolutionStatus.OK) {
        scoreGot = problemMetadata.fullScoreMultiplier * 100;
        completed = true;
      }
      if (withSubmissions) {
        submissions.add(Submission(
          id: Int64(id),
          problemId: problemMetadata.id,
          status: status,
          user: user,
          course: course,
          timestamp: timestamp,
        ));
      }
    }

    final countLimit = await _submissionsCountLimit(user, course, problemMetadata.id);
    return ProblemStatus(
      problemId: problemMetadata.id,
      blockedByPrevious: problemBlocked,
      blocksNext: problemMetadata.blocksNextProblems,
      completed: completed,
      scoreMax: problemMetadata.fullScoreMultiplier * 100,
      scoreGot: scoreGot,
      finalSolutionStatus: problemStatus,
      submitted: submitted,
      submissionCountLimit: countLimit,
      submissions: submissions,
    );
  }

  @override
  Future<SubmissionsCountLimit> checkSubmissionsCountLimit(ServiceCall call, CheckSubmissionsLimitRequest request) async {
    return _submissionsCountLimit(request.user, request.course, request.problemId);
  }

  Future<SubmissionsCountLimit> _submissionsCountLimit(User user, Course course, String problemId) async {
    int courseId = course.id.toInt();
    int userId = user.id.toInt();

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
    final courseData = parent.courseManagementService.getCourseData(course.dataId);
    final problemData = findProblemById(courseData, problemId);
    int limit = problemData.maxSubmissionsPerHour>0 ? problemData.maxSubmissionsPerHour : courseData.maxSubmissionsPerHour;
    limit -= submissionsCount;
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
    await _checkAccessToCourse(call, request.user, request.course);
    return _getSubmissions(request.user, request.course, request.problemId, request.status);
  }

  Future<void> _checkAccessToCourse(ServiceCall call, User user, Course course) async {
    final currentUser = await parent.userManagementService.getUserFromContext(call);
    final enrollmentsService = parent.enrollmentManagementService;
    final enrollmentsResponse = await enrollmentsService.getUserEnrollments(call, currentUser);
    List<Enrollment> enrollments = enrollmentsResponse.enrollments;
    Enrollment? courseEnroll;
    for (Enrollment e in enrollments) {
      if (e.course.id == course.id) {
        courseEnroll = e;
        break;
      }
    }
    if (currentUser.defaultRole != Role.ROLE_ADMINISTRATOR) {
      if (courseEnroll == null) {
        throw GrpcError.permissionDenied(
            'user ${user.id} not enrolled to ${course.id}');
      }
      if (courseEnroll.role == Role.ROLE_STUDENT && user.id != currentUser.id) {
        throw GrpcError.permissionDenied('cant access not own submissions');
      }
    }
  }


  @override
  Future<SubmissionListResponse> getSubmissionList(ServiceCall call, SubmissionListQuery request) async {
    String queryBegin = '''
      select submissions.id, problem_id, timestamp, status,
        users.first_name, users.last_name, users.mid_name,
        users.group_name
      from submissions, users
      where users_id=users.id 
      ''';
    String queryEnd = ' order by timestamp desc ';
    String queryFilter = '';
    Map<String,dynamic> queryValues = {};
    if (request.limit > 0) {
      queryEnd += 'limit ${request.limit} ';
    }
    if (request.offset > 0) {
      queryEnd += 'offset ${request.offset} ';
    }
    if (request.submissionId > 0) {
      // return just one submission if exists
      queryFilter = ' and submissions.id=@id ';
      queryValues['id'] = request.submissionId.toInt();
    }
    else {
      // create a filter for submissions list
      if (request.showMineSubmissions == false) {
        final currentUser = await parent.userManagementService.getUserFromContext(call);
        queryFilter += ' and users.id!=@user_id ';
        queryValues['user_id'] = currentUser.id.toInt();
      }
      if (request.statusFilter != SolutionStatus.ANY_STATUS_OR_NULL) {
        queryFilter += ' and status=@status ';
        queryValues['status'] = request.statusFilter.value;
      }
      if (request.problemIdFilter.isNotEmpty) {
        queryFilter += ' and problem_id=@problem_id ';
        queryValues['problem_id'] = request.problemIdFilter;
      }
      if (request.nameQuery.trim().isNotEmpty) {
        queryFilter += ''' and (
          upper(users.first_name) like @name
          or
          upper(users.last_name) like @name
          or
          upper(concat(users.last_name, ' ', users.first_name)) like @name
          or
          upper(concat(users.first_name, ' ', users.last_name)) like @name
        )  
        ''';
        String normalizedName = request.nameQuery.trim().toUpperCase().replaceAll(r'\s+', ' ');
        queryValues['name'] = '$normalizedName%';
      }
    }
    final query = queryBegin + queryFilter + queryEnd;
    List<dynamic> queryRows = await connection.query(query, substitutionValues: queryValues);
    List<SubmissionListEntry> result = [];
    for (final row in queryRows) {
      int id = row[0];
      String problemId = row[1];
      int timestamp = row[2];
      int status = row[3];
      String firstName = row[4];
      String lastName = row[5];
      String midName = row[6] is String? row[6] : '';
      String groupName = row[7] is String? row[7] : '';
      result.add(SubmissionListEntry(
        submissionId: Int64(id),
        problemId: problemId,
        timestamp: Int64(timestamp),
        status: SolutionStatus.valueOf(status),
        sender: User(
          firstName: firstName,
          lastName: lastName,
          midName: midName,
          groupName: groupName,
        )
      ));
    }
    return SubmissionListResponse(entries: result);
  }

  Future<SubmissionList> _getSubmissions(User user, Course course, String problemId, SolutionStatus status) async {
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
    queryArguments['courses_id'] = course.id.toInt();
    if (user.id != 0) {
      conditions.add('users_id=@users_id');
      queryArguments['users_id'] = user.id.toInt();
    }
    if (problemId.isNotEmpty) {
      conditions.add('problem_id=@problem_id');
      queryArguments['problem_id'] = problemId;
    }
    if (status != SolutionStatus.ANY_STATUS_OR_NULL) {
      conditions.add('status=@status');
      queryArguments['status'] = status.value;
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
        midName: midName ?? '',
        groupName: groupName ?? '',
      );
      Submission submission = Submission(
        id: Int64(id),
        user: submittedUser,
        course: course,
        problemId: problemId,
        timestamp: Int64(timestamp),
        status: SolutionStatus.valueOf(problemStatus)!,
      );
      result.add(submission);
    }
    return SubmissionList(submissions: result);
  }

  @override
  Future<Submission> getSubmissionResult(ServiceCall call, Submission request) async {
    final currentUser = await parent.userManagementService.getUserFromContext(call);
    int submissionId = request.id.toInt();
    final query =
    '''
    select users_id, problem_id, timestamp, status, style_error_log, compile_error_log
    from submissions
    where id=@id order by id asc
      ''';
    final submissionRows = await connection.query(query, substitutionValues: {'id': submissionId});
    if (submissionRows.isEmpty) {
      throw GrpcError.notFound('no submission found: $submissionId');
    }
    final firstSubmissionRow = submissionRows.first;
    int userId = firstSubmissionRow[0];
    String problemId = firstSubmissionRow[1];
    int timestamp = firstSubmissionRow[2];
    SolutionStatus status = SolutionStatus.valueOf(firstSubmissionRow[3])!;
    String? styleErrorLog = firstSubmissionRow[4];
    String? compileErrorLog = firstSubmissionRow[5];
    if (styleErrorLog == null) {
      styleErrorLog = '';
    }
    if (compileErrorLog == null) {
      compileErrorLog = '';
    }

    final enrollmentsService = parent.enrollmentManagementService;
    final enrollmentsResponse = await enrollmentsService.getUserEnrollments(call, currentUser);
    final enrollments = enrollmentsResponse.enrollments;
    Enrollment? courseEnroll;
    for (Enrollment e in enrollments) {
      if (e.course.id == request.course.id) {
        courseEnroll = e;
        break;
      }
    }
    if (currentUser.defaultRole != Role.ROLE_ADMINISTRATOR) {
      bool noCourseEnroll = courseEnroll == null;
      bool userNotMatch = userId != currentUser.id.toInt();
      if (noCourseEnroll || courseEnroll.role==Role.ROLE_STUDENT && userNotMatch) {
        throw GrpcError.permissionDenied('cant access not own submissions');
      }
    }

    final solutionFiles = await getSubmissionFiles(submissionId);
    List<TestResult> testResults = [];
    final brokenStatuses = [
      SolutionStatus.RUNTIME_ERROR,
      SolutionStatus.TIME_LIMIT,
      SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.WRONG_ANSWER,
    ];
    if (brokenStatuses.contains(status)) {
      final allTestResults = await getSubmissionTestResults(status, submissionId);
      // find first broken test and send it only to save network traffic
      for (final test in allTestResults) {
        if (test.status == status) {
          testResults.add(test);
          break;
        }
      }
    }

    return Submission(
      id: Int64(submissionId),
      user: currentUser,
      timestamp: Int64(timestamp),
      status: status,
      problemId: problemId,
      solutionFiles: FileSet(files: solutionFiles),
      testResults: testResults,
      styleErrorLog: styleErrorLog,
      buildErrorLog: compileErrorLog,
    );
  }

  Future<List<TestResult>> getSubmissionTestResults(SolutionStatus solutionStatus, int submissionId) async {
    final haveTestsStatuses = [
      SolutionStatus.OK,
      SolutionStatus.WRONG_ANSWER,
      SolutionStatus.RUNTIME_ERROR,
      SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.TIME_LIMIT,
    ];
    if (!haveTestsStatuses.contains(solutionStatus)) {
      return [];
    }
    String query =
    '''
    select test_number, stdout, stderr, standard_match, signal_killed, 
      valgrind_errors, valgrind_output, killed_by_timer, checker_output,
      status, exit_status
    from submission_results
    where submissions_id=@id 
      ''';
    final testResultsRows = await connection.query(query, substitutionValues: {
      'id': submissionId,
    });
    List<TestResult> results = [];
    for (final row in testResultsRows) {
      int testNumber = row[0];
      String stdout = row[1];
      String stderr = row[2];
      bool standardMatch = row[3];
      int signalKilled = row[4];
      int valgrindErrors = row[5];
      String valgrindOutput = row[6];
      bool killedByTimer = row[7];
      String checkerOutput = row[8];
      int status = row[9];
      int exitStatus = row[10];
      results.add(TestResult(
        testNumber: testNumber,
        stdout: stdout,
        stderr: stderr,
        signalKilled: signalKilled,
        status: SolutionStatus.valueOf(status)!,
        killedByTimer: killedByTimer,
        valgrindErrors: valgrindErrors,
        valgrindOutput: valgrindOutput,
        exitStatus: exitStatus,
        standardMatch: standardMatch,
        checkerOutput: checkerOutput,
      ));
    }
    return results;
  }

  @override
  Future<Submission> submitProblemSolution(ServiceCall call, Submission request) async {
    final currentUser = await parent.userManagementService.getUserFromContext(call);
    final enrollmentsService = parent.enrollmentManagementService;
    final enrollmentsResponse = await enrollmentsService.getUserEnrollments(call, currentUser);
    final enrollments = enrollmentsResponse.enrollments;
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
    request.updateId(submissionId);
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
    _notifyProblemStatusChanged(currentUser, request.course, request.problemId, true);
    _notifySubmissionResultChanged(request);
    pushSubmissionToGrader(request);
    return Submission(id: Int64(submissionId));
  }

  void assignGrader(Submission submission, String graderName) {
    connection.query('''
      update submissions
      set status=@status, grader_name=@grader_name
      where id=@id
      ''',
      substitutionValues: {
        'id': submission.id.toInt(),
        'status': SolutionStatus.GRADER_ASSIGNED.value,
        'grader_name': graderName,
      }
    );
    _notifySubmissionResultChanged(
      submission.copyWith((s) {
        s.graderName = graderName;
        s.status = SolutionStatus.GRADER_ASSIGNED;
      })
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
      // modify submission itself
      await connection.query(
        '''
        update 
          submissions set status=@status, grader_name=@grader_name,
          style_error_log=@style_error_log, compile_error_log=@compile_error_log
        where id=@id
        ''',
        substitutionValues: {
          'status': request.status.value,
          'grader_name': request.graderName,
          'id': request.id.toInt(),
          'style_error_log': request.styleErrorLog,
          'compile_error_log': request.buildErrorLog,
        }
      );
      // there might be older test results in case of rejudging submission
      // so delete them if exists
      await connection.query(
        ''' 
        delete from submission_results where submissions_id=@id
        ''',
        substitutionValues: { 'id': request.id.toInt() }
      );
      // insert new test results
      for (TestResult test in request.testResults) {
        connection.query(
          '''
insert into submission_results(
                               submissions_id,
                               test_number,
                               stdout,
                               stderr,
                               status,
                               exit_status,
                               standard_match,
                               killed_by_timer,
                               signal_killed,
                               valgrind_errors,
                               valgrind_output,
                               checker_output
)
values (@submissions_id,@test_number,@stdout,@stderr,
        @status,@exit_status,@standard_match,@killed_by_timer,
        @signal_killed,
        @valgrind_errors,@valgrind_output,
        @checker_output)          
          ''',
          substitutionValues: {
            'submissions_id': request.id.toInt(),
            'test_number': test.testNumber,
            'stdout': test.stdout,
            'stderr': test.stderr,
            'status': test.status.value,
            'exit_status': test.exitStatus,
            'standard_match': test.standardMatch,
            'killed_by_timer': test.killedByTimer,
            'signal_killed': test.signalKilled,
            'valgrind_errors': test.valgrindErrors,
            'valgrind_output': test.valgrindOutput,
            'checker_output': test.checkerOutput,
          }
        );
      }
    });
    _notifyProblemStatusChanged(request.user, request.course, request.problemId, true);
    final notification = request.copyWith((s) {
      // clean unnecessary test results
      List<TestResult> testResults = [];
      final brokenStatuses = [
        SolutionStatus.RUNTIME_ERROR, SolutionStatus.VALGRIND_ERRORS,
        SolutionStatus.TIME_LIMIT, SolutionStatus.WRONG_ANSWER,
      ];
      if (brokenStatuses.contains(s.status)) {
        for (final test in s.testResults) {
          if (test.status == s.status) {
            testResults.add(test);
            break;
          }
        }
      }
      s.testResults.clear();
      s.testResults.addAll(testResults);
    });
    _notifySubmissionResultChanged(notification);
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
        assignGrader(submission, request.name);
        _notifyProblemStatusChanged(submission.user, submission.course, submission.problemId, true);
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
      int courseId = sub.course.id.toInt();
      List<dynamic> rows = await parent.connection.query(
          'select course_data from courses where id=@id',
          substitutionValues: {'id': courseId}
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

  @override
  Stream<ProblemStatus> subscribeToProblemStatusNotifications(ServiceCall call, ProblemStatusRequest request) {
    final key = '${request.user.id}/${request.course.id}/${request.problemId}';
    StreamController<ProblemStatus> controller = StreamController<ProblemStatus>();
    controller.onCancel = () {
      log.info('removing controller from problem status listeners with key $key');
      List<StreamController<ProblemStatus>> controllers;
      controllers = _problemStatusStreamControllers[key]!;
      controllers.remove(controller);
      if (controllers.isEmpty) {
        _problemStatusStreamControllers.remove(key);
      }
    };

    List<StreamController<ProblemStatus>> controllers;
    if (_problemStatusStreamControllers.containsKey(key)) {
      controllers = _problemStatusStreamControllers[key]!;
    }
    else {
      controllers = [];
      _problemStatusStreamControllers[key] = controllers;
    }
    controllers.add(controller);
    log.info('added problem notification controller for $key');

    // send empty message now and periodically to prevent NGINX to close
    // connection by timeout
    controller.add(ProblemStatus());
    Timer.periodic(Duration(seconds: 15), (timer) {
      bool active =
        _problemStatusStreamControllers.containsKey(key) &&
        _problemStatusStreamControllers[key]!.contains(controller);
      if (!active) {
        timer.cancel();
        return;
      }
      controller.add(ProblemStatus());
    });

    return controller.stream;
  }


  @override
  Stream<CourseStatus> subscribeToCourseStatusNotifications(ServiceCall call, CheckCourseStatusRequest request) {
    final key = '${request.user.id}/${request.course.id}';
    StreamController<CourseStatus> controller = StreamController<CourseStatus>();
    controller.onCancel = () {
      log.info('removing controller from course status listeners with key $key');
      List<StreamController<CourseStatus>> controllers;
      controllers = _courseStatusStreamControllers[key]!;
      controllers.remove(controller);
      if (controllers.isEmpty) {
        _courseStatusStreamControllers.remove(key);
      }
    };

    List<StreamController<CourseStatus>> controllers;
    if (_courseStatusStreamControllers.containsKey(key)) {
      controllers = _courseStatusStreamControllers[key]!;
    }
    else {
      controllers = [];
      _courseStatusStreamControllers[key] = controllers;
    }
    controllers.add(controller);
    log.info('added course notification controller for $key');

    // send empty message now and periodically to prevent NGINX to close
    // connection by timeout
    controller.add(CourseStatus());
    Timer.periodic(Duration(seconds: 15), (timer) {
      bool active =
          _courseStatusStreamControllers.containsKey(key) &&
              _courseStatusStreamControllers[key]!.contains(controller);
      if (!active) {
        timer.cancel();
        return;
      }
      controller.add(CourseStatus());
    });

    return controller.stream;
  }

  @override
  Future<ProblemStatus> checkProblemStatus(ServiceCall call, ProblemStatusRequest request) async {
    final courseData = parent.courseManagementService.getCourseData(request.course.dataId);
    final problemMetadata = findProblemMetadataById(courseData, request.problemId);
    final futureProblemStatus = _getProblemStatus(
      user: request.user,
      course: request.course,
      problemMetadata: problemMetadata,
      withSubmissions: true,
    );
    return futureProblemStatus;
  }

  void _notifySubmissionResultChanged(Submission submission) {

    // controllers related to problem views
    final key = '${submission.id}';
    List<StreamController<Submission>> problemViews = [];
    if (_submissionResultStreamControllers.containsKey(key)) {
      problemViews.addAll(_submissionResultStreamControllers[key]!);
    }
    for (final controller in problemViews) {
      controller.add(submission);
    }

    // controllers related to list views

    List<StreamController<SubmissionListEntry>> listViews = [];
    for (final watcher in _submissionListListeners.values) {
      final query = watcher.query;
      final user = watcher.user;
      if (query.match(submission, user)) {
        listViews.add(watcher.controller);
      }
    }
    for (final controller in listViews) {
      final listEntry = submission.asSubmissionListEntry();
      controller.add(listEntry);
    }

  }


  void _notifyProblemStatusChanged(User user, Course course, String problemId, bool withSubmissions) {
    final courseKey = '${user.id}/${course.id}';
    final problemKey = '${user.id}/${course.id}/$problemId';

    List<StreamController<CourseStatus>> courseControllers = [];
    List<StreamController<ProblemStatus>> problemControllers = [];

    if (_courseStatusStreamControllers.containsKey(courseKey)) {
      courseControllers = _courseStatusStreamControllers[courseKey]!;
    }
    if (_problemStatusStreamControllers.containsKey(problemKey)) {
      problemControllers = _problemStatusStreamControllers[problemKey]!;
    }

    if (problemControllers.isEmpty && courseControllers.isEmpty) {
      return;
    }

    final futureCourseStatus = _getCourseStatus(user, course);

    futureCourseStatus.then((CourseStatus status) {
      for (final controller in courseControllers) {
        controller.add(status);
      }
    });

    if (problemControllers.isEmpty) {
      return;
    }

    final courseData = parent.courseManagementService.getCourseData(course.dataId);
    final problemMetadata = findProblemMetadataById(courseData, problemId);

    final futureProblemStatus = _getProblemStatus(
      user: user,
      course: course,
      problemMetadata: problemMetadata,
      withSubmissions: withSubmissions,
    );

    futureProblemStatus.then((ProblemStatus status) {
      for (final controller in problemControllers) {
        controller.sink.add(status);
      }
    });
  }


  @override
  Future<RejudgeRequest> rejudge(ServiceCall call, RejudgeRequest request) async {
    final currentUser = await parent.userManagementService.getUserFromContext(call);
    final enrollmentsService = parent.enrollmentManagementService;
    final enrollmentsResponse = await enrollmentsService.getUserEnrollments(call, currentUser);
    final enrollments = enrollmentsResponse.enrollments;
    Enrollment? courseEnroll;
    for (Enrollment e in enrollments) {
      if (e.course.id == request.course.id) {
        courseEnroll = e;
        break;
      }
    }
    if (currentUser.defaultRole != Role.ROLE_ADMINISTRATOR) {
      if (courseEnroll == null) {
        throw GrpcError.permissionDenied(
            'user ${request.user.id} not enrolled to ${request.course.id}');
      }
      if (courseEnroll.role == Role.ROLE_STUDENT) {
        throw GrpcError.permissionDenied('only teachers can initiate rejudge');
      }
    }

    Future<void> rejudgeSubmission(Submission submission) async {
      await connection.query(
          'delete from submission_results where submissions_id=@id',
          substitutionValues: {
            'id': submission.id.toInt(),
          }
      );
      await connection.query(
          'update submissions set status=@new_status where id=@id',
          substitutionValues: {
            'new_status': SolutionStatus.SUBMITTED.value,
            'id': submission.id.toInt(),
          }
      );
      final rows = await connection.query(
          'select users_id, first_name, last_name, mid_name, timestamp, grader_name '
          'from submissions, users '
          'where submissions.id=@id and users.id=submissions.users_id',
          substitutionValues: {
            'id': submission.id.toInt(),
          }
      );
      final firstRow = rows.first;
      final userId = Int64(firstRow[0] as int);
      final firstName = (firstRow[1] as String?) ?? '';
      final lastName = (firstRow[2] as String?) ?? '';
      final midName = (firstRow[3] as String?) ?? '';
      final timestamp = Int64(firstRow[4] as int);
      final graderName = firstRow[5] as String;
      submission.user = User(id: userId, firstName: firstName, lastName: lastName, midName: midName);
      submission.status = SolutionStatus.SUBMITTED;
      submission.styleErrorLog = submission.buildErrorLog = '';
      submission.testResults.clear();
      submission.graderScore = 0.0;
      submission.graderName = graderName;
      submission.timestamp = timestamp;
      _notifySubmissionResultChanged(submission);
    }

    if (request.submission.id != 0) {
      // rejudge only just one submission
      await rejudgeSubmission(request.submission.deepCopy());
    }
    else if (request.course.id>0 && request.problemId.isNotEmpty) {
      // rejudge all problem submissions within course
      String query = 'select id from submissions where courses_id=@courses_id and problem_id=@problem_id';
      if (request.onlyFailedSubmissions) {
        query += ' and status<>${SolutionStatus.OK.value}';
        query += ' and status<>${SolutionStatus.DISQUALIFIED.value}';
        query += ' and status<>${SolutionStatus.CODE_REVIEW_REJECTED.value}';
        query += ' and status<>${SolutionStatus.PENDING_REVIEW.value}';
        query += ' and status<>${SolutionStatus.ACCEPTABLE.value}';
      }
      final rows = await connection.query(
        query,
        substitutionValues: {
          'new_status': SolutionStatus.SUBMITTED.value,
          'courses_id': request.course.id.toInt(),
          'problem_id': request.problemId,
        }
      );
      final submissions = <Submission>[];
      for (final row in rows) {
        final submissionId = row[0] as int;
        submissions.add(Submission(id: Int64(submissionId), problemId: request.problemId).deepCopy());
      }
      for (final submission in submissions) {
        await rejudgeSubmission(submission);
      }
    }
    return request;
  }

  @override
  Stream<Submission> subscribeToSubmissionResultNotifications(ServiceCall call, Submission submission) {
    final key = '${submission.id}';
    StreamController<Submission> controller = StreamController<Submission>();
    controller.onCancel = () {
      log.info('removing controller from submission status listeners with key $key');
      List<StreamController<Submission>> controllers;
      controllers = _submissionResultStreamControllers[key]!;
      controllers.remove(controller);
      if (controllers.isEmpty) {
        _submissionResultStreamControllers.remove(key);
      }
    };

    List<StreamController<Submission>> controllers;
    if (_submissionResultStreamControllers.containsKey(key)) {
      controllers = _submissionResultStreamControllers[key]!;
    }
    else {
      controllers = [];
      _submissionResultStreamControllers[key] = controllers;
    }
    controllers.add(controller);
    log.info('added submission notification controller for $key');

    // send empty message now and periodically to prevent NGINX to close
    // connection by timeout
    controller.add(Submission());
    Timer.periodic(Duration(seconds: 30), (timer) {
      bool active =
          _submissionResultStreamControllers.containsKey(key) &&
              _submissionResultStreamControllers[key]!.contains(controller);
      if (!active) {
        timer.cancel();
        return;
      }
      controller.add(Submission());
    });

    return controller.stream;
  }

  @override
  Stream<Submission> receiveSubmissionsToGrade(ServiceCall call, GraderProperties request) {
    final streamController = _gradersManager.registerNewGrader(call, request);

    // check for unfinished submission processing by this grader and reassign them again
    unassignGrader(request.name);

    // force process queue of stored submissions
    processSubmissionsQueue();

    return streamController.stream;
  }

  Future<bool> pushSubmissionToGrader(Submission submission) async {
    final problemData = await getProblemDataForSubmission(submission);
    final platformRequired = problemData.gradingOptions.platformRequired;
    final graderConnection = _gradersManager.findGrader(platformRequired);
    bool result = false;
    if (graderConnection!=null) {
      if (graderConnection.pushSubmission(submission)) {
        assignGrader(submission, graderConnection.properties.name);
        _notifyProblemStatusChanged(submission.user, submission.course, submission.problemId, true);
        log.info('submission ${submission.id} assigned and sent to grader ${graderConnection.properties.name}');
        result = true;
      }
    }
    return result;
  }

  void processSubmissionsQueue() async {
    if (!_gradersManager.hasGraders) {
      return;
    }
    final queue = await getSubmissionsToGrade();
    for (final submission in queue) {
      await pushSubmissionToGrader(submission);
    }
  }

  @override
  Future<Empty> setGraderStatus(ServiceCall call, GraderStatusMessage request) async {
    _gradersManager.setGraderStatus(request.properties.name, request.status);
    return Empty();
  }

  @override
  Stream<SubmissionListEntry> subscribeToSubmissionListNotifications(ServiceCall call, SubmissionListQuery request) {
    final key = call.session;
    if (_submissionListListeners.containsKey(key)) {
      _submissionListListeners[key]!.controller.close();
    }

    final controller = StreamController<SubmissionListEntry>();

    parent.userManagementService.getUserBySession(Session(cookie: call.session))
    .then((user) {
      final entry = SubmissionListNotificationsEntry(user, request, controller);
      _submissionListListeners[key] = entry;
    });

    controller.onCancel = () {
      if (_submissionListListeners.containsKey(key)) {
        _submissionListListeners.remove(key);
      }
    };

    return controller.stream;
  }




}
