// Periodically checks for course changes and updates
// submission deadlines in background

import 'dart:async';
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import '../course_data_consumer.dart';

const checkInterval = 5;

class DeadlinesManagementService extends DeadlinesManagementServiceBase with CourseDataConsumer {

  final PostgreSQLConnection connection;
  final log = Logger('DeadlinesManager');
  final UserManagementClient userManager;
  final CourseManagementClient courseManager;
  final String secretKey;

  final Map<String,Int64> _courseDataLastModified = {};

  DeadlinesManagementService({
    required this.connection,
    required this.userManager,
    required this.courseManager,
    required CourseContentProviderClient contentProvider,
    required this.secretKey,
  }) : super() {
    super.contentProvider = contentProvider;
  }

  void start() {
    checkForDirtyCourses().then((_) {
      Timer.periodic(Duration(seconds: checkInterval), (_) => checkForDirtyCourses());
    });
  }

  Future checkForDirtyCourses() async {
    final rows = await connection.query(
        'select id,course_data,need_update_deadlines,name from courses',
    );

    for (final row in rows) {
      final courseId = row[0] as int;
      final courseDataId = row[1] as String;
      final needUpdate = row[2] as bool;
      final name = row[3] as String;
      final course = Course(
        id: courseId,
        dataId: courseDataId,
        name: name,
      );
      final dataModified = await isCourseDataModified(course);
      if (dataModified || needUpdate) {
        await updateCourseSubmissions(course);
      }
    }

  }

  Future<bool> isCourseDataModified(Course course) async {
    Int64 lastModified = Int64();
    if (_courseDataLastModified.containsKey(course.dataId)) {
      lastModified = _courseDataLastModified[course.dataId]!;
    }
    final contentRequest = CourseContentRequest(
      courseDataId: course.dataId,
      cachedTimestamp: lastModified,
    );
    try {
      final response = await contentProvider.getCoursePublicContent(contentRequest);
      bool courseModified = response.status == ContentStatus.HAS_DATA;
      _courseDataLastModified[course.dataId] = response.lastModified;
      return courseModified;
    }
    catch (e) {
      return false;
    }
  }


  Future updateCourseSubmissions(Course course) async {
    log.info('started updating submission deadlines for course ${course.id} (${course.name})');
    final courseData = await getCourseData(null, course);
    final submissionsRows = await connection.query(
      'select id, users_id, problem_id from submissions where courses_id=@course_id',
      substitutionValues: { 'course_id': course.id.toInt() },
    );
    final submissions = <Submission>[];
    for (final row in submissionsRows) {
      int submissionId = row[0];
      int usersId = row[1];
      String problemId = row[2];
      submissions.add(Submission(
        id: Int64(submissionId),
        problemId: problemId,
        user: User(id: Int64(usersId)),
      ));
    }
    final softDeadlines = <Int64,DateTime>{};
    final hardDeadlines = <Int64,DateTime>{};
    final users = <Int64,User>{};
    final scheduleSets = <User,LessonScheduleSet>{};
    for (final submission in submissions) {
      if (!users.containsKey(submission.user.id)) {
        users[submission.user.id] = await userManager.getProfileById(
          submission.user
        );
      }
      final user = users[submission.user.id]!;
      final lesson = courseData.findEnclosingLessonForProblem(submission.problemId);
      final deadlines = lesson.deadlines;
      if (!scheduleSets.containsKey(user)) {
        final request = LessonScheduleRequest(course: course, user: user);
        scheduleSets[user] = await getLessonSchedules(
            null, request
        );
      }
      final scheduleSet = scheduleSets[user]!;
      final lessonSchedule = scheduleSet.findByLesson(lesson.id);
      int softDeadLine = 0;
      int hardDeadLine = 0;
      if (deadlines.softDeadline > 0 && lessonSchedule.datetime > 0) {
        softDeadLine = deadlines.softDeadline + lessonSchedule.datetime.toInt();
      }
      if (deadlines.hardDeadline > 0 && lessonSchedule.datetime > 0) {
        hardDeadLine = deadlines.hardDeadline + lessonSchedule.datetime.toInt();
      }
      if (softDeadLine > 0) {
        softDeadlines[submission.id] = DateTime.fromMillisecondsSinceEpoch(
          softDeadLine * 1000, isUtc: true,
        );
      }
      if (hardDeadLine > 0) {
        hardDeadlines[submission.id] = DateTime.fromMillisecondsSinceEpoch(
          hardDeadLine * 1000, isUtc: true,
        );
      }
    }
    connection.transaction((connection) async {
      await connection.execute(
        'delete from submission_deadlines where courses_id=@course_id',
        substitutionValues: { 'course_id': course.id.toInt() }
      );
      for (final submission in submissions) {
        DateTime hard = hardDeadlines[submission.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime soft = softDeadlines[submission.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        await connection.execute('''
          insert into submission_deadlines(submissions_id,courses_id,hard,soft)
          values(@sid,@cid,@hard,@soft)
          ''',
          substitutionValues: {
            'sid': submission.id.toInt(),
            'cid': course.id.toInt(),
            'soft': soft,
            'hard': hard,
          }
        );
      }
      await connection.execute(
        'update courses set need_update_deadlines=false where id=@id',
        substitutionValues: {'id': course.id.toInt()},
      );
      return connection;
    }).then((_) {
      connection.execute('vacuum submission_deadlines');
      log.info('finished updating ${submissions.length} submission deadlines for course ${course.id} (${course.name})');
    });
  }

  @override
  Future<Submission> insertNewSubmission(ServiceCall call, Submission request) async {
    final user = request.user;
    final course = await courseManager.getCourse(request.course);
    final courseData = await getCourseData(call, course);
    final lesson = courseData.findEnclosingLessonForProblem(request.problemId);
    final deadlines = lesson.deadlines;
    final lessonScheduleRequest = LessonScheduleRequest(course: course, user: user);
    final scheduleSet = await getLessonSchedules(call, lessonScheduleRequest);
    final lessonSchedule = scheduleSet.findByLesson(lesson.id);
    int softDeadLine = 0;
    int hardDeadLine = 0;
    if (deadlines.softDeadline > 0 && lessonSchedule.datetime > 0) {
      softDeadLine = deadlines.softDeadline + lessonSchedule.datetime.toInt();
    }
    if (deadlines.hardDeadline > 0 && lessonSchedule.datetime > 0) {
      hardDeadLine = deadlines.hardDeadline + lessonSchedule.datetime.toInt();
    }
    try {
      await connection.execute('''
        insert into submission_deadlines(submissions_id,hard,soft,courses_id)
        values (@sid,@hard,@soft,@cid)
        ''',
          substitutionValues: {
            'sid': request.id.toInt(),
            'cid': course.id.toInt(),
            'hard': DateTime.fromMillisecondsSinceEpoch(
                hardDeadLine * 1000, isUtc: true),
            'soft': DateTime.fromMillisecondsSinceEpoch(
                softDeadLine * 1000, isUtc: true),
          }
      );
    }
    catch (e) {
      log.severe('cant insert into submission_deadlines: $e');
    }
    return request;
  }

  Future<int> hardDeadline(Submission submission) async {
    final rows = await connection.query(
      'select hard from submission_deadlines where submissions_id=@id',
      substitutionValues: {'id': submission.id.toInt() }
    );
    if (rows.isEmpty) {
      return 0;
    }
    final row = rows.single;
    final value = row.single as DateTime;
    if (value.isBefore(DateTime(2021))) {
      // 2021 is birth year of YaJudge
      return 0; // invalid deadline
    }
    return value.millisecondsSinceEpoch ~/ 1000;
  }

  Future<int> softDeadline(Submission submission) async {
    final rows = await connection.query(
        'select soft from submission_deadlines where submissions_id=@id',
        substitutionValues: {'id': submission.id.toInt() }
    );
    if (rows.isEmpty) {
      return 0;
    }
    final row = rows.single;
    final value = row.single as DateTime;
    if (value.isBefore(DateTime(2021))) {
      // 2021 is birth year of YaJudge
      return 0; // invalid deadline
    }
    return value.millisecondsSinceEpoch ~/ 1000;
  }

  @override
  Future<Submission> getSubmissionDeadlines(ServiceCall call, Submission request) async {
    int hard = await hardDeadline(request);
    int soft = await softDeadline(request);
    return Submission(
      id: request.id,
      hardDeadline: Int64(hard),
      softDeadline: Int64(soft),
    );
  }

  @override
  Future<LessonScheduleSet> getLessonSchedules(ServiceCall? call, LessonScheduleRequest request) async {
    final userEnrollments = await courseManager.getUserEnrollments(request.user);
    final courseData = await getCourseData(call, request.course);
    final allLessons = courseData.allLessons();
    String groupPattern = '';
    for (final enrollment in userEnrollments.enrollments) {
      if (enrollment.course.id == request.course.id) {
        groupPattern = enrollment.groupPattern;
        break;
      }
    }
    final queryValues = <String,dynamic>{'course_id': request.course.id.toInt()};
    String query = '''
    select datetime, repeat_count, repeat_interval_days
    from lesson_schedules
    where courses_id=@course_id
    ''';
    if (groupPattern.isNotEmpty) {
      query += ' and group_pattern=@group_pattern';
      queryValues['group_pattern'] = groupPattern;
    }
    var rows = [];
    try {
      rows = await connection.query(query, substitutionValues: queryValues);
    }
    catch (e) {
      log.severe('query error: $e');
    }
    final entries = <LessonSchedule>[];
    for (final row in rows) {
      DateTime dateTime = row[0];
      int repeatCount = row[1];
      int repeatIntervalDays = row[2];
      entries.add(LessonSchedule(
        datetime: Int64(dateTime.toUtc().millisecondsSinceEpoch ~/ 1000),
        repeatCount: repeatCount,
        repeatInterval: Duration(days: repeatIntervalDays).inSeconds,
      ));
    }
    final expandedTimestamps = <int>[];
    for (final entry in entries) {
      int base = entry.datetime.toInt();
      int interval = entry.repeatInterval;
      for (int i=0; i<entry.repeatCount; i++) {
        int timestamp = base + i*interval;
        expandedTimestamps.add(timestamp);
      }
    }
    expandedTimestamps.sort();
    final result = LessonScheduleSet().deepCopy();
    int entriesCount = math.min(expandedTimestamps.length, allLessons.length);
    for (int i=0; i<entriesCount; i++) {
      final lesson = allLessons[i];
      final datetime = Int64(expandedTimestamps[i]);
      result.schedules[lesson.id] = datetime;
    }
    return result;
  }

}