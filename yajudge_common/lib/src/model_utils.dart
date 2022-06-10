import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';
import './generated/yajudge.pb.dart';
import 'dart:io' as io;

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

ExecutableTarget executableTargetFromString(dynamic conf) {
  String c = '';
  if (conf is String) {
    c = conf.toLowerCase().replaceAll('-', '_');
  }
  switch (c) {
    case 'bash_script':
    case 'bash':
    case 'shell':
      return ExecutableTarget.BashScript;
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
    case 'qemu_image_x86':
    case 'qemu_x86':
      return ExecutableTarget.QemuX86DiskImage;
    case 'qemu_image_arm':
    case 'qemu_arm':
      return ExecutableTarget.QemuArmDiskImage;
    default:
      return ExecutableTarget.AutodetectExecutable;
  }
}

String executableTargetToString(ExecutableTarget target) {
  switch (target) {
    case ExecutableTarget.AutodetectExecutable:
      return 'auto';
    case ExecutableTarget.BashScript:
      return 'bash';
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
    case ExecutableTarget.QemuArmDiskImage:
      return 'qemu-arm';
    case ExecutableTarget.QemuX86DiskImage:
      return 'qemu-x86';
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


  void saveToPlainFiles(io.Directory targetDirectory) {
    final dirPath = targetDirectory.path;
    _saveBuild(io.File('$dirPath/$buildName'));
    _saveBuildProperties(io.File('$dirPath/$buildPropertiesName'));
    _saveTarget(io.File('$dirPath/$targetName'));
    _saveTargetProperties(io.File('$dirPath/$targetName'));
    _saveCodeStyles(targetDirectory);
    _saveChecker(targetDirectory);
    _saveInteractor(targetDirectory);
    _saveCoprocess(targetDirectory);
    _saveTestsGenerator(targetDirectory);
    _saveLimits(io.File('$dirPath/$limitsName'));
    _saveSecurityContext(io.File('$dirPath/$securityContextName'));
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
    return result;
  }

  _saveBuild(io.File file) => file.writeAsStringSync(buildSystemToString(buildSystem));
  _loadBuild(io.File file) {
    buildSystem = buildSystemFromString(
        file.existsSync() ? file.readAsStringSync().trim() : null
    );
  }
  _saveBuildProperties(io.File file) => file.writeAsStringSync(propertiesToYaml(buildProperties));
  _loadBuildProperties(io.File file) {
    buildProperties.addAll(propertiesFromYaml(
        file.existsSync() ? loadYaml(file.readAsStringSync()) : null
    ));
  }
  _saveTarget(io.File file) => file.writeAsStringSync(executableTargetToString(executableTarget));
  _loadTarget(io.File file) {
    executableTarget = executableTargetFromString(
      file.existsSync() ? file.readAsStringSync().trim() : null
    );
  }
  _saveTargetProperties(io.File file) => file.writeAsStringSync(propertiesToYaml(targetProperties));
  _loadTargetProperties(io.File file) {
    targetProperties.addAll(propertiesFromYaml(
        file.existsSync() ? loadYaml(file.readAsStringSync()) : null
    ));
  }
  _saveCodeStyles(io.Directory targetDirectory) {
    for (final codeStyle in codeStyles) {
      final styleFile = codeStyle.styleFile;
      final codeStyleFileName = styleFile.name;
      final suffix = codeStyle.sourceFileSuffix.replaceAll('.', '');
      io.File('${targetDirectory.path}/$codeStyleFileName').writeAsBytesSync(styleFile.data);
      io.File('${targetDirectory.path}/$styleNamePrefix$suffix').writeAsStringSync(styleFile.name);
    }
  }
  _loadCodeStyles(io.Directory sourceDirectory) {
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
  _saveChecker(io.Directory targetDirectory) {
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
  _loadChecker(io.Directory sourceDirectory) {
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
  _saveInteractor(io.Directory targetDirectory) {
    if (interactor.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$interactorName').writeAsStringSync(interactor.name);
      io.File('${targetDirectory.path}/${interactor.name}').writeAsBytesSync(interactor.data);
    }
  }
  _loadInteractor(io.Directory sourceDirectory) {
    final interactorFile = io.File('${sourceDirectory.path}/$interactorName');
    if (interactorFile.existsSync()) {
      final interactorFileName = interactorFile.readAsStringSync().trim();
      final interactorData = io.File('${sourceDirectory.path}/$interactorFileName').readAsBytesSync();
      interactor = File(name: interactorFileName, data: interactorData);
    }
  }
  _saveCoprocess(io.Directory targetDirectory) {
    if (coprocess.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$coprocessName').writeAsStringSync(coprocess.name);
      io.File('${targetDirectory.path}/${coprocess.name}').writeAsBytesSync(coprocess.data);
    }
  }
  _loadCoprocess(io.Directory sourceDirectory) {
    final coprocessFile = io.File('${sourceDirectory.path}/$coprocessName');
    if (coprocessFile.existsSync()) {
      final coprocessFileName = coprocessFile.readAsStringSync().trim();
      final coprocessData = io.File('${sourceDirectory.path}/$coprocessFileName').readAsBytesSync();
      coprocess = File(name: coprocessFileName, data: coprocessData);
    }
  }
  _saveTestsGenerator(io.Directory targetDirectory) {
    if (testsGenerator.name.isNotEmpty) {
      io.File('${targetDirectory.path}/$testsGeneratorName').writeAsStringSync(testsGenerator.name);
      io.File('${targetDirectory.path}/${testsGenerator.name}').writeAsBytesSync(testsGenerator.data);
    }
  }
  _loadTestsGenerator(io.Directory sourceDirectory) {
    final testsGeneratorFile = io.File('${sourceDirectory.path}/$testsGeneratorName');
    if (testsGeneratorFile.existsSync()) {
      final testsGeneratorFileName = testsGeneratorFile.readAsStringSync().trim();
      final testsGeneratorData = io.File('${sourceDirectory.path}/$testsGeneratorFileName').readAsBytesSync();
      testsGenerator = File(name: testsGeneratorFileName, data: testsGeneratorData);
    }
  }
  _saveLimits(io.File file) => file.writeAsStringSync(limits.toYamlString());
  _loadLimits(io.File file) {
    GradingLimitsExtension.fromYaml(loadYaml(file.readAsStringSync()));
  }
  _saveSecurityContext(io.File file) =>
      file.writeAsStringSync(securityContextToYamlString(securityContext));
  _loadSecurityContext(io.File file) {
    securityContext = securityContextFromYaml(
      loadYaml(file.readAsStringSync())
    );
  }
  saveTests(io.Directory targetDirectory) {
    final testsDir = targetDirectory.path;
    final gzip = io.gzip;
    int testNumber = 1;
    int testsCount = 0;
    for (final testCase in testCases) {
      final stdin = testCase.stdinData;
      final stdout = testCase.stdoutReference;
      final stderr = testCase.stderrReference;
      final bundle = testCase.directoryBundle;
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
      if (bundle.name.isNotEmpty) {
        io.File('$testsDir/${bundle.name}').writeAsBytesSync(bundle.data);
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