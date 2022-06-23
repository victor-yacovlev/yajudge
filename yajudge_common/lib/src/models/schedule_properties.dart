import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';

import '../../yajudge_common.dart';

bool isHardDeadlinePassed(Course course, CourseData courseData, Submission submission) {
  final schedule = courseData.findScheduleByProblemId(submission.problemId);
  DateTime submitted = DateTime.fromMillisecondsSinceEpoch(submission.timestamp.toInt() * 1000);
  DateTime base = DateTime.fromMillisecondsSinceEpoch(course.courseStart.toInt() * 1000);
  if (schedule.hasHardDeadline() && course.courseStart > 0) {
    DateTime hardDeadline = DateTime.fromMillisecondsSinceEpoch(
        base.millisecondsSinceEpoch + schedule.hardDeadline * 1000
    );
    if (submitted.millisecondsSinceEpoch > hardDeadline.millisecondsSinceEpoch) {
      return true;
    }
  }
  return false;
}

extension SchedulePropertiesExtension on ScheduleProperties {

  Duration get openDateAsDuration => Duration(seconds: openDate);

  bool get hasSoftDeadline => softDeadline >= 0;
  Duration get softDeadlineAsDuration => Duration(seconds: softDeadline);

  bool get hasHardDeadline => hardDeadline >= 0;
  Duration get hardDeadlineAsDuration => Duration(seconds: hardDeadline);

  static DateTime applyBaseTime(DateTime base, Duration value) {
    int msFromEpoch = base.millisecondsSinceEpoch + value.inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(msFromEpoch, isUtc: base.isUtc);
  }

  int softDeadlinePenalty(DateTime base, DateTime submitted, int cost) {
    if (base.millisecondsSinceEpoch==0 || !hasSoftDeadline) {
      return 0;
    }
    final deadlineDateTime = DateTime.fromMillisecondsSinceEpoch(
        base.millisecondsSinceEpoch + softDeadline * 1000, isUtc: base.isUtc
    );
    int msOver = submitted.millisecondsSinceEpoch - deadlineDateTime.millisecondsSinceEpoch;
    if (msOver <= 0) {
      return 0;
    }
    int hoursOver = msOver ~/ 1000 ~/ 60 ~/ 60;
    return cost * hoursOver;
  }

  bool isHardDeadlinePassed(DateTime base, DateTime submitted) {
    if (base.millisecondsSinceEpoch==0 || !hasHardDeadline) {
      return false;
    }
    final deadlineDateTime = DateTime.fromMillisecondsSinceEpoch(
        base.millisecondsSinceEpoch + hardDeadline*1000, isUtc: base.isUtc
    );
    return submitted.millisecondsSinceEpoch > deadlineDateTime.millisecondsSinceEpoch;
  }

  static ScheduleProperties fromYaml(YamlMap node) {
    final result = ScheduleProperties().deepCopy();
    const openDateKey = 'open_date';
    const softDeadlineKey = 'soft_deadline';
    const hardDeadlineKey = 'hard_deadline';
    if (node.containsKey(openDateKey)) {
      result.openDate = _parseDuration(node[openDateKey]).inSeconds;
    }
    if (node.containsKey(softDeadlineKey)) {
      result.softDeadline = _parseDuration(node[softDeadlineKey]).inSeconds;
    }
    if (node.containsKey(hardDeadlineKey)) {
      result.hardDeadline = _parseDuration(node[hardDeadlineKey]).inSeconds;
    }
    return result;
  }

  static Duration _parseDuration(String value) {
    value = value.replaceAll(RegExp(r'\s+'), '');
    if (value.length < 2) {
      return Duration();
    }
    final suffix = value.substring(value.length-1).toLowerCase();
    final integer = value.substring(0, value.length-1);
    int? integerValue = int.tryParse(integer);
    if (integerValue == null) {
      return Duration();
    }
    // h - hour
    // m - minute
    // d - day
    // w - week
    switch (suffix) {
      case 'h':
        return Duration(hours: integerValue);
      case 'm':
        return Duration(minutes: integerValue);
      case 'd':
        return Duration(days: integerValue);
      case 'w':
        return Duration(days: integerValue * 7);
      default:
        return Duration();
    }
  }

  ScheduleProperties mergeWith(ScheduleProperties other) {
    ScheduleProperties result = ScheduleProperties().deepCopy();
    int newOpenDate = openDate + other.openDate;
    int newSoftDeadline = other.softDeadline>=0? softDeadline + other.softDeadline : -1;
    int newHardDeadline = other.hardDeadline>=0? hardDeadline + other.hardDeadline : -1;
    result.openDate = newOpenDate;
    result.softDeadline = newSoftDeadline;
    result.hardDeadline = newHardDeadline;
    return result;
  }

}