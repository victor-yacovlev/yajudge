// Periodically checks for course changes and updates
// submission deadlines in background

import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'master_service.dart';

const checkInterval = 5;

class DeadlinesManager {

  final MasterService parent;
  final PostgreSQLConnection connection;
  final logger = Logger('DeadlinesManager');

  final Map<String,Int64> _courseDataLastModified = {};

  DeadlinesManager(this.parent, this.connection);

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
        id: Int64(courseId),
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
      final response = await parent.courseManagementService
          .getCoursePublicContent(
          null, contentRequest
      );
      bool courseModified = response.status == ContentStatus.HAS_DATA;
      _courseDataLastModified[course.dataId] = response.lastModified;
      return courseModified;
    }
    catch (e) {
      return false;
    }
  }

  Future updateCourseSubmissions(Course course) async {
    logger.info('started updating submission deadlines for course ${course.id} (${course.name})');
    final courseData = parent.courseManagementService.getCourseData(course.dataId);
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
        users[submission.user.id] = await parent.userManagementService.getUserById(
          submission.user.id
        );
      }
      final user = users[submission.user.id]!;
      final lesson = courseData.findEnclosingLessonForProblem(submission.problemId);
      final deadlines = lesson.deadlines;
      if (!scheduleSets.containsKey(user)) {
        final request = LessonScheduleRequest(course: course, user: user);
        scheduleSets[user] = await parent.courseManagementService.getLessonSchedules(
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
      logger.info('finished updating ${submissions.length} submission deadlines for course ${course.id} (${course.name})');
    });
  }

  Future insertNewSubmission(Submission submission) async {
    final user = submission.user;
    final course = await parent.courseManagementService.getCourseInfo(submission.course.id);
    final courseData = parent.courseManagementService.getCourseData(course.dataId);
    final lesson = courseData.findEnclosingLessonForProblem(submission.problemId);
    final deadlines = lesson.deadlines;
    final request = LessonScheduleRequest(course: course, user: user);
    final scheduleSet = await parent.courseManagementService.getLessonSchedules(null, request);
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
            'sid': submission.id.toInt(),
            'cid': course.id.toInt(),
            'hard': DateTime.fromMillisecondsSinceEpoch(
                hardDeadLine * 1000, isUtc: true),
            'soft': DateTime.fromMillisecondsSinceEpoch(
                softDeadLine * 1000, isUtc: true),
          }
      );
    }
    catch (e) {
      logger.severe('cant insert into submission_deadlines: $e');
    }
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

  Future<Submission> updateSubmissionWithDeadlines(Submission submission) async {
    submission = submission.deepCopy();
    int hard = await hardDeadline(submission);
    int soft = await softDeadline(submission);
    submission.hardDeadline = Int64(hard);
    submission.softDeadline = Int64(soft);
    return submission;
  }

}