import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:postgres/postgres.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import '../course_data_consumer.dart';
import '../services_connector.dart';

typedef ProblemStatusController = StreamController<ProblemStatus>;
typedef CourseStatusController = StreamController<CourseStatus>;

class ProgressCalculatorService extends ProgressCalculatorServiceBase with CourseDataConsumer {

  final log = Logger('ProgressCalculator');
  final PostgreSQLConnection connection;
  final ServicesConnector services;

  final _problemStatusControllers = <String,List<ProblemStatusController>>{};
  final _courseStatusControllers = <String,List<CourseStatusController>>{};

  ProgressCalculatorService({
    required this.connection,
    required this.services,
  }) : super() {
    super.courseDataConsumerServices = services;
  }

  @override
  Future<CourseProgressResponse> getProgress(ServiceCall call, CourseProgressRequest request) async {
    AllGroupsEnrollments enrollment;
    if (services.courses == null) {
      final message = 'courses service offline while GetProgress';
      log.severe(message);
      throw GrpcError.unavailable(message);
    }
    try {
      enrollment = await services.courses!.getAllGroupsEnrollments(
        request.course,
        options: CallOptions(metadata: call.clientMetadata),
      );
    }
    catch (e) {
      log.severe('cant get all group enrollment: $e');
      rethrow;
    }
    List<User> enrolledUsers = [];
    for (final group in enrollment.groups) {
      enrolledUsers.addAll(group.groupStudents);
      enrolledUsers.addAll(group.foreignStudents);
    }
    List<CourseStatus> statuses = [];
    for (final user in enrolledUsers) {
      if (request.nameFilter.isNotEmpty) {
        final filter = request.nameFilter.trim().toUpperCase();
        bool test1 = user.lastName.toUpperCase().contains(filter);
        bool test2 = user.firstName.toUpperCase().contains(filter);
        bool test3 = ('${user.firstName} ${user.lastName}').toUpperCase().contains(filter);
        bool test4 = ('${user.lastName} ${user.firstName}').toUpperCase().contains(filter);
        bool test5 = user.groupName.toUpperCase().contains(filter);
        bool matched = test1 || test2 || test3 || test4 || test5;
        if (!matched) {
          continue;
        }
      }
      final statusRequest = CheckCourseStatusRequest(user: user, course: request.course);
      final statusResponse = await checkCourseStatus(call, statusRequest);
      statuses.add(statusResponse);
    }
    int statusComparator(CourseStatus a, CourseStatus b) {
      if (a.user.groupName == b.user.groupName) {
        if (a.user.lastName == b.user.lastName) {
          if (a.user.firstName == b.user.firstName) {
            return a.user.midName.compareTo(b.user.midName);
          }
          else {
            return a.user.firstName.compareTo(b.user.firstName);
          }
        }
        else {
          return a.user.lastName.compareTo(b.user.lastName);
        }
      }
      else {
        return a.user.groupName.compareTo(b.user.groupName);
      }
    }
    statuses.sort(statusComparator);
    List<ProblemData> problems = [];
    if (request.includeProblemDetails) {
      final courseData = await getCourseData(call, request.course);
      for (final section in courseData.sections) {
        for (final lesson in section.lessons) {
          problems.addAll(lesson.problems);
        }
      }
    }
    List<CourseStatusEntry> entries = [];
    for (final status in statuses) {
      double scoreGot = status.scoreGot;
      double scoreMax = status.scoreMax;
      bool courseCompleted = status.completed;
      List<ProblemStatus> problemStatuses = [];
      if (request.includeProblemDetails) {
        for (final section in status.sections) {
          for (final lesson in section.lessons) {
            problemStatuses.addAll(lesson.problems);
          }
        }
      }
      final entry = CourseStatusEntry(
        user: status.user,
        scoreGot: scoreGot,
        scoreMax: scoreMax,
        courseCompleted: courseCompleted,
        statuses: problemStatuses,
      );
      entries.add(entry);
    }
    return CourseProgressResponse(entries: entries, problems: problems);
  }

  @override
  Stream<ProblemStatus> subscribeToProblemStatusNotifications(ServiceCall call, ProblemStatusRequest request) {
    final key = '${request.user.id}/${request.course.id}/${request.problemId}';
    StreamController<ProblemStatus> controller = StreamController<ProblemStatus>();
    controller.onCancel = () {
      log.info('removing controller from problem status listeners with key $key');
      List<StreamController<ProblemStatus>> controllers;
      controllers = _problemStatusControllers[key]!;
      controllers.remove(controller);
      if (controllers.isEmpty) {
        _problemStatusControllers.remove(key);
      }
    };

    List<StreamController<ProblemStatus>> controllers;
    if (_problemStatusControllers.containsKey(key)) {
      controllers = _problemStatusControllers[key]!;
    }
    else {
      controllers = [];
      _problemStatusControllers[key] = controllers;
    }
    controllers.add(controller);
    log.info('added problem notification controller for $key');

    // send empty message now and periodically to prevent NGINX to close
    // connection by timeout
    controller.add(ProblemStatus());
    Timer.periodic(Duration(seconds: 15), (timer) {
      bool active =
          _problemStatusControllers.containsKey(key) &&
              _problemStatusControllers[key]!.contains(controller);
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
    final controller = StreamController<CourseStatus>();
    controller.onCancel = () {
      log.info('removing controller from course status listeners with key $key');
      final controllers = _courseStatusControllers[key]!;
      controllers.remove(controller);
      if (controllers.isEmpty) {
        _courseStatusControllers.remove(key);
      }
    };

    final controllers = _courseStatusControllers[key] ?? [];
    _courseStatusControllers[key] = controllers;

    controllers.add(controller);
    log.info('added course notification controller for $key');

    // send empty message now and periodically to prevent NGINX to close
    // connection by timeout
    controller.add(CourseStatus());
    Timer.periodic(Duration(seconds: 15), (timer) {
      bool active =
          _courseStatusControllers.containsKey(key) &&
              _courseStatusControllers[key]!.contains(controller);
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

    final courseData = await getCourseData(call, request.course);
    final problemMetadata = courseData.findProblemMetadataById(request.problemId);
    final futureProblemStatus = _getProblemStatus(call,
      user: request.user,
      course: request.course,
      problemMetadata: problemMetadata,
      withSubmissions: true,
    );
    return futureProblemStatus;
  }

  @override
  Future<CourseStatus> checkCourseStatus(ServiceCall call, CheckCourseStatusRequest request) async {
    final user = request.user;
    final course = request.course;
    return _getCourseStatus(call, user, course);
  }

  Future<CourseStatus> _getCourseStatus(ServiceCall call, User user, Course course) async {
    final courseData = await getCourseData(call, course);
    double courseScoreGot = 0.0;
    double courseScoreMax = 0.0;
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
          final problemStatus = await _getProblemStatus(call,
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

          const allowGoNextStatuses = [
            SolutionStatus.PENDING_REVIEW, SolutionStatus.SUMMON_FOR_DEFENCE,
            SolutionStatus.DISQUALIFIED, SolutionStatus.CODE_REVIEW_REJECTED,
          ];

          bool allowGoToNextProblem = problemStatus.completed ||
              allowGoNextStatuses.contains(problemStatus.finalSolutionStatus);

          if (problemMetadata.blocksNextProblems && !allowGoToNextProblem) {
            lessonCompleted = false;
            sectionCompleted = false;
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

  Future<ProblemStatus> _getProblemStatus(ServiceCall? call, {
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
      select id,status,datetime,grading_status from submissions
      where users_id=@users_id and courses_id=@courses_id and problem_id=@problem_id
      order by datetime asc 
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

    const finalStatuses = [
      SolutionStatus.OK,
      SolutionStatus.DISQUALIFIED,
      SolutionStatus.PENDING_REVIEW,
      SolutionStatus.CODE_REVIEW_REJECTED,
      SolutionStatus.SUMMON_FOR_DEFENCE,
    ];
    Submission? finalSubmission;
    List<Submission> submissions = [];
    var problemStatus = SolutionStatus.ANY_STATUS_OR_NULL;
    var gradingStatus = SubmissionProcessStatus.PROCESS_DONE;
    final maxProblemScore = (problemMetadata.fullScoreMultiplier * 100).round();
    bool completed = false;
    int scoreGot = 0;
    for (List<dynamic> fields in rows) {
      int id = fields[0];
      final status = SolutionStatus.valueOf(fields[1])!;
      final datetime = fields[2] as DateTime;
      gradingStatus = SubmissionProcessStatus.valueOf(fields[3])!;
      if (finalStatuses.contains(status)) {
        problemStatus = status;
        finalSubmission = Submission(
          id: Int64(id),
          course: course,
          problemId: problemMetadata.id,
          user: user,
          datetime: Int64(datetime.millisecondsSinceEpoch ~/ 1000),
        );
      }
      if (status == SolutionStatus.OK) {
        scoreGot = maxProblemScore;
        completed = true;
      }
      if (withSubmissions) {
        submissions.add(Submission(
          id: Int64(id),
          problemId: problemMetadata.id,
          status: status,
          gradingStatus: gradingStatus,
          user: user,
          course: course,
          datetime: Int64(datetime.millisecondsSinceEpoch ~/ 1000),
        ));
      }
    }

    int deadlinePenalty = 0;
    bool hardDeadlinePassed = false;
    int softDeadline = 0;
    int hardDeadline = 0;

    if (finalSubmission != null) {
      if (services.deadlines == null) {
        final message = 'deadline service offline while GetProblemStatus';
        log.severe(message);
        throw GrpcError.unavailable(message);
      }
      final deadlines = await services.deadlines!.getSubmissionDeadlines(finalSubmission);
      softDeadline = deadlines.softDeadline.toInt();
      hardDeadline = deadlines.hardDeadline.toInt();
    }

    if (softDeadline > 0) {
      int secondsOverdue = finalSubmission!.datetime.toInt() - softDeadline;
      int hoursOverdue = secondsOverdue ~/ 60 ~/ 60;
      deadlinePenalty = hoursOverdue * problemMetadata.deadlines.softPenalty;
      if (deadlinePenalty < 0) {
        deadlinePenalty = 0;
      }
      scoreGot -= deadlinePenalty;
    }

    if (hardDeadline > 0) {
      hardDeadlinePassed = finalSubmission!.datetime.toInt() > hardDeadline;
    }

    if (scoreGot < 0) {
      scoreGot = 0;
    }

    final countLimit = await _submissionsCountLimit(call, user, course, problemMetadata.id);

    return ProblemStatus(
      problemId: problemMetadata.id,
      blockedByPrevious: problemBlocked,
      blocksNext: problemMetadata.blocksNextProblems,
      completed: completed,
      scoreMax: maxProblemScore,
      scoreGot: scoreGot,
      finalSolutionStatus: hardDeadlinePassed? SolutionStatus.HARD_DEADLINE_PASSED : problemStatus,
      finalGradingStatus: gradingStatus,
      submitted: finalSubmission==null? Int64() : finalSubmission.datetime,
      submissionCountLimit: countLimit,
      submissions: submissions,
      deadlinePenaltyTotal: deadlinePenalty,
    );
  }

  @override
  Future<SubmissionsCountLimit> getSubmissionCountLimit(ServiceCall call, Submission request) async {
    return _submissionsCountLimit(call, request.user, request.course, request.problemId);
  }

  Future<SubmissionsCountLimit> _submissionsCountLimit(ServiceCall? call, User user, Course course, String problemId) async {
    int courseId = course.id.toInt();
    int userId = user.id.toInt();

    // min time = current time - one hour
    DateTime minDateTime = DateTime.now().subtract(Duration(hours: 1)).toUtc();
    List<dynamic> rows = await connection.query(
        '''
      select datetime 
      from submissions 
      where users_id=@users_id and courses_id=@courses_id and problem_id=@problem_id and datetime>=@datetime 
      order by datetime
      ''',
        substitutionValues: {
          'users_id': userId,
          'courses_id': courseId,
          'problem_id': problemId,
          'datetime': minDateTime,
        }
    );
    int submissionsCount = 0;
    DateTime? earliestSubmission;
    for (List<dynamic> fields in rows) {
      submissionsCount += 1;
      DateTime submissionDateTime = fields[0];
      if (submissionDateTime.isAfter(minDateTime)) {
        if (earliestSubmission==null || submissionDateTime.isBefore(earliestSubmission)) {
          earliestSubmission = submissionDateTime;
        }
      }
    }
    final courseData = await getCourseData(call, course);
    final problemData = courseData.findProblemById(problemId);
    int limit = problemData.maxSubmissionsPerHour>0 ? problemData.maxSubmissionsPerHour : courseData.maxSubmissionsPerHour;
    limit -= submissionsCount;
    if (limit < 0) {
      limit = 0;
    }
    DateTime? nextTimeReset = earliestSubmission;
    if (nextTimeReset != null) {
      nextTimeReset = nextTimeReset.add(Duration(hours: 1));
    }
    else {
      nextTimeReset = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return SubmissionsCountLimit(
      attemptsLeft: limit,
      nextTimeReset: Int64(nextTimeReset.toUtc().millisecondsSinceEpoch ~/ 1000),
      serverTime: Int64(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000),
    );
  }

  @override
  Future<Empty> notifyProblemStatusChanged(ServiceCall call, Submission request) async {
    final user = request.user;
    final course = request.course;
    final problemId = request.problemId;

    final courseKey = '${user.id}/${course.id}';
    final problemKey = '${user.id}/${course.id}/$problemId';

    final courseControllers = _courseStatusControllers[courseKey] ?? [];
    final problemControllers = _problemStatusControllers[problemKey] ?? [];

    if (problemControllers.isEmpty && courseControllers.isEmpty) {
      return Empty();
    }

    final futureCourseStatus = _getCourseStatus(call, user, course);

    futureCourseStatus.then((CourseStatus status) {
      for (final controller in courseControllers) {
        controller.add(status);
      }
    });

    if (problemControllers.isEmpty) {
      return Empty();
    }

    final courseData = await getCourseData(call, course);
    final problemMetadata = courseData.findProblemMetadataById(problemId);
    final problemStatus = await _getProblemStatus(call,
      user: user,
      course: course,
      problemMetadata: problemMetadata,
      withSubmissions: true,
    );

    for (final controller in problemControllers) {
      controller.sink.add(problemStatus);
    }
    return Empty();
  }

}