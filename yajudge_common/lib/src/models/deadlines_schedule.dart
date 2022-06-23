import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import '../../yajudge_common.dart';


extension DeadlinesExtension on Deadlines {

  int softDeadlinePenalty(LessonSchedule lessonSchedule, int submissionTimestamp) {
    if (softPenalty == 0 || softDeadline == 0) {
      return 0;
    }
    int deadlineInSeconds = lessonSchedule.datetime.toInt() + softDeadline;
    int secondsOverdue = submissionTimestamp - deadlineInSeconds;
    if (secondsOverdue <= 0) {
      return 0;
    }
    int hoursOverdue = secondsOverdue ~/ 60 ~/ 60;
    int totalPenalty = softPenalty * hoursOverdue;
    return totalPenalty;
  }

  bool hardDeadlinePassed(LessonSchedule lessonSchedule, int submissionTimestamp) {
    if (hardDeadline == 0 || lessonSchedule.datetime == 0) {
      return false;
    }
    int deadlineInSeconds = lessonSchedule.datetime.toInt() + hardDeadline;
    bool passed = submissionTimestamp > deadlineInSeconds;
    return passed;
  }

  Deadlines inherit(Deadlines parent) {
    Deadlines result = deepCopy();
    if (softPenalty == 0) {
      result.softPenalty = parent.softPenalty;
    }
    if (softDeadline == 0) {
      result.softDeadline = parent.softDeadline;
    }
    if (hardDeadline == 0) {
      result.hardDeadline = parent.hardDeadline;
    }
    return result;
  }

  static Deadlines fromYaml(YamlMap node) {
    Deadlines result = Deadlines().deepCopy();
    const softName = 'soft';
    const hardName = 'hard';
    const softPenaltyName = 'soft_penalty';
    const penaltyName = 'penalty';
    if (node.containsKey(softName)) {
      result.softDeadline = _parseDuration(node[softName]);
    }
    if (node.containsKey(hardName)) {
      result.hardDeadline = _parseDuration(node[hardName]);
    }
    if (node.containsKey(softPenaltyName)) {
      result.softPenalty = node[softPenaltyName];
    }
    else if (node.containsKey(penaltyName)) {
      result.softPenalty = node[penaltyName];
    }
    return result;
  }

  static int _parseDuration(String value) {
    value = value.replaceAll(RegExp(r'\s+'), '');
    if (value.length < 2) {
      return 0;
    }
    final suffix = value.substring(value.length-1).toLowerCase();
    final integer = value.substring(0, value.length-1);
    int? integerValue = int.tryParse(integer);
    if (integerValue == null) {
      return 0;
    }
    // h - hour
    // m - minute
    // d - day
    // w - week
    switch (suffix) {
      case 'h':
        return Duration(hours: integerValue).inSeconds;
      case 'm':
        return Duration(minutes: integerValue).inSeconds;
      case 'd':
        return Duration(days: integerValue).inSeconds;
      case 'w':
        return Duration(days: integerValue * 7).inSeconds;
      default:
        return 0;
    }
  }
}

extension LessonScheduleSetExtension on LessonScheduleSet {
  LessonSchedule findByLesson(String lessonId) {
    lessonId = path.normalize(lessonId.replaceAll(':', '/'));
    if (lessonId.startsWith('/')) {
      lessonId = lessonId.substring(1);
    }
    if (lessonId.endsWith('/')) {
      lessonId = lessonId.substring(0, lessonId.length-1);
    }
    if (schedules.containsKey(lessonId)) {
      final timestamp = schedules[lessonId]!;
      return LessonSchedule(datetime: timestamp);
    }
    else {
      return LessonSchedule();
    }
  }
}
