import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';
import './generated/yajudge.pb.dart';

class CourseDataCacheItem {
  CourseData? data;
  DateTime? lastModified;
  DateTime? lastChecked;
  Object? loadError;

  CourseDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}

class ProblemDataCacheItem {
  ProblemData? data;
  DateTime? lastModified;
  DateTime? lastChecked;
  Object? loadError;

  ProblemDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });
}

extension CourseDataExtension on CourseData {

  Lesson findLessonByKey(String key) {
    if (key.startsWith('/')) {
      key = key.substring(1);
    }
    List<String> parts = key.split('/');
    parts.removeWhere((element) => element.isEmpty);
    Section section = Section();
    String lessonId;
    if (sections.length==1 && sections.single.id.isEmpty) {
      section = sections.single;
      assert (parts.isNotEmpty);
      lessonId = parts[0];
    }
    else {
      assert(parts.length >= 2);
      String sectionId = parts[0];
      lessonId = parts[1];
      for (final entry in sections) {
        if (entry.id == sectionId) {
          section = entry;
          break;
        }
      }
    }

    Lesson lesson = Lesson();
    for (final entry in section.lessons) {
      if (entry.id == lessonId) {
        lesson = entry;
        break;
      }
    }

    return lesson;
  }

  TextReading findReadingByKey(String key) {
    final parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (final section in sections) {
      if (section.id == parts[0]) {
        for (final lesson in section.lessons) {
          if (lesson.id == parts[1]) {
            for (final reading in lesson.readings) {
              if (reading.id == parts[2]) {
                return reading;
              }
            }
          }
        }
      }
    }
    return TextReading();
  }


  ProblemData findProblemByKey(String key) {
    final parts = key.substring(1).split('/');
    assert (parts.length >= 3);
    for (final section in sections) {
      if (section.id == parts[0]) {
        for (final lesson in section.lessons) {
          if (lesson.id == parts[1]) {
            for (final problem in lesson.problems) {
              if (problem.id == parts[2]) {
                return problem;
              }
            }
          }
        }
      }
    }
    return ProblemData();
  }

  ProblemData findProblemById(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          if (problem.id == problemId) {
            return problem;
          }
        }
      }
    }
    return ProblemData();
  }

  ProblemMetadata findProblemMetadataById(String problemId) {
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problemsMetadata) {
          if (problem.id == problemId) {
            return problem;
          }
        }
      }
    }
    return ProblemMetadata();
  }

}


ProblemStatus findProblemStatus(CourseStatus course, String problemId) {
  for (final section in course.sections) {
    for (final lesson in section.lessons) {
      for (final problem in lesson.problems) {
        if (problem.problemId == problemId) {
          return problem;
        }
      }
    }
  }
  return ProblemStatus();
}


bool submissionsCountLimitIsValid(SubmissionsCountLimit countLimit) {
  return countLimit.attemptsLeft!=0 || countLimit.nextTimeReset!=0;
}

extension GradingLimitsExtension on GradingLimits {

  static GradingLimits fromYaml(YamlMap conf) {
    int stackSize = 0;
    int memoryMax = 0;
    int cpuTime = 0;
    int realTime = 0;
    int procs = 0;
    int procStartDelay = 0;
    int files = 0;
    int stdoutMax = 0;
    int stderrMax = 0;
    bool allowNetwork = false;

    if (conf['stack_size_limit_mb'] is int) {
      stackSize = conf['stack_size_limit_mb'];
    }
    if (conf['memory_max_limit_mb'] is int) {
      memoryMax = conf['memory_max_limit_mb'];
    }
    if (conf['cpu_time_limit_sec'] is int) {
      cpuTime = conf['cpu_time_limit_sec'];
    }
    if (conf['real_time_limit_sec'] is int) {
      realTime = conf['real_time_limit_sec'];
    }
    if (conf['proc_count_limit'] is int) {
      procs = conf['proc_count_limit'];
    }
    if (conf['new_proc_delay_msec'] is int) {
      procStartDelay = conf['new_proc_delay_msec'];
    }
    if (conf['fd_count_limit'] is int) {
      files = conf['fd_count_limit'];
    }
    if (conf['stdout_size_limit_mb'] is int) {
      stdoutMax = conf['stdout_size_limit_mb'];
    }
    if (conf['stderr_size_limit_mb'] is int) {
      stderrMax = conf['stderr_size_limit_mb'];
    }
    if (conf['allow_network'] is bool) {
      allowNetwork = conf['allow_network'].toString().toLowerCase()=='true';
    }
    return GradingLimits(
      stackSizeLimitMb: Int64(stackSize),
      memoryMaxLimitMb: Int64(memoryMax),
      cpuTimeLimitSec: Int64(cpuTime),
      realTimeLimitSec: Int64(realTime),
      procCountLimit: Int64(procs),
      newProcDelayMsec: Int64(procStartDelay),
      fdCountLimit: Int64(files),
      stdoutSizeLimitMb: Int64(stdoutMax),
      stderrSizeLimitMb: Int64(stderrMax),
      allowNetwork: allowNetwork,
    );
  }

  GradingLimits mergedWith(GradingLimits u) {
    GradingLimits s = deepCopy();
    if (u.stackSizeLimitMb != 0) {
      s.stackSizeLimitMb = u.stackSizeLimitMb;
    }
    if (u.memoryMaxLimitMb != 0) {
      s.memoryMaxLimitMb = u.memoryMaxLimitMb;
    }
    if (u.cpuTimeLimitSec != 0) {
      s.cpuTimeLimitSec = u.cpuTimeLimitSec;
    }
    if (u.realTimeLimitSec != 0) {
      s.realTimeLimitSec = u.realTimeLimitSec;
    }
    if (u.procCountLimit != 0) {
      s.procCountLimit = u.procCountLimit;
    }
    if (u.fdCountLimit != 0) {
      s.fdCountLimit = u.fdCountLimit;
    }
    if (u.stdoutSizeLimitMb != 0) {
      s.stdoutSizeLimitMb = u.stdoutSizeLimitMb;
    }
    if (u.stderrSizeLimitMb != 0) {
      s.stderrSizeLimitMb = u.stderrSizeLimitMb;
    }
    if (u.allowNetwork) {
      s.allowNetwork = u.allowNetwork;
    }
    return s;
  }

  String toYamlString({int level = 0}) {
    String indent = level > 0 ? '  ' * level : '';
    String result = '';
    if (stackSizeLimitMb > 0) {
      result += '${indent}stack_size_limit_mb: $stackSizeLimitMb\n';
    }
    if (memoryMaxLimitMb > 0) {
      result += '${indent}memory_max_limit_mb: $memoryMaxLimitMb\n';
    }
    if (cpuTimeLimitSec > 0) {
      result += '${indent}cpu_time_limit_sec: $cpuTimeLimitSec\n';
    }
    if (realTimeLimitSec > 0) {
      result += '${indent}real_time_limit_sec: $realTimeLimitSec\n';
    }
    if (procCountLimit > 0) {
      result += '${indent}proc_count_limit: $procCountLimit\n';
    }
    if (newProcDelayMsec > 0) {
      result += '${indent}new_proc_delay_msec: $newProcDelayMsec\n';
    }
    if (fdCountLimit > 0) {
      result += '${indent}fd_count_limit: $fdCountLimit\n';
    }
    if (stdoutSizeLimitMb > 0) {
      result += '${indent}stdout_size_limit_mb: $stdoutSizeLimitMb\n';
    }
    if (stderrSizeLimitMb > 0) {
      result += '${indent}stderr_size_limit_mb: $stderrSizeLimitMb\n';
    }
    if (allowNetwork) {
      result += '${indent}allow_network: $allowNetwork\n';
    }
    return result;
  }

}

SecurityContext securityContextFromYaml(YamlMap conf) {
  List<String> forbiddenFunctions = [];
  List<String> allowedFunctions = [];

  if (conf['forbidden_functions'] is YamlList) {
    YamlList list = conf['forbidden_functions'];
    for (final entry in list) {
      String name = entry;
      if (!forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  else if (conf['forbidden_functions'] is String) {
    final parts = (conf['forbidden_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  if (conf['allowed_functions'] is YamlList) {
    YamlList list = conf['allowed_functions'];
    for (final entry in list) {
      String name = entry;
      if (!allowedFunctions.contains(name)) {
        allowedFunctions.add(name);
      }
    }
  }
  else if (conf['allowed_functions'] is String) {
    final parts = (conf['allowed_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !allowedFunctions.contains(name)) {
        allowedFunctions.add(name);
      }
    }
  }
  return SecurityContext(
    forbiddenFunctions: forbiddenFunctions,
    allowedFunctions: allowedFunctions,
  );
}

SecurityContext mergeSecurityContext(SecurityContext source, SecurityContext update) {
  List<String> forbiddenFunctions = source.forbiddenFunctions;
  for (final name in update.forbiddenFunctions) {
    if (!forbiddenFunctions.contains(name)) {
      forbiddenFunctions.add(name);
    }
  }
  for (final name in update.allowedFunctions) {
    if (forbiddenFunctions.contains(name)) {
      forbiddenFunctions.remove(name);
    }
  }
  return SecurityContext(forbiddenFunctions: forbiddenFunctions);
}

SecurityContext mergeSecurityContextFromYaml(SecurityContext source, YamlMap conf) {
  List<String> forbiddenFunctions = source.forbiddenFunctions;
  if (conf['forbidden_functions'] is YamlList) {
    YamlList list = conf['forbidden_functions'];
    for (final entry in list) {
      String name = entry;
      if (!forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  else if (conf['forbidden_functions'] is String) {
    final parts = (conf['forbidden_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && !forbiddenFunctions.contains(name)) {
        forbiddenFunctions.add(name);
      }
    }
  }
  if (conf['allowed_functions'] is YamlList) {
    YamlList list = conf['allowed_functions'];
    for (final entry in list) {
      String name = entry;
      if (forbiddenFunctions.contains(name)) {
        forbiddenFunctions.remove(name);
      }
    }
  }
  else if (conf['allowed_functions'] is String) {
    final parts = (conf['allowed_functions'] as String).split(' ');
    for (final name in parts) {
      if (name.isNotEmpty && forbiddenFunctions.contains(name)) {
        forbiddenFunctions.remove(name);
      }
    }
  }
  return SecurityContext(
    forbiddenFunctions: forbiddenFunctions
  );
}

String securityContextToYamlString(SecurityContext securityContext, [int level = 0]) {
  String indent = level > 0 ? '  ' * level : '';
  String result = '';
  if (securityContext.allowedFunctions.isNotEmpty) {
    result += '${indent}allowed_functions: ${securityContext.allowedFunctions.join(' ')}\n';
  }
  if (securityContext.forbiddenFunctions.isNotEmpty) {
    result += '${indent}forbidden_functions: ${securityContext.forbiddenFunctions.join(' ')}\n';
  }
  return result;
}

extension SubmissionListEntryExtension on SubmissionListEntry {
  void updateStatus(SolutionStatus newStatus) {
    status = newStatus;
  }
}

extension SubmissionListQueryExtension on SubmissionListQuery {
  bool match(Submission submission, User currentUser) {
    if (submissionId!=0 && submissionId==submission.id) {
      return true;
    }
    bool statusMatch = true;
    if (statusFilter != SolutionStatus.ANY_STATUS_OR_NULL) {
      statusMatch = submission.status==statusFilter;
    }

    bool currentUserMatch = currentUser.id==submission.user.id;
    bool hideThisSubmission = false;
    if (currentUserMatch) {
      hideThisSubmission = !showMineSubmissions;
    }

    bool problemMatch = true;
    if (problemIdFilter.isNotEmpty) {
      problemMatch = problemIdFilter==submission.problemId;
    }
    bool nameMatch = true;
    if (nameQuery.trim().isNotEmpty) {
      final normalizedName = nameQuery.trim().toUpperCase().replaceAll(r'\s+', ' ');
      final user = submission.user;
      bool firstNameLike = user.firstName.toUpperCase().startsWith(normalizedName);
      bool lastNameLike = user.firstName.toUpperCase().startsWith(normalizedName);
      final firstLastName = '${user.firstName} ${user.lastName}'.toUpperCase();
      final lastFirstName = '${user.lastName} ${user.firstName}'.toUpperCase();
      bool firstLastNameLike = firstLastName.startsWith(normalizedName);
      bool lastFirstNameLike = lastFirstName.startsWith(normalizedName);
      nameMatch = firstNameLike || lastNameLike || lastFirstNameLike || firstLastNameLike;
    }
    return statusMatch && problemMatch && nameMatch && !hideThisSubmission;
  }
}

extension SubmissionExtension on Submission {
  SubmissionListEntry asSubmissionListEntry() {
    return SubmissionListEntry(
      submissionId: id,
      status: status,
      sender: user,
      timestamp: timestamp,
      problemId: problemId,
    );
  }

  void updateId(int newId) {
    id = Int64(newId);
  }
}

extension ReviewHistoryExtension on ReviewHistory {
  CodeReview? findBySubmissionId(Int64 submissionId) {
    for (final review in reviews) {
      if (review.submissionId == submissionId) {
        return review;
      }
    }
    return null;
  }
}

extension CodeReviewExtension on CodeReview {

  String debugInfo() {
    final lineMessages = lineComments.map((e) => '${e.lineNumber+1}: "${e.message}"');
    return '{ "$globalComment", [${lineMessages.join(', ')}]';
  }

  bool get contentIsEmpty {
    bool globalCommentIsEmpty = globalComment.trim().isEmpty;
    bool linesEmpty = lineComments.isEmpty;
    return globalCommentIsEmpty && linesEmpty;
  }

  bool get contentIsNotEmpty => !contentIsEmpty;

  bool contentEqualsTo(CodeReview other) {
    final myGlobalComment = globalComment.trim();
    final otherGlobalComment = other.globalComment.trim();
    final myLineComments = lineComments;
    final otherLineComments = other.lineComments;
    if (myGlobalComment != otherGlobalComment) {
      return false;
    }
    if (myLineComments.length != otherLineComments.length) {
      return false;
    }
    for (final myComment in myLineComments) {
      LineComment? matchingOtherComment;
      for (final otherComment in otherLineComments) {
        if (otherComment.fileName==myComment.fileName && otherComment.lineNumber==myComment.lineNumber) {
          matchingOtherComment = otherComment;
          break;
        }
      }
      if (matchingOtherComment == null) {
        return false;
      }
      if (matchingOtherComment.message.trim() != myComment.message.trim()) {
        return false;
      }
    }
    return true;
  }
}