// ignore_for_file: unused_field

import 'generated/yajudge.pb.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:protobuf/protobuf.dart';
import 'model_utils.dart';
import 'dart:io' as io;

const courseReloadInterval = Duration(seconds: 10);
const problemReloadInterval = Duration(seconds: 10);

class CourseLoadError extends Error {
  final String message;
  final String relatedFileName;
  dynamic underlyingError;
  CourseLoadError(this.message, this.relatedFileName, [this.underlyingError]);

  @override
  String toString() {
    String msg = "while processing $relatedFileName: $message";
    if (underlyingError != null) {
      msg += " [$underlyingError]";
    }
    return msg;
  }
}

class CourseLoader {
  final String coursesRootPath;
  final String separateProblemsRootPath;
  final String courseId;

  CourseDataCacheItem courseCache = CourseDataCacheItem();
  Map<String, ProblemDataCacheItem> problemsCache = {};

  GradingLimits _defaultLimits = GradingLimits();
  SecurityContext _defaultSecurityContext = SecurityContext();
  List<CodeStyle> _codeStyles = [];
  int _maxSubmissionsPerHour = 10;
  int _maxSubmissionFileSize = 1 * 1024 * 1024;

  Section _section = Section();
  YamlMap _sectionMap = YamlMap();

  Lesson _lesson = Lesson();
  YamlMap _lessonMap = YamlMap();

  TextReading _textReading = TextReading();

  final DateTime _softDeadLine = DateTime.fromMicrosecondsSinceEpoch(0);
  final DateTime _hardDeadLine = DateTime.fromMicrosecondsSinceEpoch(0);

  CourseLoader({required this.courseId, required this.coursesRootPath, required this.separateProblemsRootPath});


  CourseData courseData() {
    if (requiresToReloadCourse()) {
      loadCourse();
    }
    if (courseCache.loadError != null) {
      throw courseCache.loadError!;
    }
    else {
      return courseCache.data!;
    }
  }

  ProblemData problemData(String problemId) {
    if (requiresToReloadProblem(problemId)) {
      problemsCache[problemId] = ProblemDataCacheItem();
      ProblemData problemData = _loadProblemData(true, problemId);
      problemsCache[problemId]!.data = problemData;
      problemsCache[problemId]!.lastChecked = DateTime.now();
    }
    if (problemsCache[problemId]!.loadError != null) {
      throw problemsCache[problemId]!.loadError!;
    }
    else {
      return problemsCache[problemId]!.data!;
    }
  }

  DateTime courseLastModified() {
    if (requiresToReloadCourse()) {
      try {
        loadCourse();
      } catch (err) {
        courseCache.loadError = err;
      }
    }
    if (courseCache.loadError != null) {
      throw courseCache.loadError!;
    }
    else {
      return courseCache.lastModified!;
    }
  }

  DateTime problemLastModified(String problemId) {
    if (requiresToReloadProblem(problemId)) {
      problemsCache[problemId] = ProblemDataCacheItem(
        lastChecked: DateTime.now(),
        lastModified: DateTime.fromMillisecondsSinceEpoch(0),
      );
      try {
        problemsCache[problemId]!.data = _loadProblemData(true, problemId);
      } catch (err) {
        problemsCache[problemId]!.loadError = err;
      }
    }
    if (problemsCache[problemId]!.loadError != null) {
      throw problemsCache[problemId]!.loadError!;
    }
    else {
      return problemsCache[problemId]!.lastModified!;
    }
  }

  bool requiresToReloadCourse() {
    if (courseCache.lastChecked==null || courseCache.data==null || courseCache.loadError!=null) {
      return true;
    }
    DateTime lastChecked = courseCache.lastChecked!;
    DateTime nextCheck = lastChecked.add(problemReloadInterval);
    DateTime now = DateTime.now();
    return now.millisecondsSinceEpoch >= nextCheck.millisecondsSinceEpoch;
  }

  bool requiresToReloadProblem(String problemId) {
    if (!problemsCache.containsKey(problemId)) {
      return true;
    }
    ProblemDataCacheItem item = problemsCache[problemId]!;
    if (item.lastChecked==null || item.data==null || item.loadError!=null) {
      return true;
    }
    DateTime lastChecked = item.lastChecked!;
    DateTime nextCheck = lastChecked.add(problemReloadInterval);
    DateTime now = DateTime.now();
    return now.millisecondsSinceEpoch >= nextCheck.millisecondsSinceEpoch;
  }

  void loadCourse() {
    _sectionMap = YamlMap();
    _lessonMap = YamlMap();
    courseCache.lastModified = DateTime.fromMillisecondsSinceEpoch(0);

    final courseFile = io.File('$rootPath/course.yaml');
    updateCourseLastModified(courseFile);
    YamlMap courseMap = loadYaml(courseFile.readAsStringSync());
    String description = courseMap['description'] is String? courseMap['description'] : '';
    _codeStyles = _loadCourseCodeStyles('');
    final defaultLimitsFile = io.File('${problemPath('')}/default-limits.yaml');
    if (defaultLimitsFile.existsSync()) {
      updateCourseLastModified(defaultLimitsFile);
      YamlMap limitsMap = loadYaml(defaultLimitsFile.readAsStringSync());
      _defaultLimits = GradingLimitsExtension.fromYaml(limitsMap);
    }
    final submissionPropertiesFile = io.File('${problemPath('')}/submission-properties.yaml');
    if (submissionPropertiesFile.existsSync()) {
      updateCourseLastModified(submissionPropertiesFile);
      YamlMap propsMap = loadYaml(submissionPropertiesFile.readAsStringSync());
      if (propsMap['max_submissions_per_hour'] is int) {
        _maxSubmissionsPerHour = propsMap['max_submissions_per_hour'];
      }
      if (propsMap['max_submission_file_size'] is int) {
        _maxSubmissionFileSize = propsMap['max_submission_file_size'];
      }
    }
    final securityContextFile = io.File('${problemPath('')}/security-context.yaml');
    if (securityContextFile.existsSync()) {
      updateCourseLastModified(securityContextFile);
      YamlMap propsMap = loadYaml(securityContextFile.readAsStringSync());
      _defaultSecurityContext = securityContextFromYaml(propsMap);
    }
    bool hasSections = false;
    if (courseMap['sections'] != null) {
      hasSections = true;
    }
    List<Section> sectionsList = [];
    if (hasSections) {
      YamlList sections = courseMap['sections'];
      for (String entry in sections) {
        _section = Section(id: entry);
        final sectionFile = io.File('$rootPath/$entry/section.yaml');
        updateCourseLastModified(sectionFile);
        _sectionMap = loadYaml(sectionFile.readAsStringSync());
        _loadCourseSection();
        sectionsList.add(_section);
      }
    } else {
      _section = Section().deepCopy();
      _sectionMap = courseMap;
      _loadCourseSection();
      _section.name = '';
      _section.description = '';
      sectionsList.add(_section);
    }
    courseCache.data = CourseData(
      id: courseId,
      description: description,
      maxSubmissionFileSize: _maxSubmissionFileSize,
      maxSubmissionsPerHour: _maxSubmissionsPerHour,
      codeStyles: _codeStyles,
      defaultLimits: _defaultLimits,
      sections: sectionsList,
    );
    courseCache.lastChecked = DateTime.now();
    courseCache.loadError = null;
  }

  void _loadCourseSection() {
    String title = _sectionMap['title'] is String? _sectionMap['title'] : '';
    String description = _sectionMap['description'] is String? _sectionMap['description'] : '';
    List<Lesson> lessonsList = [];
    YamlList lessons = _sectionMap['lessons'];
    for (String entry in lessons) {
      final lessonFile = io.File('$rootPath/${_section.id}/$entry/lesson.yaml');
      if (!lessonFile.existsSync()) {
        throw CourseLoadError('file not found', lessonFile.path);
      }
      updateCourseLastModified(lessonFile);
      try {
        _lessonMap = loadYaml(lessonFile.readAsStringSync());
      }
      catch (error) {
        throw CourseLoadError('cant parse yaml', lessonFile.path, error);
      }
      _lesson = Lesson(id: entry);
      _loadCourseLesson();
      lessonsList.add(_lesson);
    }
    _section = _section.deepCopy();
    _section.name = title;
    _section.description = description;
    _section.lessons.addAll(lessonsList);
  }

  void _loadCourseLesson() {
    final title = _lessonMap['title'] is String? _lessonMap['title'] : '';
    final description = _lessonMap['description'] is String? _lessonMap['description'] : '';
    List<TextReading> readingsList = [];
    List<ProblemData> problemsList = [];
    List<ProblemMetadata> problemsMetadataList = [];
    if (_lessonMap['readings'] is YamlList) {
      YamlList readings = _lessonMap['readings'];
      for (String entry in readings) {
        _textReading = TextReading(id: entry);
        _loadTextReading();
        readingsList.add(_textReading);
      }
    }
    else if (_lessonMap['readings'] is String) {
      List<String> readings = _lessonMap['readings'].toString().split(' ');
      for (String entry in readings) {
        if (entry.isNotEmpty) {
          _textReading = TextReading(id: entry);
          _loadTextReading();
          readingsList.add(_textReading);
        }
      }
    }
    else {
      final readmeMd = io.File('$rootPath/${_section.id}/${_lesson.id}/README.md');
      if (readmeMd.existsSync()) {
        _textReading = TextReading(id: _lesson.id);
        _loadTextReading(_lesson.id, readmeMd.path);
        readingsList.add(_textReading);
      }
    }
    if (_lessonMap['problems'] is YamlList) {
      YamlList problems = _lessonMap['problems'];
      for (dynamic entry in problems) {
        ProblemData problemData;
        ProblemMetadata problemMetadata;
        String problemId;
        if (entry is String) {
          problemId = entry;
          problemMetadata = ProblemMetadata(id: problemId, fullScoreMultiplier: 1.0);
        }
        else if (entry is YamlMap) {
          problemId = entry['id'];
          bool blocksNext = entry['blocks_next'] is bool? entry['blocks_next'] : false;
          bool skipCodeReview = entry['no_review'] is bool? entry['no_review'] : false;
          bool skipSolutionDefence = entry['no_defence'] is bool? entry['no_defence'] : false;
          double fullScore = entry['full_score'] is double? entry['full_score'] : 1.0;
          problemMetadata = ProblemMetadata(
            id: problemId,
            blocksNextProblems: blocksNext,
            fullScoreMultiplier: fullScore,
            skipCodeReview: skipCodeReview,
            skipSolutionDefence: skipSolutionDefence,
          );
        } else {
          throw Exception('problems element in not a string or map');
        }
        problemsCache[problemId] = ProblemDataCacheItem();
        problemData = _loadProblemData(false, problemId);
        problemsList.add(problemData);
        problemsMetadataList.add(problemMetadata);
      }
    }
    _lesson = _lesson.deepCopy();
    _lesson.name = title;
    _lesson.description = description;
    _lesson.problems.addAll(problemsList);
    _lesson.problemsMetadata.addAll(problemsMetadataList);
    _lesson.readings.addAll(readingsList);
  }

  ProblemData _loadProblemData(bool withGradingData, String problemId) {
    final problemYamlFile = io.File('${problemPath(problemId)}/problem.yaml');
    if (!problemYamlFile.existsSync()) {
      throw Exception('file not exists: ${problemYamlFile.path}');
    }
    updateCourseLastModified(problemYamlFile);
    if (withGradingData) {
      updateProblemLastModified(problemId, problemYamlFile);
    }
    YamlMap data = loadYaml(problemYamlFile.readAsStringSync());
    String statementFileName = data['statement'] is String? data['statement'] : 'statement.md';
    final statementFile = io.File('${problemPath(problemId)}/$statementFileName');
    if (!statementFileName.endsWith('.md')) {
      throw UnimplementedError('statements other than Markdown (.md) are not supported: ${statementFile.path}');
    }
    String title = data['title'] is String? data['title'] : problemId;
    String uniqueId = data['unique_id'] is String? data['unique_id'] : problemId;
    String statement = statementFile.readAsStringSync();
    int maxSubmissionsPerHour = data['max_submissions_per_hour'] is int
        ? data['max_submissions_per_hour'] : _maxSubmissionsPerHour;
    int maxSubmissionFileSize = data['max_submission_file_size'] is int
        ? data['max_submission_file_size'] : _maxSubmissionFileSize;
    List<File> solutionFiles = [];
    String solutionTemplateName = '';
    String solutionTemplateFileName = '';
    if (data['solution_files'] is YamlList) {
      YamlList yamlList = data['solution_files'];
      for (String entry in yamlList) {
        solutionFiles.add(File(name: entry));
      }
    }
    else {
      final problemDir = io.Directory(problemPath(problemId));
      final problemIdLastPart = problemId.split(':').last;
      final problemIdAllParts = problemId.replaceAll(':', '-');
      List<List<String>> candidates = [];
      for (final entry in problemDir.listSync(recursive: false, followLinks: true)) {
        final entryPath = entry.path;
        final baseName = path.basenameWithoutExtension(entryPath);
        final fileName = path.basename(entryPath);
        final fileSuffix = path.extension(fileName);
        if (baseName == problemIdLastPart || baseName == problemIdAllParts) {
          candidates.add([fileName, fileName]);
        }
        else if (baseName == 'template') {
          candidates.add(['$problemIdAllParts$fileSuffix', fileName]);
        }
      }
      if (candidates.length > 1) {
        throw Exception('ambiguous solution template file in $problemId. Set explicit solution_files entry in problem.yaml');
      }
      else if (candidates.isEmpty) {
        throw Exception('no solution template file in $problemId. Set explicit solution_files entry in problem.yaml');
      }
      solutionTemplateName = candidates.single.first;
      solutionTemplateFileName = candidates.single.last;
      solutionFiles.add(File(name: solutionTemplateName));
    }
    FileSet publicFiles = FileSet();
    if (data['public_files'] is YamlList) {
      YamlList yamlList = data['public_files'];
      publicFiles = _loadFileSet(problemId, yamlList, true, false);
    }
    else if (solutionTemplateName.isNotEmpty) {
      final solutionTemplateFile = io.File('${problemPath(problemId)}/$solutionTemplateFileName');
      final templateData = solutionTemplateFile.readAsBytesSync();
      final description = 'Шаблон решения';
      updateCourseLastModified(solutionTemplateFile);
      publicFiles = FileSet(files: [File(
        name: solutionTemplateName,
        data: templateData,
        description: description,
      )]);
    }
    GradingOptions gradingOptions;
    if (withGradingData) {
      gradingOptions = _loadProblemGradingOptions(problemId, publicFiles);
    }
    else {
      gradingOptions = GradingOptions();
    }
    return ProblemData(
      id: problemId,
      uniqueId: uniqueId,
      title: title,
      solutionFiles: FileSet(files: solutionFiles),
      statementFiles: publicFiles,
      statementText: statement,
      statementContentType: 'text/markdown',
      gradingOptions: gradingOptions,
      maxSubmissionsPerHour: maxSubmissionsPerHour,
      maxSubmissionFileSize: maxSubmissionFileSize,
    );
  }

  FileSet _loadFileSet(String problemId, YamlList yamlList, bool updateCourseCache, bool updateProblemCache) {
    List<File> filesList = [];
    for (dynamic entry in yamlList) {
      String description = '';
      String name;
      String src;
      if (entry is YamlMap) {
        YamlMap yamlMap = entry;
        name = yamlMap['name'];
        src = yamlMap['src'] is String? yamlMap['src'] : name;
        description = yamlMap['description'] is String? yamlMap['description'] : '';
      }
      else {
        name = src = entry.toString();
      }
      final file = io.File('${problemPath(problemId)}/$src');
      if (updateCourseCache) {
        updateCourseLastModified(file);
      }
      if (updateProblemCache) {
        updateProblemLastModified(problemId, file);
      }
      List<int> data = file.readAsBytesSync();
      filesList.add(File(name: name, description: description, data: data));
    }
    return FileSet(files: filesList);
  }

  GradingOptions _loadProblemGradingOptions(String problemId, FileSet publicFiles) {
    final problemYamlFile = io.File('${problemPath(problemId)}/problem.yaml');
    updateCourseLastModified(problemYamlFile);
    updateProblemLastModified(problemId, problemYamlFile);
    YamlMap data = loadYaml(problemYamlFile.readAsStringSync());
    String archValue = data['arch'] is String? data['arch'] : 'any';
    Arch arch = _parseArch(archValue);
    final gradingPlatform = GradingPlatform(arch: arch);
    String checker = data['checker'] is String? data['checker'] : 'text';
    String checkerOpts = data['checker_options'] is String? data['checker_options'] : '';
    String customCheckerName = data['custom_checker'] is String? data['custom_checker'] : '';
    String interactorName = data['interactor'] is String? data['interactor'] : '';
    String coprocessName = data['coprocess'] is String? data['coprocess'] : '';
    String testsGeneratorName = data['tests_generator'] is String? data['tests_generator'] : '';
    String compileOptions = data['compile_options'] is String? data['compile_options'] : '';
    String linkOptions = data['link_options'] is String? data['link_options'] : '';
    bool disableValgrind = data['disable_valgrind'] is bool? data['disable_valgrind'] : false;
    List<String> disableSanitizers = [];
    if (data['disable_sanitizers'] is YamlList) {
      YamlList yamlList = data['disable_sanitizers'];
      for (final entry in yamlList) {
        String disabledSanitizerName = entry.toString();
        disableSanitizers.add(disabledSanitizerName);
      }
    }
    else if (data['disable_sanitizers'] is String) {
      String line = data['disable_sanitizers'];
      disableSanitizers = line.split(' ');
    }
    File customChecker = File();
    if (customCheckerName.isNotEmpty) {
      final checkerFile = io.File('${problemPath(problemId)}/$customCheckerName');
      updateProblemLastModified(problemId, checkerFile);
      customChecker = File(name: customCheckerName, data: checkerFile.readAsBytesSync());
    }
    File customInteractor = File();
    if (interactorName.isNotEmpty) {
      final interactorFile = io.File('${problemPath(problemId)}/$interactorName');
      updateProblemLastModified(problemId, interactorFile);
      customInteractor = File(name: interactorName, data: interactorFile.readAsBytesSync());
    }
    File testsGenerator = File();
    if (testsGeneratorName.isNotEmpty) {
      final generatorFile = io.File('${problemPath(problemId)}/$testsGeneratorName');
      updateProblemLastModified(problemId, generatorFile);
      testsGenerator = File(name: testsGeneratorName, data: generatorFile.readAsBytesSync());
    }
    File coprocess = File();
    if (coprocessName.isNotEmpty) {
      final coprocessFile = io.File('${problemPath(problemId)}/$coprocessName');
      updateProblemLastModified(problemId, coprocessFile);
      coprocess = File(name: coprocessName, data: coprocessFile.readAsBytesSync());
    }
    FileSet privateFiles = FileSet();
    if (data['private_files'] is YamlList) {
      YamlList yamlList = data['private_files'];
      privateFiles = _loadFileSet(problemId, yamlList, false, true);
    }
    GradingLimits limits = GradingLimits();
    if (data['limits'] is YamlMap) {
      YamlMap yamlMap = data['limits'];
      limits = GradingLimitsExtension.fromYaml(yamlMap);
    }
    SecurityContext securityContext = SecurityContext();
    if (data['security_context'] is YamlMap) {
      YamlMap yamlMap = data['security_context'];
      securityContext = securityContextFromYaml(yamlMap);
    }
    List<TestCase> testCases = _loadProblemTestCases(problemId);
    final codeStyles = _loadCourseCodeStyles(problemId);
    return GradingOptions(
      platformRequired: gradingPlatform,
      standardChecker: checker,
      standardCheckerOpts: checkerOpts,
      customChecker: customChecker,
      interactor: customInteractor,
      coprocess: coprocess,
      codeStyles: codeStyles,
      extraBuildFiles: FileSet(files: publicFiles.files + privateFiles.files),
      testCases: testCases,
      extraCompileOptions: compileOptions.split(' '),
      extraLinkOptions: linkOptions.split(' '),
      limits: limits,
      securityContext: securityContext,
      disableSanitizers: disableSanitizers,
      disableValgrind: disableValgrind,
      testsGenerator: testsGenerator,
    );
  }

  List<CodeStyle> _loadCourseCodeStyles(String problemId) {
    final codeStylesFile = io.File('${problemPath('')}/code-styles.yaml');
    List<CodeStyle> codeStyles = [];
    if (codeStylesFile.existsSync()) {
      updateCourseLastModified(codeStylesFile);
      if (problemId.isNotEmpty) {
        updateProblemLastModified(problemId, codeStylesFile);
      }
      YamlMap codeStylesMap = loadYaml(codeStylesFile.readAsStringSync());
      for (final entry in codeStylesMap.entries) {
        String suffix = entry.key;
        String styleFileName = entry.value;
        final styleFile = io.File('${problemPath('')}/$styleFileName');
        List<int> styleFileData = styleFile.readAsBytesSync();
        updateCourseLastModified(styleFile);
        codeStyles.add(CodeStyle(
          sourceFileSuffix: suffix,
          styleFile: File(name: styleFileName, data: styleFileData),
        ));
      }
    }
    return codeStyles;
  }

  List<TestCase> _loadProblemTestCases(String problemId) {
    final testsDir = io.Directory('${problemPath(problemId)}/tests');
    List<TestCase> result = [];
    final gzip = io.gzip;
    if (testsDir.existsSync()) {
      for (int i = 1; i <= 999; i++) {
        String base;
        if (i < 10) {
          base = '00$i';
        } else if (i < 100) {
          base = '0$i';
        } else {
          base = '$i';
        }
        io.File tgzFile = io.File('${testsDir.path}/$base.tgz');
        io.File datFile = io.File('${testsDir.path}/$base.dat');
        io.File ansFile = io.File('${testsDir.path}/$base.ans');
        io.File infFile = io.File('${testsDir.path}/$base.inf');
        io.File errFile = io.File('${testsDir.path}/$base.err');
        File tgz = File();
        File dat = File();
        File ans = File();
        File err = File();
        String params = '';
        bool anyTestExists = false;
        if (tgzFile.existsSync()) {
          tgz = File(name: '$base.tgz', data: tgzFile.readAsBytesSync());
          updateProblemLastModified(problemId, tgzFile);
          anyTestExists = true;
        }
        if (datFile.existsSync()) {
          dat = File(name: '$base.dat', data: gzip.encode(datFile.readAsBytesSync()));
          updateProblemLastModified(problemId, datFile);
          anyTestExists = true;
        }
        if (ansFile.existsSync()) {
          ans = File(name: '$base.ans', data: gzip.encode(ansFile.readAsBytesSync()));
          updateProblemLastModified(problemId, ansFile);
          anyTestExists = true;
        }
        if (errFile.existsSync()) {
          err = File(name: '$base.err', data: gzip.encode(errFile.readAsBytesSync()));
          updateProblemLastModified(problemId, errFile);
          anyTestExists = true;
        }
        if (infFile.existsSync()) {
          String line = infFile.readAsStringSync().trim();
          updateProblemLastModified(problemId, infFile);
          int equalPos = line.indexOf('=');
          params = line.substring(equalPos+1).trim();
          anyTestExists = true;
        }
        if (anyTestExists) {
          final testCase = TestCase(
            stdinData: dat,
            stderrReference: err,
            stdoutReference: ans,
            commandLineArguments: params,
            directoryBundle: tgz,
          );
          result.add(testCase);
        } else {
          break;
        }
      }
    }
    return result;
  }

  Arch _parseArch(String value) {
    Arch arch = Arch.ARCH_ANY;
    value = value.toLowerCase().trim();
    switch (value) {
      case 'arm':
      case 'arm32':
        arch = Arch.ARCH_ARMV7;
        break;
      case 'arm64':
      case 'aarch64':
        arch = Arch.ARCH_AARCH64;
        break;
      case 'x86_64':
      case 'x86-64':
      case 'x64':
      case 'amd64':
      case 'ia64':
        arch = Arch.ARCH_X86_64;
        break;
      case 'x86':
      case 'i386':
      case 'i686':
      case 'x86-32':
      case 'ia32':
        arch = Arch.ARCH_X86;
        break;
    }
    return arch;
  }

  void _loadTextReading([String readingId = '', String readingFilePath = '']) {
    if (readingId.isEmpty) {
      readingId = _textReading.id;
    }
    if (readingFilePath.isEmpty) {
      readingFilePath = '$rootPath/${_section.id}/${_lesson.id}/${_textReading.id}';
    }
    final readingFile = io.File(readingFilePath);
    updateCourseLastModified(readingFile);
    if (!readingFile.path.endsWith('.md')) {
      throw UnimplementedError('only markdown (.md) text readings supported yet');
    }
    String content = readingFile.readAsStringSync();
    List<String> lines = content.split('\n');
    String title = '';
    for (String line in lines) {
      line = line.trimLeft();
      if (line.startsWith('#') && !line.startsWith('##')) {
        String titleCandidate = line.substring(1).trim();
        if (titleCandidate.isNotEmpty) {
          title = titleCandidate;
          break;
        }
      }
    }
    List<File> resources = [];
    final rxResourceLink = RegExp(r'\[.*\]\((.+)\)');
    for (final RegExpMatch match in rxResourceLink.allMatches(content)) {
      String resourceName = match.group(1)!;
      final resourceFile = io.File('$rootPath/${_section.id}/${_lesson.id}/$resourceName');
      if (resourceFile.existsSync()) {
        updateCourseLastModified(resourceFile);
        resources.add(File(name: resourceName, data: resourceFile.readAsBytesSync()));
      }
    }
    _textReading = TextReading(
      id: readingId,
      contentType: 'text/markdown',
      title: title,
      resources: FileSet(files: resources),
      data: content,
    );
  }

  String get rootPath {
    return path.normalize(path.absolute('$coursesRootPath/$courseId/'));
  }

  String problemPath(String problemId) {
    final problemRelativePath = problemId.replaceAll(':', '/');
    return path.normalize(path.absolute('$separateProblemsRootPath/$problemRelativePath/'));
  }

  void updateCourseLastModified(io.File file) {
    if (courseCache.lastModified == null) {
      return;
    }
    final fileLastModified = file.lastModifiedSync();
    final cacheLastModified = courseCache.lastModified!;
    if (fileLastModified.millisecondsSinceEpoch > cacheLastModified.millisecondsSinceEpoch) {
      courseCache.lastModified = file.lastModifiedSync();
    }
  }

  void updateProblemLastModified(String problemId, io.File file) {
    final fileLastModified = file.lastModifiedSync();
    final cacheLastModified = problemsCache[problemId]!.lastModified!;
    if (fileLastModified.millisecondsSinceEpoch > cacheLastModified.millisecondsSinceEpoch) {
      problemsCache[problemId]!.lastModified = fileLastModified;
    }
  }

}
