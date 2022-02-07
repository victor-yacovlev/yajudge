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
  Future<CourseStatus> checkCourseStatus(ServiceCall call, CheckCourseStatusRequest request) async {
    final user = request.user;
    final course = request.course;
    final courseDataId = course.dataId;

    final usersId = user.id.toInt();
    final coursesId = course.id.toInt();

    Map<String,SolutionStatus> statuses = {};
    Map<String,Int64> timestamps = {};

    List<dynamic> rows = [];

    try {
      rows = await connection.query(
          '''
      select problem_id,status,timestamp from submissions
      where users_id=@users_id and courses_id=@courses_id
      order by timestamp 
      ''',
          substitutionValues: {
            'users_id': usersId,
            'courses_id': coursesId,
          }
      );
    } catch (error) {
      log.severe('sql query at checkCourseStatus: $error');
    }

    final finalStatuses = [SolutionStatus.OK, SolutionStatus.DISQUALIFIED];
    for (List<dynamic> fields in rows) {
      String problemId = fields[0];
      SolutionStatus status = SolutionStatus.valueOf(fields[1])!;
      Int64 timestamp = Int64(fields[2]);
      if (statuses.containsKey(problemId)) {
        statuses[problemId] = status;
        final previousStatus = statuses[problemId];
        if (!finalStatuses.contains(previousStatus)) {
          statuses[problemId] = status;
          timestamps[problemId] = timestamp;
        }
      } else {
        statuses[problemId] = status;
      }
    }
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
      bool sectionBlocked = !courseCompleted;
      bool sectionCompleted = true;

      List<LessonStatus> lessonStatuses = [];
      for (final lesson in section.lessons) {
        double lessonScoreGot = 0.0;
        double lessonScoreMax = 0.0;
        bool lessonBlocked = !sectionCompleted;
        bool lessonCompleted = true;

        List<ProblemStatus> problemStatuses = [];
        for (final problemMetadata in lesson.problemsMetadata) {
          problemsTotal ++;
          if (problemMetadata.blocksNextProblems) {
            problemsRequired ++;
          }
          final problemId = problemMetadata.id;
          bool problemCompleted;
          bool problemBlocked = !lessonCompleted;
          double problemScoreGot = 0.0;
          double problemScoreMax = 100.0 * problemMetadata.fullScoreMultiplier;
          Int64 problemSubmitted = Int64(0);
          SolutionStatus lastSolutionStatus = SolutionStatus.ANY_STATUS_OR_NULL;
          if (statuses.containsKey(problemMetadata.id)) {
            final problemStatus = statuses[problemId];
            if (timestamps.containsKey(problemId)) {
              problemSubmitted = timestamps[problemId]!;
            }
            lastSolutionStatus = problemStatus!;
            problemCompleted = problemStatus==SolutionStatus.OK;
            if (problemCompleted) {
              // TODO check for deadlines
              problemScoreGot = problemScoreMax;
              problemsSolved ++;
              if (problemMetadata.blocksNextProblems) {
                problemsRequiredSolved ++;
              }
            }
          }
          else {
            problemCompleted = false;
          }

          lessonScoreGot += problemScoreGot;
          lessonScoreMax += problemScoreMax;
          sectionScoreGot += problemScoreGot;
          sectionScoreMax += problemScoreMax;
          courseScoreGot += problemScoreGot;
          courseScoreMax += problemScoreMax;
          if (problemMetadata.blocksNextProblems && !problemCompleted) {
            lessonCompleted = false;
            sectionCompleted = false;
            courseCompleted = false;
          }

          problemStatuses.add(ProblemStatus(
            problemId: problemId,
            scoreGot: problemScoreGot,
            scoreMax: problemScoreMax,
            blockedByPrevious: problemBlocked,
            blocksNext: problemMetadata.blocksNextProblems,
            completed: problemCompleted,
            submitted: problemSubmitted,
            lastSolutionStatus: lastSolutionStatus,
          ));
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
    if (request.status != SolutionStatus.ANY_STATUS_OR_NULL) {
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
                               valgrind_output,
                               checker_output
)
values (@submissions_id,@test_number,@stdout,@stderr,
        @status,@standard_match,@killed_by_timer,
        @signal_killed,
        @valgrind_errors,@valgrind_output,
        @checker_output)          
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
            'checker_output': test.checkerOutput,
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
