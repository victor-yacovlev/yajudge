import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';
import './generated/yajudge.pb.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart'
  if (dart.library.io) 'package:archive/archive_io.dart'
  if (dart.librart.html) 'package:archive/archive.dart';

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

extension ProblemDataExtension on ProblemData {

  void cleanPrivateContent() {
    // must be called only after deepCopy

    final limits = gradingOptions.limits;
    gradingOptions = GradingOptions(limits: limits);
    graderFiles = FileSet();
  }

}

extension CourseDataExtension on CourseData {

  void cleanPrivateContent() {
    // must be called only after deepCopy

    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problems) {
          problem.cleanPrivateContent();
        }
      }
    }
  }

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

  ScheduleProperties findScheduleByProblemId(String problemId) {
    ScheduleProperties schedule = scheduleProperties;
    for (final section in sections) {
      for (final lesson in section.lessons) {
        for (final problem in lesson.problemsMetadata) {
          if (problem.id == problemId) {
            return schedule
                .mergeWith(section.scheduleProperties)
                .mergeWith(lesson.scheduleProperties)
                .mergeWith(problem.scheduleProperties)
                ;
          }
        }
      }
    }
    return ScheduleProperties();
  }

}

extension CourseStatusExtension on CourseStatus {
  ProblemStatus findProblemStatus(String problemId) {
    for (final section in sections) {
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
}

extension CoursesListExtension on CoursesList {
  CoursesList_CourseListEntry? findByUrlPrefix(String urlPrefix) {
    for (final entry in courses) {
      if (entry.course.urlPrefix == urlPrefix) {
        return entry;
      }
    }
    return null;
  }
}


bool submissionsCountLimitIsValid(SubmissionsCountLimit countLimit) {
  return countLimit.attemptsLeft!=0 || countLimit.nextTimeReset!=0;
}

ExecutableTarget executableTargetFromString(dynamic conf) {
  String c = '';
  if (conf is String) {
    c = conf.toLowerCase().replaceAll('-', '_');
  }
  switch (c) {
    case 'bash_script':
    case 'bash':
    case 'shell':
    case 'shell_script':
      return ExecutableTarget.ShellScript;
    case 'python_script':
    case 'python':
      return ExecutableTarget.PythonScript;
    case 'native':
    case 'unchecked':
      return ExecutableTarget.Native;
    case 'valgrind':
      return ExecutableTarget.NativeWithValgrind;
    case 'sanitizers':
    case 'sanitized':
      return ExecutableTarget.NativeWithSanitizers;
    case 'checked':
      return ExecutableTarget.NativeWithSanitizersAndValgrind;
    case 'java':
    case 'jre':
    case 'java_class':
    case 'class':
      return ExecutableTarget.JavaClass;
    case 'java_jar':
    case 'jar':
      return ExecutableTarget.JavaJar;
    case 'qemu_system':
    case 'qemu_image':
    case 'qemu_system_image':
      return ExecutableTarget.QemuSystemImage;
    default:
      return ExecutableTarget.AutodetectExecutable;
  }
}

String executableTargetToString(ExecutableTarget target) {
  switch (target) {
    case ExecutableTarget.AutodetectExecutable:
      return 'auto';
    case ExecutableTarget.ShellScript:
      return 'shell';
    case ExecutableTarget.JavaClass:
      return 'java';
    case ExecutableTarget.JavaJar:
      return 'java-jar';
    case ExecutableTarget.Native:
      return 'native';
    case ExecutableTarget.NativeWithSanitizers:
      return 'sanitizers';
    case ExecutableTarget.NativeWithValgrind:
      return 'valgrind';
    case ExecutableTarget.NativeWithSanitizersAndValgrind:
      return 'checked';
    case ExecutableTarget.PythonScript:
      return 'python';
    case ExecutableTarget.QemuSystemImage:
      return 'qemu-system';
    default:
      return 'auto';
  }
}

enum ProgrammingLanguage {
  unknown,
  c,
  cxx,
  java,
  python,
  bash,
  go,
  gnuAsm,
}

BuildSystem buildSystemFromString(dynamic conf) {
  String c = '';
  if (conf is String) {
    c = conf.toLowerCase().replaceAll('-', '_');
  }
  switch (c) {
    case 'none':
    case 'no':
    case 'skip':
      return BuildSystem.SkipBuild;
    case 'c':
    case 'cpp':
    case 'cxx':
    case 'c++':
    case 'gcc':
    case 'clang':
      return BuildSystem.ClangToolchain;
    case 'make':
    case 'makefile':
      return BuildSystem.MakefileProject;
    case 'go':
    case 'golang':
      return BuildSystem.GoLangProject;
    case 'cmake':
    case 'cmakelists':
    case 'cmakelists.txt':
      return BuildSystem.CMakeProject;
    case 'java':
    case 'javac':
      return BuildSystem.JavaPlainProject;
    case 'maven':
    case 'mvn':
    case 'pom':
    case 'pom.xml':
      return BuildSystem.MavenProject;
    default:
      return BuildSystem.AutodetectBuild;
  }
}

String buildSystemToString(BuildSystem buildSystem) {
  switch (buildSystem) {
    case BuildSystem.AutodetectBuild:
      return 'auto';
    case BuildSystem.CMakeProject:
      return 'cmake';
    case BuildSystem.ClangToolchain:
      return 'clang';
    case BuildSystem.GoLangProject:
      return 'go';
    case BuildSystem.JavaPlainProject:
      return 'javac';
    case BuildSystem.MakefileProject:
      return 'make';
    case BuildSystem.MavenProject:
      return 'mvn';
    case BuildSystem.PythonCheckers:
      return 'pylint';
    case BuildSystem.SkipBuild:
      return 'none';
    default:
      return 'auto';
  }
}

Map<String,String> propertiesFromYaml(dynamic conf) {
  Map<String,String> result = {};
  if (conf is YamlMap) {
    final props = conf;
    for (final property in props.entries) {
      final propertyName = property.key.toString();
      final propertyValue = property.value.toString();
      result[propertyName] = propertyValue;
    }
  }
  return result;
}

String propertiesToYaml(Map<String,String> props) {
  String result = '';
  for (final key in props.keys) {
    final value = props[key];
    result += '$key: \'$value\'\n';
  }
  return result;
}

extension GradingLimitsExtension on GradingLimits {

  static GradingLimits fromYaml(dynamic confOrNull) {
    if (confOrNull is! YamlMap) {
      return GradingLimits();
    }
    YamlMap conf = confOrNull;
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

SecurityContext securityContextFromYaml(dynamic confOrNull) {
  if (confOrNull == null || confOrNull !is YamlMap) {
    return SecurityContext();
  }
  YamlMap conf = confOrNull;
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
      gradingStatus: gradingStatus,
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

extension GradingOptionsExtension on GradingOptions {

  static const buildName = '.build';
  static const buildPropertiesName = '.build_properties';
  static const targetName = '.target';
  static const targetPropertiesName = '.target_properties';
  static const styleNamePrefix = '.style_';
  static const checkerName = '.checker';
  static const interactorName = '.interactor';
  static const coprocessName = '.coprocess';
  static const testsGeneratorName = '.tests_generator';
  static const limitsName = '.limits';
  static const securityContextName = '.security_context';
  static const testsCountName = '.tests_count';
  static const testsRequireBuildName = '.tests_require_build';


  void saveToPlainFiles(io.Directory targetDirectory) {
    final dirPath = targetDirectory.path;
    _saveBuild(io.File('$dirPath/$buildName'));
    _saveBuildProperties(io.File('$dirPath/$buildPropertiesName'));
    _saveTarget(io.File('$dirPath/$targetName'));
    _saveTargetProperties(io.File('$dirPath/$targetPropertiesName'));
    _saveCodeStyles(targetDirectory);
    _saveChecker(targetDirectory);
    _saveInteractor(targetDirectory);
    _saveCoprocess(targetDirectory);
    _saveTestsGenerator(targetDirectory);
    _saveLimits(io.File('$dirPath/$limitsName'));
    _saveSecurityContext(io.File('$dirPath/$securityContextName'));
    if (testsRequiresBuild) {
      io.File('$dirPath/$testsRequireBuildName').createSync();
    }
  }

  static GradingOptions loadFromPlainFiles(io.Directory sourceDirectory) {
    GradingOptions result = GradingOptions().deepCopy();
    final dirPath = sourceDirectory.path;
    result._loadBuild(io.File('$dirPath/$buildName'));
    result._loadBuildProperties(io.File('$dirPath/$buildPropertiesName'));
    result._loadTarget(io.File('$dirPath/$targetName'));
    result._loadTargetProperties(io.File('$dirPath/$targetPropertiesName'));
    result._loadCodeStyles(sourceDirectory);
    result._loadChecker(sourceDirectory);
    result._loadInteractor(sourceDirectory);
    result._loadCoprocess(sourceDirectory);
    result._loadTestsGenerator(sourceDirectory);
    result._loadLimits(io.File('$dirPath/$limitsName'));
    result._loadSecurityContext(io.File('$dirPath/$securityContextName'));
    result.testsRequiresBuild = io.File('$dirPath/$testsRequireBuildName').existsSync();
    return result;
  }

  void _saveBuild(io.File file) => file.writeAsStringSync(buildSystemToString(buildSystem));
  void _loadBuild(io.File file) {
    buildSystem = buildSystemFromString(
        file.existsSync() ? file.readAsStringSync().trim() : null
    );
  }
  void _saveBuildProperties(io.File file) => file.writeAsStringSync(propertiesToYaml(buildProperties));
  void _loadBuildProperties(io.File file) {
    buildProperties.addAll(propertiesFromYaml(
        file.existsSync() ? loadYaml(file.readAsStringSync()) : null
    ));
  }
  void _saveTarget(io.File file) {
    final executableTargetName = executableTargetToString(executableTarget);
    file.writeAsStringSync(executableTargetName);
  }
  void _loadTarget(io.File file) {
    executableTarget = executableTargetFromString(
      file.existsSync() ? file.readAsStringSync().trim() : null
    );
  }
  void _saveTargetProperties(io.File file) => file.writeAsStringSync(propertiesToYaml(targetProperties));
  void _loadTargetProperties(io.File file) {
    targetProperties.addAll(propertiesFromYaml(
        file.existsSync() ? loadYaml(file.readAsStringSync()) : null
    ));
  }
  void _saveCodeStyles(io.Directory targetDirectory) {
    for (final codeStyle in codeStyles) {
      final styleFile = codeStyle.styleFile;
      final codeStyleFileName = styleFile.name;
      final suffix = codeStyle.sourceFileSuffix.replaceAll('.', '');
      io.File('${targetDirectory.path}/$codeStyleFileName').writeAsBytesSync(styleFile.data);
      io.File('${targetDirectory.path}/$styleNamePrefix$suffix').writeAsStringSync(styleFile.name);
    }
  }
  void _loadCodeStyles(io.Directory sourceDirectory) {
    sourceDirectory.list().forEach((final entity) {
      if (entity.path.startsWith(styleNamePrefix)) {
        final suffix = entity.path.substring(styleNamePrefix.length);
        final codeStyleFileName = io.File('${sourceDirectory.path}/${entity.path}')
            .readAsStringSync().trim();
        final codeStyleData = io.File('${sourceDirectory.path}/$codeStyleFileName}')
            .readAsBytesSync().toList();
        codeStyles.add(CodeStyle(
          sourceFileSuffix: suffix,
          styleFile: File(name: codeStyleFileName, data: codeStyleData),
        ));
      }
    });
  }
  void _saveChecker(io.Directory targetDirectory) {
    final checkerOpts = standardCheckerOpts;
    if (customChecker.name.isNotEmpty) {
      final checkerFileName = customChecker.name;
      io.File('${targetDirectory.path}/$checkerFileName')
          .writeAsBytesSync(customChecker.data);
      io.File('${targetDirectory.path}/$checkerName')
          .writeAsStringSync('$checkerFileName\n$checkerOpts\n');
    }
    else {
      final standardCheckerName = standardChecker;
      io.File('${targetDirectory.path}/$checkerName')
          .writeAsStringSync('=$standardCheckerName\n$checkerOpts\n');
    }
  }
  void _loadChecker(io.Directory sourceDirectory) {
    final checkerLines = io.File('${sourceDirectory.path}/$checkerName')
        .readAsLinesSync();
    checkerLines.removeWhere((element) => element.isEmpty);
    final checkerFileOrStandardName = checkerLines.first.trim();
    if (checkerFileOrStandardName.startsWith('=')) {
      standardChecker = checkerFileOrStandardName.substring(1);
    }
    else {
      final checkerData = io.File('${sourceDirectory.path}/$checkerFileOrStandardName')
          .readAsBytesSync().toList();
      customChecker = File(name: checkerFileOrStandardName, data: checkerData);
    }
    final checkerOptions = checkerLines.length > 1? checkerLines[1].split(' ') : [];
    standardCheckerOpts = checkerOptions.join(' ');
  }
  void _saveInteractor(io.Directory targetDirectory) {
    if (interactor.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$interactorName').writeAsStringSync(interactor.name);
      io.File('${targetDirectory.path}/${interactor.name}').writeAsBytesSync(interactor.data);
    }
  }
  void _loadInteractor(io.Directory sourceDirectory) {
    final interactorFile = io.File('${sourceDirectory.path}/$interactorName');
    if (interactorFile.existsSync()) {
      final interactorFileName = interactorFile.readAsStringSync().trim();
      final interactorData = io.File('${sourceDirectory.path}/$interactorFileName').readAsBytesSync();
      interactor = File(name: interactorFileName, data: interactorData);
    }
  }
  void _saveCoprocess(io.Directory targetDirectory) {
    if (coprocess.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$coprocessName').writeAsStringSync(coprocess.name);
      io.File('${targetDirectory.path}/${coprocess.name}').writeAsBytesSync(coprocess.data);
    }
  }
  void _loadCoprocess(io.Directory sourceDirectory) {
    final coprocessFile = io.File('${sourceDirectory.path}/$coprocessName');
    if (coprocessFile.existsSync()) {
      final coprocessFileName = coprocessFile.readAsStringSync().trim();
      final coprocessData = io.File('${sourceDirectory.path}/$coprocessFileName').readAsBytesSync();
      coprocess = File(name: coprocessFileName, data: coprocessData);
    }
  }
  void _saveTestsGenerator(io.Directory targetDirectory) {
    if (testsGenerator.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$testsGeneratorName').writeAsStringSync(testsGenerator.name);
      io.File('${targetDirectory.path}/${testsGenerator.name}').writeAsBytesSync(testsGenerator.data);
    }
  }
  void _loadTestsGenerator(io.Directory sourceDirectory) {
    final testsGeneratorFile = io.File('${sourceDirectory.path}/$testsGeneratorName');
    if (testsGeneratorFile.existsSync()) {
      final testsGeneratorFileName = testsGeneratorFile.readAsStringSync().trim();
      final testsGeneratorData = io.File('${sourceDirectory.path}/$testsGeneratorFileName').readAsBytesSync();
      testsGenerator = File(name: testsGeneratorFileName, data: testsGeneratorData);
    }
  }
  void _saveLimits(io.File file) => file.writeAsStringSync(limits.toYamlString());
  void _loadLimits(io.File file) {
    limits = GradingLimitsExtension.fromYaml(loadYaml(file.readAsStringSync()));
  }
  void _saveSecurityContext(io.File file) =>
      file.writeAsStringSync(securityContextToYamlString(securityContext));
  void _loadSecurityContext(io.File file) {
    securityContext = securityContextFromYaml(
      loadYaml(file.readAsStringSync())
    );
  }
  void saveTests(io.Directory targetDirectory) {
    final testsDir = targetDirectory.path;
    final gzip = io.gzip;
    int testNumber = 1;
    int testsCount = 0;
    for (final testCase in testCases) {
      final stdin = testCase.stdinData;
      final stdout = testCase.stdoutReference;
      final stderr = testCase.stderrReference;
      final buildBundle = testCase.buildDirectoryBundle;
      final runtimeBundle = testCase.directoryBundle;
      final args = testCase.commandLineArguments;
      if (stdin.name.isNotEmpty) {
        io.File('$testsDir/${stdin.name}').writeAsBytesSync(
            gzip.decode(stdin.data));
      }
      if (stdout.name.isNotEmpty) {
        io.File('$testsDir/${stdout.name}').writeAsBytesSync(
            gzip.decode(stdout.data));
      }
      if (stderr.name.isNotEmpty) {
        io.File('$testsDir/${stderr.name}').writeAsBytesSync(
            gzip.decode(stderr.data));
      }
      if (runtimeBundle.name.isNotEmpty) {
        io.File('$testsDir/${runtimeBundle.name}').writeAsBytesSync(runtimeBundle.data);
      }
      if (buildBundle.name.isNotEmpty) {
        io.File('$testsDir/${buildBundle.name}').writeAsBytesSync(buildBundle.data);
      }
      if (args.isNotEmpty) {
        String testBaseName = _testNumberToString(testNumber);
        io.File('$testsDir/$testBaseName.args').writeAsStringSync(args);
      }
      testNumber ++;
      testsCount ++;
    }
    io.File("$testsDir/.tests_count").writeAsStringSync('$testsCount\n');
  }
  static String _testNumberToString(int number) {
    String result = '$number';
    while (result.length < 3) {
      result = '0$result';
    }
    return result;
  }

}

extension FileExtension on File {
  void save(io.Directory targetDirectory) {
    if (name.isEmpty) {
      return;
    }
    targetDirectory.createSync(recursive: true);
    final fullPath = '${targetDirectory.path}/$name';
    io.File(fullPath).createSync(recursive: true);
    io.File(fullPath).writeAsBytesSync(data);
  }
  
  static File fromFile(io.File sourceFile, {
    String name = '',
    String description = '',
    int? permissions,
  }) {
    name = name.isEmpty? sourceFile.path : name;
    final data = sourceFile.readAsBytesSync();
    final permissionsMask = int.parse('777', radix: 8);
    int resolvedPermissions;
    if (permissions != null) {
      resolvedPermissions = permissions & permissionsMask;
    }
    else {
      final mode = sourceFile.statSync().mode;
      resolvedPermissions = mode & permissionsMask;
    }
    return File(
      name: name,
      data: data,
      permissions: resolvedPermissions,
      description: description,
    );
  }

}

extension FileSetExtension on FileSet {
  void saveAll(io.Directory targetDirectory) {
    for (final file in files) {
      file.save(targetDirectory);
    }
  }

  static const String permissionsFileName = '.permissions';

  static FileSet fromDirectory(io.Directory sourceDirectory, {
    bool recursive = false, String namePrefix = '',
  }) {
    final entries = sourceDirectory.listSync(recursive: recursive);
    final directoryPath = sourceDirectory.path;
    List<File> files = [];
    final permissions = readPermissionsFile(
      '${sourceDirectory.path}/$permissionsFileName'
    );
    for (final entry in entries) {
      if (entry is io.File) {
        final fullPath = entry.path;
        String relativePath = fullPath.substring(directoryPath.length);
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        final fileName = path.normalize('$namePrefix$relativePath');
        int? filePermissions;
        if (permissions.containsKey(relativePath)) {
          filePermissions = permissions[relativePath]!;
        }
        files.add(FileExtension.fromFile(entry, name: fileName, permissions: filePermissions));
      }
    }
    return FileSet(files: files).deepCopy();
  }

  static Map<String,int> readPermissionsFile(String permissionsPath) {
    Map<String,int> result = {};
    final permissionsMask = int.parse('777', radix: 8);
    final permissionsFile = io.File(permissionsPath);
    if (permissionsFile.existsSync()) {
      final lines = permissionsFile.readAsLinesSync();
      for (final line in lines) {
        if (line.trim().startsWith('#') || line.trim().isEmpty) {
          continue;
        }
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) {
          continue;
        }
        final fileName = parts[0];
        int? mode = int.tryParse(parts[1], radix: 8);
        if (mode != null) {
          result[fileName] = mode & permissionsMask;
        }
      }
    }
    return result;
  }

  File toTarGzBundle(String fileName) {
    final archive = Archive();
    for (final file in files) {
      final fileData = Uint8List.fromList(file.data);
      final archiveFile = ArchiveFile(file.name, file.data.length, fileData);
      archiveFile.mode = file.permissions;
      archive.addFile(archiveFile);
    }
    final tarData = TarEncoder().encode(archive);
    final gzData = GZipEncoder().encode(tarData)!.toList();
    return File(
      name: fileName,
      data: gzData,
    ).deepCopy();
  }

}

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