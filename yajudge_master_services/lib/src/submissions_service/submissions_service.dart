import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:fixnum/fixnum.dart';
import '../service_call_extension.dart';
import 'external_services_manager.dart';
import '../course_data_consumer.dart';
import '../last_seen_tracker.dart';

const graderPushInterval = Duration(seconds: 1);

class SubmissionListNotificationsEntry {
  final User user;
  final SubmissionListNotificationsRequest request;
  final StreamController<SubmissionListEntry> controller;

  SubmissionListNotificationsEntry(this.user, this.request, this.controller);
}

class SubmissionManagementService extends SubmissionManagementServiceBase
    with CourseDataConsumer, LastSeenTracker {

  final Logger log = Logger('SubmissionManager');
  final PostgreSQLConnection connection;
  final CourseManagementClient courseManager;
  final UserManagementClient userManager;
  final DeadlinesManagementClient deadlinesManager;
  final ProgressCalculatorClient progressNotifier;
  final String secretKey;

  final Map<String,List<StreamController<Submission>>> _submissionResultStreamControllers = {};

  final Map<String,SubmissionListNotificationsEntry> _submissionListListeners = {};

  final ExternalServicesManager _gradersManager = ExternalServicesManager();

  SubmissionManagementService({
    required this.connection,
    required this.courseManager,
    required this.userManager,
    required this.deadlinesManager,
    required this.progressNotifier,
    required CourseContentProviderClient courseContentProvider,
    required this.secretKey,
  }) : super()
  {
    super.contentProvider = courseContentProvider;
    Timer.periodic(graderPushInterval, (_) {
      try {
        processSubmissionsQueue();
      }
      catch (e) {
        log.severe('cant process submissions queue: $e');
      }
    });
  }


  @override
  Future<SubmissionList> getSubmissions(ServiceCall call, SubmissionFilter request) async {
    await _checkAccessToCourse(call, request.user, request.course);
    final submissions = await _getSubmissions(request.user, request.course, request.problemId, request.status);
    return SubmissionList(submissions: submissions);
  }

  Future<void> _checkAccessToCourse(ServiceCall call, User user, Course course) async {
    final currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('no user information in request call');
    }
    final enrollmentsResponse = await courseManager.getUserEnrollments(currentUser);
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
    final currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('must be logged in user to get submissions list');
    }
    String countQueryBegin = '''
      select count(submissions.id)
      from submissions, users, submission_deadlines
      where users_id=users.id and submissions.id=submission_deadlines.submissions_id
    ''';
    String dataQueryBegin = '''
      select submissions.id, problem_id, datetime, status,
        users.first_name, users.last_name, users.mid_name,
        users.group_name, grading_status
      from submissions, users, submission_deadlines
      where users_id=users.id and submissions.id=submission_deadlines.submissions_id 
      ''';
    String queryEnd = ' order by datetime desc ';
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
        queryFilter += ' and users.id!=@user_id ';
        queryValues['user_id'] = currentUser.id.toInt();
      }
      if (request.courseId > 0) {
        queryFilter += ' and submissions.courses_id=@course_id ';
        queryValues['course_id'] = request.courseId.toInt();
      }
      if (!{SolutionStatus.ANY_STATUS_OR_NULL, SolutionStatus.HARD_DEADLINE_PASSED}.contains(request.statusFilter)) {
        queryFilter += ' and status=@status ';
        queryValues['status'] = request.statusFilter.value;
      }
      if (request.statusFilter == SolutionStatus.HARD_DEADLINE_PASSED) {
        queryFilter += ' and datetime>hard ';
      }
      else if (request.statusFilter != SolutionStatus.ANY_STATUS_OR_NULL) {
        queryFilter += ' and (hard<=\'1971-01-01\' or datetime<=hard) ';
      }
      if (request.problemIdFilter.isNotEmpty) {
        queryFilter += ' and problem_id=@problem_id ';
        queryValues['problem_id'] = request.problemIdFilter;
      }
      if (request.nameQuery.trim().isNotEmpty) {
        final userId = int.tryParse(request.nameQuery);
        if (userId != null) {
          queryFilter += ' and users.id=@user_id ';
          queryValues['user_id'] = userId;
        }
        else {
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
          String normalizedName = request.nameQuery.trim()
              .toUpperCase()
              .replaceAll(r'\s+', ' ');
          queryValues['name'] = '$normalizedName%';
        }
      }
    }
    final countQuery = countQueryBegin + queryFilter;
    final dataQuery = dataQueryBegin + queryFilter + queryEnd;
    final countQueryRows = await connection.query(countQuery, substitutionValues: queryValues);
    final countRow = countQueryRows.single;
    final countValue = countRow.single as int;
    final dataQueryRows = await connection.query(dataQuery, substitutionValues: queryValues);
    List<SubmissionListEntry> result = [];
    for (final row in dataQueryRows) {
      int id = row[0];
      String problemId = row[1];
      DateTime dateTime = row[2];
      int status = row[3];
      String firstName = row[4];
      String lastName = row[5];
      String midName = row[6] is String? row[6] : '';
      String groupName = row[7] is String? row[7] : '';
      final gradingStatus = SubmissionProcessStatus.valueOf(row[8])!;
      final sender = User(
        firstName: firstName,
        lastName: lastName,
        midName: midName,
        groupName: groupName,
      );
      final submission = Submission(
        id: Int64(id),
        problemId: problemId,
        datetime: Int64(dateTime.millisecondsSinceEpoch ~/ 1000),
        status: SolutionStatus.valueOf(status),
        gradingStatus: gradingStatus,
        user: sender,
      );
      final deadlines = await deadlinesManager.getSubmissionDeadlines(submission);
      final hardDeadline = deadlines.hardDeadline;
      bool hardDeadlinePassed = false;
      if (hardDeadline > 0) {
        hardDeadlinePassed = submission.datetime > hardDeadline;
      }
      result.add(SubmissionListEntry(
        submissionId: submission.id,
        problemId: submission.problemId,
        datetime: submission.datetime,
        status: submission.status,
        gradingStatus: submission.gradingStatus,
        sender: submission.user,
        hardDeadlinePassed: hardDeadlinePassed,
      ));
    }

    return SubmissionListResponse(
      entries: result,
      query: request,
      totalCount: countValue,
    );
  }

  Future<List<Submission>> _getSubmissions(User user, Course course, String problemId, SolutionStatus status) async {
    String query =
      '''
    select submissions.id, users_id, problem_id, datetime, status,
       users.first_name, users.last_name, users.mid_name,
       users.group_name 
    from submissions, users
    where users_id=users.id 
      ''';
    List<String> conditions = List.empty(growable: true);
    Map<String,dynamic> queryArguments = {};
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
    query += ' and ${conditions.join(' and ')}';
    List<dynamic> rows = await connection.query(query, substitutionValues: queryArguments);
    List<Submission> result = [];
    for (List<dynamic> fields in rows) {
      int id = fields[0];
      int usersId = fields[1];
      String problemId = fields[2];
      DateTime dateTime = fields[3];
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
        datetime: Int64(dateTime.millisecondsSinceEpoch ~/ 1000),
        status: SolutionStatus.valueOf(problemStatus)!,
      );
      result.add(submission);
    }
    return result;
  }

  Future<Submission> getSubmissionInfo(ServiceCall call, Submission request) async {
    User? currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('no user information in service call');
    }
    currentUser = await userManager.getProfileById(currentUser,
      options: CallOptions(metadata: call.clientMetadata),
    );
    final submissionId = request.id.toInt();
    final query =
    '''
    select users_id, problem_id, datetime, status, style_error_log, compile_error_log, grading_status
    from submissions
    where id=@id
      ''';
    final submissionRows = await connection.query(query, substitutionValues: {'id': submissionId});
    if (submissionRows.isEmpty) {
      throw GrpcError.notFound('no submission found: $submissionId');
    }
    final firstSubmissionRow = submissionRows.first;
    int userId = firstSubmissionRow[0];
    String problemId = firstSubmissionRow[1];
    DateTime dateTime = firstSubmissionRow[2];
    final status = SolutionStatus.valueOf(firstSubmissionRow[3])!;
    String? styleErrorLog = firstSubmissionRow[4];
    String? compileErrorLog = firstSubmissionRow[5];
    final gradingStatus = SubmissionProcessStatus.valueOf(firstSubmissionRow[6])!;
    styleErrorLog ??= '';
    compileErrorLog ??= '';

    final enrollmentsResponse = await courseManager.getUserEnrollments(currentUser);
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

    final deadlines = await deadlinesManager.getSubmissionDeadlines(Submission(id: Int64(submissionId)));

    final submission = Submission(
      id: Int64(submissionId),
      user: User(id: Int64(userId)),
      datetime: Int64(dateTime.millisecondsSinceEpoch ~/ 1000),
      status: status,
      gradingStatus: gradingStatus,
      problemId: problemId,
      styleErrorLog: styleErrorLog,
      buildErrorLog: compileErrorLog,
      course: request.course,
      hardDeadline: deadlines.hardDeadline,
      softDeadline: deadlines.softDeadline,
    );

    return submission;
  }

  @override
  Future<Submission> getSubmissionResult(ServiceCall call, Submission request) async {
    final submissionId = request.id.toInt();
    final submission = await getSubmissionInfo(call, request);

    final solutionFiles = await getSubmissionFiles(submissionId);
    submission.solutionFiles = FileSet(files: solutionFiles);

    List<TestResult> testResults = [];
    final brokenStatuses = [
      SolutionStatus.RUNTIME_ERROR,
      SolutionStatus.TIME_LIMIT,
      SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.WRONG_ANSWER,
    ];
    if (brokenStatuses.contains(submission.status)) {
      final allTestResults = await getSubmissionTestResults(submission.status, request);
      // find first broken test and send it only to save network traffic
      for (final test in allTestResults) {
        if (test.status == submission.status) {
          testResults.add(test);
          break;
        }
      }
    }

    submission.testResults.addAll(testResults);

    return submission;
  }

  Future<List<TestResult>> getSubmissionResultsFromSQL(Submission submission) async {
    final query = '''
      select submission_protobuf_gzipped_base64 
      from submission_results 
      where id=@id
      ''';
    final queryValues = { 'id': submission.id.toInt() };
    final rows = await connection.query(query, substitutionValues: queryValues);
    if (rows.isEmpty) {
      return [];
    }
    try {
      final singleRow = rows.single;
      final singleValue = singleRow.single;
      final submissionProtobufGzippedBase64 = singleValue as String?;
      if (submissionProtobufGzippedBase64 == null) {
        return [];
      }
      final submissionProtobufGzipped = base64Decode(submissionProtobufGzippedBase64);
      final submissionProtobuf = io.gzip.decode(submissionProtobufGzipped);
      submission = Submission.fromBuffer(submissionProtobuf);
    }
    catch (e) {
      log.severe('cant get submission results dump from SQL: $e');
      return [];
    }
    return submission.testResults;
  }

  Future<List<TestResult>> getSubmissionTestResults(SolutionStatus solutionStatus, Submission submission) async {
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
    return getSubmissionResultsFromSQL(submission);
  }

  @override
  Future<Submission> submitProblemSolution(ServiceCall call, Submission request) async {
    User? currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('no user data in call request while trying to submit solution');
    }
    currentUser = await userManager.getProfileById(currentUser,
      options: CallOptions(metadata: call.clientMetadata),
    );
    final enrollmentsResponse = await courseManager.getUserEnrollments(currentUser);
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
    List<dynamic> submissionsRows = await connection.query(
      '''
      insert into submissions(users_id,courses_id,problem_id,status,datetime,grading_status)
      values (@users_id,@courses_id,@problem_id,@status,@datetime,@grading_status)
      returning id
      ''',
      substitutionValues: {
        'users_id': currentUser.id.toInt(),
        'courses_id': request.course.id.toInt(),
        'problem_id': request.problemId,
        'status': SolutionStatus.ANY_STATUS_OR_NULL.value,
        'grading_status': SubmissionProcessStatus.PROCESS_QUEUED.value,
        'datetime': DateTime.now().toUtc(),
      }
    );
    int submissionId = submissionsRows[0][0];
    request.updateId(submissionId);
    await deadlinesManager.insertNewSubmission(request);
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
    try {
      progressNotifier.notifyProblemStatusChanged(request);
    }
    catch (e) {
      log.warning('cant notify progress service about submission ${request.id}: $e');
    }
    await _notifySubmissionResultChanged(request);
    await pushSubmissionToGrader(request);
    return Submission(id: Int64(submissionId));
  }

  Future assignGrader(Submission submission, String graderName) async {
    await connection.query('''
      update submissions
      set grading_status=@grading_status, grader_name=@grader_name
      where id=@id
      ''',
      substitutionValues: {
        'id': submission.id.toInt(),
        'grading_status': SubmissionProcessStatus.PROCESS_ASSIGNED.value,
        'grader_name': graderName,
      }
    );
    final assignedSubmission = submission.deepCopy();
    assignedSubmission.graderName = graderName;
    assignedSubmission.gradingStatus = SubmissionProcessStatus.PROCESS_ASSIGNED;
    await _notifySubmissionResultChanged(assignedSubmission);
  }

  void unassignGrader(String graderName) {
    connection.query('''
      update submissions
      set grading_status=@new_status, grader_name=null
      where grading_status=@assigned_status and grader_name=@grader_name
      ''',
        substitutionValues: {
          'assigned_status': SubmissionProcessStatus.PROCESS_ASSIGNED.value,
          'new_status': SubmissionProcessStatus.PROCESS_QUEUED.value,
          'grader_name': graderName,
        }
    );
  }

  @override
  Future<Submission> updateSubmissionStatus(ServiceCall? call, Submission request) async {
    log.info('manual submission ${request.id} status update: ${request.status.value} (${request.status.name})');
    final query = '''
    update submissions set status=@status where id=@id
    ''';
    await connection.query(query, substitutionValues: {
      'status': request.status.value,
      'id': request.id.toInt(),
    });
    // TODO make notifications
    return request;
  }


  Future insertSubmissionResultsIntoSQL(Submission submission) async {
    final submissionProtobuf = submission.writeToBuffer();
    final submissionProtobufGzipped = io.gzip.encode(submissionProtobuf);
    final submissionProtobufGzippedBase64 = base64Encode(submissionProtobufGzipped);
    await connection.query(
        '''
insert into submission_results(id,submission_protobuf_gzipped_base64)
values (@id,@data)
        ''',
        substitutionValues: {
          'id': submission.id.toInt(),
          'data': submissionProtobufGzippedBase64,
        }
    );
  }
  
  Future deleteSubmissionResultsFromSQL(Submission submission) {
    return connection.execute(
      'delete from submission_results where id=@id',
      substitutionValues: { 'id': submission.id.toInt()}
    );
  }


  @override
  Future<Submission> updateGraderOutput(ServiceCall? call, Submission request) async {
    log.info('got response from grader ${request.graderName} on ${request.id}: status = ${request.status.name}');
    request = request.deepCopy();
    request.gradingStatus = SubmissionProcessStatus.PROCESS_DONE;
    final submissionResultsDeleter = deleteSubmissionResultsFromSQL;
    final submissionResultsInserter = insertSubmissionResultsIntoSQL;
    if (request.status == SolutionStatus.OK) {
      final course = await courseManager.getCourse(request.course);
      final courseData = await getCourseData(call, course);
      final problemId = request.problemId;
      final problemMetadata = courseData.findProblemMetadataById(problemId);
      bool skipCodeReview = course.disableReview || problemMetadata.skipCodeReview;
      if (!skipCodeReview) {
        request.status = SolutionStatus.PENDING_REVIEW;
        // do not change submission status in case of review processed
        final oldStatusRows = await connection.query(
          'select status from submissions where id=@id',
          substitutionValues: { 'id': request.id.toInt() },
        );
        if (oldStatusRows.isNotEmpty) {
          final oldStatusRow = oldStatusRows.first;
          final oldStatusValue = oldStatusRow.first as int;
          final oldStatus = SolutionStatus.valueOf(oldStatusValue)!;
          const statusesNotToChange = {
            SolutionStatus.OK, SolutionStatus.SUMMON_FOR_DEFENCE,
            SolutionStatus.DISQUALIFIED, SolutionStatus.CODE_REVIEW_REJECTED,
          };
          if (statusesNotToChange.contains(oldStatus)) {
            request.status = oldStatus;
          }
        }
      }
    }

    final query = '''
        update 
          submissions set status=@status, grader_name=@grader_name,
          style_error_log=@style_error_log, compile_error_log=@compile_error_log,
          grading_status=@grading_status
        where id=@id
        ''';
    final queryValues = {
      'status': request.status.value,
      'grader_name': request.graderName,
      'id': request.id.toInt(),
      'style_error_log': request.styleErrorLog,
      'compile_error_log': request.buildErrorLog,
      'grading_status': SubmissionProcessStatus.PROCESS_DONE.value,
    };

    try {
      await connection.query(query, substitutionValues: queryValues);
    } catch (e) {
      log.severe('error updating result from grader: $e');
      return request;
    }

    // there might be older test results in case of rejudging submission
    // so delete them if exists
    await submissionResultsDeleter(request);

    // insert new test results
    await submissionResultsInserter(request);

    try {
      progressNotifier.notifyProblemStatusChanged(request);
    }
    catch (e) {
      log.warning('cant notify progress service about submission ${request.id}: $e');
    }
    // clean unnecessary test results
    const brokenStatuses = [
      SolutionStatus.RUNTIME_ERROR, SolutionStatus.VALGRIND_ERRORS,
      SolutionStatus.TIME_LIMIT, SolutionStatus.WRONG_ANSWER,
    ];
    List<TestResult> testResults = [];
    if (brokenStatuses.contains(request.status)) {
      for (final test in request.testResults) {
        if (test.status == request.status) {
          testResults.add(test);
          break;
        }
      }
    }
    request.testResults.clear();
    request.testResults.addAll(testResults);
    await _notifySubmissionResultChanged(request);
    log.fine('successfully updated submission ${request.id} from grader');
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
      where grading_status=@grading_status and courses_id=courses.id
      order by datetime
      ''',
      substitutionValues: {'grading_status': SubmissionProcessStatus.PROCESS_QUEUED.value}
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
        course: Course(id: coursesId, dataId: courseData),
        problemId: problemId,
        solutionFiles: FileSet(files: files),
      ));
    }
    return result;
  }

  Future<List<Submission>> getUnfinishedSubmissionToGrade(String graderName) async {
    List<dynamic> rows = await connection.query(
      '''
      select submissions.id, users_id, courses_id, problem_id, course_data 
      from submissions, courses
      where grading_status=@grading_status and grader_name=@grader_name and courses_id=courses.id
      order by datetime
      limit 1
      ''',
        substitutionValues: {
          'grading_status': SubmissionProcessStatus.PROCESS_ASSIGNED.value,
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
        course: Course(id: coursesId, dataId: courseData),
        problemId: problemId,
        solutionFiles: FileSet(files: files),
      ));
    }
    return result;
  }

  @override
  Future<Submission> takeSubmissionToGrade(ServiceCall call, ConnectedServiceProperties request) async {
    List<Submission> unfinished = await getUnfinishedSubmissionToGrade(request.name);
    if (unfinished.isNotEmpty) {
      Submission submission = unfinished.first;
      log.info('submission ${submission.id} sent to grader ${request.name}');
      return submission;
    }
    List<Submission> newSubmissions = await getSubmissionsToGrade();
    for (Submission submission in newSubmissions) {
      ProblemData problemData = await getProblemDataForSubmission(call, submission);
      if (graderMatch(request, problemData.gradingOptions)) {
        assignGrader(submission, request.name);
        try {
          progressNotifier.notifyProblemStatusChanged(submission);
        }
        catch (e) {
          log.warning('cant notify progress service about submission ${submission.id}: $e');
        }
        log.info('submission ${submission.id} assigned and sent to grader ${request.name}');
        return submission;
      }
    }
    return Submission(id: Int64(0));
  }

  bool graderMatch(ConnectedServiceProperties grader, GradingOptions options) {
    return grader.platform.arch == options.platformRequired.arch ||
      options.platformRequired.arch == Arch.ARCH_ANY;
  }

  Future<ProblemData> getProblemDataForSubmission(ServiceCall? call, Submission sub) async {
    final course = await courseManager.getCourse(sub.course,
      options: CallOptions(metadata: call?.clientMetadata),
    );
    final request = ProblemContentRequest(
      courseDataId: course.dataId,
      problemId: sub.problemId,
    );
    final response = await contentProvider.getProblemFullContent(request,
      options: CallOptions(metadata: call?.clientMetadata),
    );
    return response.data;
  }

  Future _notifySubmissionResultChanged(Submission submission) async {

    final deadlines = await deadlinesManager.getSubmissionDeadlines(submission);
    submission = submission.deepCopy();
    submission.softDeadline = deadlines.softDeadline;
    submission.hardDeadline = deadlines.hardDeadline;

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
      final request = watcher.request;
      final user = watcher.user;
      if (request.match(submission, user)) {
        listViews.add(watcher.controller);
      }
    }
    for (final controller in listViews) {
      final listEntry = submission.asSubmissionListEntry();
      bool hardDeadlinePassed = false;
      if (submission.hardDeadline > 0) {
        hardDeadlinePassed = submission.hardDeadline < submission.datetime;
      }
      listEntry.hardDeadlinePassed = hardDeadlinePassed;
      controller.add(listEntry);
      final id = listEntry.submissionId.toInt();
      final status = listEntry.status.name;
      final grading = listEntry.gradingStatus.name;
      final logEntry = '{ id: $id, status: $status, grading: $grading }';
      log.fine('sent list notification entry $logEntry');
    }

  }



  @override
  Future<RejudgeRequest> rejudge(ServiceCall call, RejudgeRequest request) async {
    final currentUser = call.getSessionUser(secretKey);
    if (currentUser == null) {
      throw GrpcError.unauthenticated('requires user metadata in request to rejudge');
    }
    final enrollmentsResponse = await courseManager.getUserEnrollments(currentUser);
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
      final submissionResultsDeleter = deleteSubmissionResultsFromSQL;
      await submissionResultsDeleter(submission);

      await connection.query(
          'update submissions set grading_status=@new_status where id=@id',
          substitutionValues: {
            'new_status': SubmissionProcessStatus.PROCESS_QUEUED.value,
            'id': submission.id.toInt(),
          }
      );
      final rows = await connection.query(
          'select users_id, first_name, last_name, mid_name, datetime, grader_name, status '
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
      final datetime = firstRow[4] as DateTime;
      final graderName = firstRow[5] as String;
      final status = firstRow[6] as int;
      submission.user = User(id: userId, firstName: firstName, lastName: lastName, midName: midName);
      submission.status = SolutionStatus.valueOf(status)!;
      submission.gradingStatus = SubmissionProcessStatus.PROCESS_QUEUED;
      submission.styleErrorLog = submission.buildErrorLog = '';
      submission.testResults.clear();
      submission.graderScore = 0.0;
      submission.graderName = graderName;
      submission.datetime = Int64(datetime.millisecondsSinceEpoch ~/ 1000);
      await _notifySubmissionResultChanged(submission);
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
        query += ' and status<>${SolutionStatus.SUMMON_FOR_DEFENCE.value}';
      }
      final rows = await connection.query(
        query,
        substitutionValues: {
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
    final response = request.deepCopy();
    response.submission = request.submission.deepCopy();
    response.submission.gradingStatus = SubmissionProcessStatus.PROCESS_QUEUED;
    return response;
  }

  @override
  Stream<Submission> subscribeToSubmissionResultNotifications(ServiceCall call, Submission request) {
    final key = '${request.id}';
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
  Stream<Submission> receiveSubmissionsToProcess(ServiceCall call, ConnectedServiceProperties request) {
    final streamController = _gradersManager.registerNewService(call, request);

    // check for unfinished submission processing by this grader and reassign them again
    unassignGrader(request.name);

    // force process queue of stored submissions
    try {
      processSubmissionsQueue();
    }
    catch (e) {
      log.severe('cant process submissions queue: $e');
    }

    return streamController.stream;
  }

  Future<bool> pushSubmissionToGrader(Submission submission) async {
    ProblemData problemData;
    try {
      problemData = await getProblemDataForSubmission(null, submission);
    }
    catch (e) {
      log.severe('cant get problem data for ${submission.problemId} while pushing to grader');
      return false;
    }
    final platformRequired = problemData.gradingOptions.platformRequired;
    final graderConnection = _gradersManager.findService(ServiceRole.SERVICE_GRADING, platformRequired);
    bool result = false;
    if (graderConnection!=null) {
      if (graderConnection.pushSubmission(submission)) {
        assignGrader(submission, graderConnection.properties.name);
        try {
          progressNotifier.notifyProblemStatusChanged(submission);
        }
        catch (e) {
          log.warning('cant notify progress service about submission ${submission.id}: $e');
        }
        log.info('submission ${submission
            .id} assigned and sent to grader ${graderConnection.properties
            .name}');
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
      try {
        await pushSubmissionToGrader(submission);
      }
      catch (e) {
        log.severe('error pushing submission ${submission.id} to grader: $e');
      }
    }
  }

  @override
  Future<Empty> setExternalServiceStatus(ServiceCall call, ConnectedServiceStatus request) async {
    _gradersManager.setServiceStatus(request.properties.role, request.properties.name, request.status, request.capacity);
    return Empty();
  }

  @override
  Stream<SubmissionListEntry> subscribeToSubmissionListNotifications(ServiceCall call, SubmissionListNotificationsRequest request) async* {
    final key = call.session;
    final currentUser = call.getSessionUser(secretKey);
    if (key.isEmpty || currentUser==null) {
      throw GrpcError.unauthenticated('requires session and user in call request');
    }

    Future cancelExistingSubscription() async {
      if (_submissionListListeners.containsKey(key)) {
        final entry = _submissionListListeners[key]!;
        _submissionListListeners.remove(key);
        final existingController = entry.controller;
        if (!existingController.isClosed) {
          await existingController.close();
        }
        log.fine('canceled and forgot list notification subscription for client $key');
      }
    }

    await cancelExistingSubscription();

    final controller = StreamController<SubmissionListEntry>();
    final listener = SubmissionListNotificationsEntry(currentUser, request, controller);
    _submissionListListeners[key] = listener;

    const maxInactivityTime = Duration(minutes: 15);

    Timer.periodic(Duration(seconds: 5), (timer) {
      final lastSeen = lastSeenForSession(call);
      final now = DateTime.now();
      final deadline = lastSeen.add(maxInactivityTime);
      if (now.isAfter(deadline)) {
        timer.cancel();
        cancelExistingSubscription();
      }
    });

    final submissionsList = request.submissionIds;
    int minId = 0;
    int maxId = 0;
    for (final id in submissionsList) {
      if (id.toInt() > maxId) {
        maxId = id.toInt();
      }
      if (id.toInt() < minId || minId == 0) {
        minId = id.toInt();
      }
    }
    if (minId > 0 && maxId > 0) {
      log.fine(
          'subscribed to list [$minId...$maxId] notification by client $key'
      );
    }
    else {
      log.fine(
          'subscribed to list notification by client $key'
      );
    }

    yield* controller.stream;

  }

  @override
  Future<DiffViewResponse> getSubmissionsToDiff(ServiceCall call, DiffViewRequest request) async {
    final firstSource = request.first;
    final secondSource = request.second;
    request = request.deepCopy();
    if (firstSource.hasExternal() || secondSource.hasExternal()) {
      throw UnimplementedError();
    }
    final firstSubmission = await getSubmissionInfo(call, firstSource.submission);
    firstSubmission.user = await userManager.getProfileById(firstSubmission.user,
      options: CallOptions(metadata: call.clientMetadata)
    );
    request.first.submission = firstSubmission;
    final firstFiles = FileSet(
        files: await getSubmissionFiles(firstSubmission.id.toInt())
    );
    final secondSubmission = await getSubmissionInfo(call, secondSource.submission);
    secondSubmission.user = await userManager.getProfileById(secondSubmission.user,
      options: CallOptions(metadata: call.clientMetadata)
    );
    request.second.submission = secondSubmission;
    final secondFiles = FileSet(
        files: await getSubmissionFiles(secondSubmission.id.toInt())
    );
    final tempDirPath = '${io.Directory.systemTemp.path}/yajudge-master-${io.pid}/diffview';
    final firstDirPath = '$tempDirPath/submission${firstSubmission.id}';
    final secondDirPath = '$tempDirPath/submission${secondSubmission.id}';
    io.Directory(firstDirPath).createSync(recursive: true);
    io.Directory(secondDirPath).createSync(recursive: true);
    const diffOptions = <String>[];
    final result = <DiffData>[];
    for (final firstFile in firstFiles.files) {
      final secondFile = secondFiles.get(firstFile.name);
      if (secondFile.name != firstFile.name) {
        continue;
      }
      final firstFilePath = '$firstDirPath/${firstFile.name}';
      final secondFilePath = '$secondDirPath/${secondFile.name}';
      io.File(firstFilePath).writeAsBytesSync(firstFile.data, flush: true);
      io.File(secondFilePath).writeAsBytesSync(secondFile.data, flush: true);
      final diffArguments = diffOptions + [firstFilePath, secondFilePath];
      final diffCommandResult = io.Process.runSync(
          'diff', diffArguments,
          stdoutEncoding: Encoding.getByName('utf-8')
      );
      final diffOutput = diffCommandResult.stdout as String;
      final firstText = utf8.decode(firstFile.data, allowMalformed: true);
      final secondText = utf8.decode(secondFile.data, allowMalformed: true);
      final diffOperations = _parseDiffOutput(diffOutput);
      final diffData = DiffData(
        fileName: firstFile.name,
        firstText: firstText,
        secondText: secondText,
        operations: diffOperations,
      );
      result.add(diffData);
    }
    io.Directory(tempDirPath).deleteSync(recursive: true);
    return DiffViewResponse(diffs: result, request: request);
  }

  List<DiffOperation> _parseDiffOutput(String diffOutput) {

    DiffOperationType parseDiffOperation(String text) {
      switch (text) {
        case 'a': return DiffOperationType.LINE_INSERTED;
        case 'd': return DiffOperationType.LINE_DELETED;
        case 'c': return DiffOperationType.LINE_DIFFER;
        default: return DiffOperationType.LINE_EQUAL;
      }
    }

    LineRange parseLineRange(String text) {
      if (text.contains(',')) {
        final parts = text.split(',');
        int start = int.parse(parts[0]);
        int end = int.parse(parts[1]);
        return LineRange(start: start, end: end);
      }
      else {
        int single = int.parse(text);
        return LineRange(start: single, end: single);
      }
    }

    final diffLines = diffOutput.split('\n');
    final result = <DiffOperation>[];
    int currentLineIndex = 0;
    final rxDiffHeader = RegExp(r'(\d+,?\d*)([acd])(\d+,?\d*)');
    while (currentLineIndex < diffLines.length) {
      final line = diffLines[currentLineIndex];
      if (!rxDiffHeader.hasMatch(line)) {
        currentLineIndex ++;
        continue;
      }
      final match = rxDiffHeader.matchAsPrefix(line)!;
      final rangeFirstText = match.group(1)!;
      final rangeSecondText = match.group(3)!;
      final opText = match.group(2)!;
      final rangeFirst = parseLineRange(rangeFirstText);
      final rangeSecond = parseLineRange(rangeSecondText);
      final operationType = parseDiffOperation(opText);
      final operation = DiffOperation(from: rangeFirst, to: rangeSecond, operation: operationType);
      result.add(operation);
      switch (operationType) {
        case DiffOperationType.LINE_INSERTED:
          currentLineIndex += rangeSecond.length + 1;
          break;
        case DiffOperationType.LINE_DELETED:
          currentLineIndex += rangeFirst.length + 1;
          break;
        case DiffOperationType.LINE_DIFFER:
          currentLineIndex += rangeFirst.length + 1 + rangeSecond.length + 1;
          break;
        default:
          currentLineIndex ++;
      }
    }
    return result;
  }

}
