import 'dart:io' as io;

import 'package:path/path.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:postgres/postgres.dart';
import 'package:tuple/tuple.dart';
import 'package:xml/xml.dart';
import 'package:yajudge_common/yajudge_common.dart';
import './service.dart';
import './user_management.dart';
import 'package:yaml/yaml.dart';

const CourseReloadInterval = Duration(seconds: 15);

class CourseDataCacheItem {
  final CourseData? data;
  final DateTime? lastModified;
  final DateTime? lastChecked;
  final GrpcError? loadError;

  CourseDataCacheItem({
    this.data,
    this.lastModified,
    this.lastChecked,
    this.loadError,
  });

}

class CourseManagementService extends CourseManagementServiceBase {

  final PostgreSQLConnection connection;
  final MasterService parent;
  late final String root;
  final Map<String, CourseDataCacheItem> cache = Map();

  CourseManagementService({
    required this.parent,
    required this.connection,
    required String root
  }): super() {
    if (isAbsolute(root)) {
      this.root = root;
    } else {
      String scriptPath = io.Platform.script.path;
      String relPath = normalize(scriptPath + '/../../' + root);
      this.root = relPath;
    }
  }

  @override
  Future<Course> cloneCourse(ServiceCall call, Course request) {
    // TODO: implement cloneCourse
    throw UnimplementedError();
  }

  @override
  Future<Course> createOrUpdateCourse(ServiceCall call, Course request) {
    // TODO: implement createOrUpdateCourse
    throw UnimplementedError();
  }

  @override
  Future<Nothing> deleteCourse(ServiceCall call, Course course) async {
    if (course.id == 0) {
      throw GrpcError.invalidArgument('course id required');
    }
    connection.query(
      'delete from courses where id=@id',
      substitutionValues: {
        'id': course.id.toInt()
      }
    );
    return Nothing();
  }

  @override
  Future<Course> enrollUser(ServiceCall call, Enroll request) async {
    User user = request.user;
    Course course = request.course;
    Role role = request.role;
    if (user.id==0 && user.email.isEmpty) {
      throw GrpcError.invalidArgument('user id or email required');
    } else if (user.id==0) {
      List<dynamic> rows = await connection.query(
        'select id from users where email=@email',
        substitutionValues: {'email': user.email}
      );
      List<dynamic> row = rows.first;
      user.id = Int64(row.first);
    }
    if (role == Role.ROLE_ANY) {
      throw GrpcError.invalidArgument('exact role required');
    }
    if (course.id==0 && course.name.isEmpty) {
      throw GrpcError.invalidArgument('course id or name required');
    } else if (course.id==0) {
      List<dynamic> rows = await connection.query(
          'select id from courses where name=@name',
          substitutionValues: {'name': course.name}
      );
      List<dynamic> row = rows.first;
      course.id = Int64(row.first);
    } else if (course.name.isEmpty) {
      List<dynamic> rows = await connection.query(
          'select name from courses where id=@id',
          substitutionValues: {'id': course.id.toInt()}
      );
      List<dynamic> row = rows.first;
      course.name = row.first;
    }
    await connection.query(
      'insert into enrollments(courses_id, users_id, role) values (@c,@u,@r)',
      substitutionValues: {
        'c': course.id.toInt(),
        'u': user.id.toInt(),
        'r': role.value,
      }
    );
    return course;
  }

  Tuple3<List<CodeStyle>, DateTime, GrpcError?> _getCourseCodeStyles(String courseId, YamlMap stylesMap) {
    List<CodeStyle> result = List.empty(growable: true);
    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    for (var item in stylesMap.entries) {
      String suffix = item.key;
      String entry = item.value;
      if (!suffix.startsWith('.')) {
        suffix = '.' + suffix;
      }
      String srcFileName = normalize(root + '/' + courseId + '/' + entry);
      io.File srcFile = io.File(srcFileName);
      if (!srcFile.existsSync()) {
        error = GrpcError.notFound('file not found: ' + srcFileName);
        break;
      }
      if (srcFile.lastModifiedSync().millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = srcFile.lastModifiedSync();
      }
      File file = File(name: entry);
      file.data = srcFile.readAsBytesSync();
      result.add(CodeStyle(sourceFileSuffix: suffix, styleFile: file));
    }
    return Tuple3(result, lastModified, error);
  }

  static String _guessContentType(String fileName) {
    if (fileName.endsWith('.md')) {
      return 'text/markdown';
    }
    else if (fileName.endsWith('.txt')) {
      return 'text/plain';
    }
    else if (fileName.endsWith('.html')) {
      return 'text/html';
    }
    return '';
  }

  static String _guessTitle(String contentType, String content) {
    if (contentType == 'text/markdown') {
      List<String> lines = content.split('\n');
      for (String line in lines) {
        line = line.trimLeft();
        if (line.startsWith('#') && !line.startsWith('##')) {
          String title = line.substring(1).trim();
          if (title.isNotEmpty) {
            return title;
          }
        }
      }
    }
    return '';
  }

  Tuple3<List<TextReading>, DateTime, GrpcError?> _getLessonReadings(String prefix, YamlMap parentMap) {
    List<TextReading> result = List.empty(growable: true);
    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    if (!parentMap.containsKey('readings')) {
      return Tuple3(result, lastModified, error);
    }
    YamlList readingNames = parentMap['readings'];
    for (String entry in readingNames) {
      String readingPrefix = prefix + '/' + entry;
      String readingFileName = root + '/' + readingPrefix;
      io.File readingFile = io.File(readingFileName);
      io.Directory readingDir = io.Directory(readingFileName);
      if (!readingFile.existsSync() && !readingDir.existsSync()) {
        error = GrpcError.notFound('file or directory not found: ' + readingFileName);
        return Tuple3(result, lastModified, error);
      }
      TextReading data = TextReading();
      if (readingDir.existsSync()) {
        // TODO read contents from subdirectory
      } else {
        data.id = basenameWithoutExtension(entry);
        data.contentType = _guessContentType(readingFileName);
        if (data.contentType.isEmpty) {
          error = GrpcError.internal('unknown content type for ' + readingFileName);
          return Tuple3(result, lastModified, error);
        }
        if (data.contentType.startsWith('text/')) {
          data.data = readingFile.readAsStringSync();
        }
        data.title = _guessTitle(data.contentType, data.data);
      }
      result.add(data);
    }
    return Tuple3(result, lastModified, error);
  }

  static bool _getBoolValueFromYaml(YamlMap m, String key, bool def) {
    if (!m.containsKey(key)) {
      return def;
    }
    dynamic value = m['key'];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      String sValue = value;
      sValue = sValue.toLowerCase().trim();
      return sValue == 'yes' || sValue == 'true' || sValue == '1';
    }
    if (value is int) {
      int iValue = value;
      return iValue > 0;
    }
    return def;
  }

  Tuple3<FileSet,DateTime,GrpcError?> _getFileset(String prefix, String problemId, YamlList entries, bool read) {
    FileSet fileset = FileSet();
    DateTime lastModified = DateTime.fromMillisecondsSinceEpoch(0);
    GrpcError? error;
    for (dynamic entry in entries) {
      String name = '';
      String src = '';
      String description = '';
      if (entry is String) {
        name = entry;
      } else {
        YamlMap dataMap = entry;
        if (dataMap.containsKey('name')) {
          name = dataMap['name'];
        }
        if (dataMap.containsKey('src')) {
          src = dataMap['src'];
        }
        if (dataMap.containsKey('description')) {
          description = dataMap['description'];
        }
      }
      if (read && src.isEmpty && name.isNotEmpty) {
        src = name;
      }
      if (name.isEmpty && src.isNotEmpty) {
        name = src;
      }
      if (name.isEmpty) {
        error = GrpcError.internal('file name is empty in problem ' + problemId);
        return Tuple3(fileset, lastModified, error);
      }
      File file = File(name: name, description: description);
      if (read) {
        String filePath = root + '/' + prefix + '/' + src;
        io.File content = io.File(filePath);
        if (!content.existsSync()) {
          error = GrpcError.internal('file not found ' + filePath);
          return Tuple3(fileset, lastModified, error);
        }
        file.data = content.readAsBytesSync();
        if (content.lastModifiedSync().millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
          lastModified = content.lastModifiedSync();
        }
      }
      fileset.files.add(file);
    }
    return Tuple3(fileset, lastModified, error);
  }

  Tuple3<ProblemData, DateTime, GrpcError?> _getProblemFromYaml(String prefix) {

    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    String yamlFileName = root + '/' + prefix + '/problem.yaml';
    String problemShortId = basenameWithoutExtension(prefix);
    io.File yamlFile = io.File(yamlFileName);
    if (!yamlFile.existsSync()) {
      error = GrpcError.notFound('file not found: ' + yamlFileName);
      return Tuple3(ProblemData(), lastModified, error);
    }
    lastModified = yamlFile.lastModifiedSync();
    String yamlContent = yamlFile.readAsStringSync();
    YamlMap dataMap = loadYaml(yamlContent, sourceUrl: Uri(path: yamlFileName));

    Arch arch = Arch.ARCH_ANY;
    OS os = OS.OS_POSIX;
    if (dataMap['arch'] is String) {
      String value = dataMap['arch'];
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
    }
    if (dataMap['os'] is String) {
      String value = dataMap['arch'];
      value = value.toLowerCase().trim();
      switch (value) {
        case 'any':
          os = OS.OS_ANY;
          break;
        case 'windows':
          os = OS.OS_WINDOWS;
          break;
        case 'linux':
          os = OS.OS_LINUX;
          break;
        case 'darwin':
        case 'macos':
          os = OS.OS_DARWIN;
          break;
        case 'bsd':
          os = OS.OS_BSD;
          break;
      }
    }
    GradingPlatform gradingPlatform = GradingPlatform(arch: arch, os: os);
    GradingOptions gradingOptions = GradingOptions(platformRequired: gradingPlatform);
    ProblemData data = ProblemData(id: problemShortId, gradingOptions: gradingOptions);

    if (!dataMap.containsKey('statement')) {
      error = GrpcError.internal('no statement in ' + yamlFileName);
      return Tuple3(data, lastModified, error);
    }
    String statementFileName = root + '/' + prefix + '/' + dataMap['statement'];
    io.File statementFile = io.File(statementFileName);
    if (!statementFile.existsSync()) {
      error = GrpcError.internal('file not exists ' + statementFileName);
      return Tuple3(data, lastModified, error);
    }
    final statementData = _getStatementData(statementFile);
    if (statementData.item3 != null) {
      return Tuple3(data, lastModified, statementData.item3);
    }
    data.statementText = statementData.item1;
    data.statementContentType = statementData.item2;
    if (statementFile.lastModifiedSync().millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
      lastModified = statementFile.lastModifiedSync();
    }
    if (dataMap.containsKey('unique_id')) {
      data.uniqueId = dataMap['unique_id'];
    }
    if (dataMap.containsKey('title')) {
      data.title = dataMap['title'];
    }
    if (dataMap.containsKey('solution_files')) {
      YamlList entries = dataMap['solution_files'];
      Tuple3<FileSet,DateTime,GrpcError?> fileset = _getFileset(prefix, problemShortId, entries, false);
      if (fileset.item3 != null) {
        error = fileset.item3;
        return Tuple3(data, lastModified, error);
      }
      if (fileset.item2.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = fileset.item2;
      }
      data.solutionFiles = fileset.item1;
    }
    if (dataMap.containsKey('public_files')) {
      YamlList entries = dataMap['public_files'];
      Tuple3<FileSet,DateTime,GrpcError?> fileset = _getFileset(prefix, problemShortId, entries, true);
      if (fileset.item3 != null) {
        error = fileset.item3;
        return Tuple3(data, lastModified, error);
      }
      if (fileset.item2.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = fileset.item2;
      }
      data.statementFiles = fileset.item1;
    }
    return Tuple3(data, lastModified, error);
  }

  Tuple3<String,String,GrpcError?> _getStatementData(io.File file) {
    String raw = file.readAsStringSync();
    if (file.path.endsWith('.md')) {
      return Tuple3(raw, 'text/markdown', null);
    } else if (file.path.endsWith('.txt')) {
      return Tuple3(raw, 'text/plain', null);
    } else if (file.path.endsWith('.xml')) {
      // ejudge statement format
      final xmlDocument = XmlDocument.parse(raw);
      final problemElement = xmlDocument.getElement('problem');
      if (problemElement == null) {
        return Tuple3('', '', GrpcError.internal('no problem element in ${file.path}'));
      }
      final statementElement = problemElement.getElement('statement');
      if (statementElement == null) {
        return Tuple3('', '', GrpcError.internal('no statement element in ${file.path}'));
      }
      final descriptionElement = statementElement.getElement('description');
      if (descriptionElement == null) {
        return Tuple3('', '', GrpcError.internal('no description element in ${file.path}'));
      }
      String content = descriptionElement.innerXml;
      return Tuple3(content, 'text/html', null);
    } else {
      return Tuple3('', '', GrpcError.internal('statement file type unknown: ${file.path}'));
    }
  }

  Tuple4<List<ProblemData>, List<ProblemMetadata>, DateTime, GrpcError?> _getLessonProblems(String prefix, YamlMap parentMap) {
    List<ProblemData> problems = List.empty(growable: true);
    List<ProblemMetadata> metas = List.empty(growable: true);
    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    if (!parentMap.containsKey('problems')) {
      return Tuple4(problems, metas, lastModified, error);
    }
    YamlList problemEntries = parentMap['problems'];
    for (dynamic entry in problemEntries) {
      String problemId = '';
      ProblemMetadata metadata = ProblemMetadata(fullScoreMultiplier: 1.0);
      if (entry is String) {
        problemId = entry;
      } else {
        YamlMap problemProps = entry;
        problemId = problemProps['id'];
        metadata.blocksNextProblems = _getBoolValueFromYaml(problemProps, 'blocks_next', false);
        metadata.skipCodeReview = _getBoolValueFromYaml(problemProps, 'no_review', false);
        metadata.skipSolutionDefence = _getBoolValueFromYaml(problemProps, 'no_defence', false);
        if (problemProps['full_score'] is double) {
          metadata.fullScoreMultiplier = problemProps['full_score'] as double;
        }
      }
      metadata.id = problemId;
      metas.add(metadata);
      String problemPrefix = prefix + '/' + problemId;
      String problemFileName = root + '/' + problemPrefix + '/problem.yaml';
      io.File problemFile = io.File(problemFileName);
      if (!problemFile.existsSync()) {
        error = GrpcError.notFound(
            'file not found: ' + problemFileName);
        return Tuple4(problems, metas, lastModified, error);
      }
      Tuple3<ProblemData, DateTime, GrpcError?> problem = _getProblemFromYaml(problemPrefix);
      if (problem.item3 != null) {
        error = problem.item3;
        return Tuple4(problems, metas, lastModified, error);
      }
      ProblemData data = problem.item1;
      problems.add(data);
    }
    return Tuple4(problems, metas, lastModified, error);
  }

  Tuple3<List<Lesson>, DateTime, GrpcError?> _getSectionLessons(String prefix, YamlMap parentMap) {
    List<Lesson> result = List.empty(growable: true);
    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    if (!parentMap.containsKey('lessons')) {
      return Tuple3(result, lastModified, error);
    }
    YamlList lessonIds = parentMap['lessons'];
    for (String lessonId in lessonIds) {
      String lessonPrefix = prefix + '/' + lessonId;
      String yamlFileName = root + '/' + lessonPrefix + '/lesson.yaml';
      io.File yamlFile = io.File(yamlFileName);
      if (!yamlFile.existsSync()) {
        error = GrpcError.notFound('file not found: ' + yamlFileName);
        return Tuple3(result, lastModified, error);
      }
      if (yamlFile.lastModifiedSync().millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = yamlFile.lastModifiedSync();
      }
      String yamlContent = yamlFile.readAsStringSync();
      YamlMap dataMap = loadYaml(yamlContent, sourceUrl: Uri(path: yamlFileName));
      Lesson data = Lesson(id: lessonId);
      if (dataMap.containsKey('name')) {
        data.name = dataMap['name'];
      }
      if (dataMap.containsKey('description')) {
        data.description = dataMap['description'];
      }
      DateTime readingsModified = lastModified;
      Tuple3<List<TextReading>,DateTime,GrpcError?> readingsResult = _getLessonReadings(lessonPrefix, dataMap);
      if (readingsResult.item3 != null) {
        error = readingsResult.item3;
        return Tuple3(result, lastModified, error);
      }
      data.readings.addAll(readingsResult.item1);
      readingsModified = readingsResult.item2;
      if (readingsModified.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = readingsModified;
      }
      DateTime problemsModified = lastModified;
      Tuple4<List<ProblemData>,List<ProblemMetadata>,DateTime,GrpcError?> problemsResult = _getLessonProblems(lessonPrefix, dataMap);
      if (problemsResult.item4 != null) {
        error = problemsResult.item4;
        return Tuple3(result, lastModified, error);
      }
      data.problems.addAll(problemsResult.item1);
      data.problemsMetadata.addAll(problemsResult.item2);
      problemsModified = problemsResult.item3;
      if (problemsModified.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = problemsModified;
      }
      result.add(data);
    }
    return Tuple3(result, lastModified, error);
  }

  Tuple3<List<Section>, DateTime, GrpcError?> _getCourseSections(String prefix, YamlMap parentMap) {
    List<Section> result = List.empty(growable: true);
    DateTime lastModified = DateTime.fromMicrosecondsSinceEpoch(0);
    GrpcError? error;
    if (!parentMap.containsKey('sections')) {
      return Tuple3(result, lastModified, error);
    }
    YamlList sectionIds = parentMap['sections'];
    for (String sectionId in sectionIds) {
      String sectionPrefix = prefix + '/' + sectionId;
      String yamlFileName = root + '/' + sectionPrefix + '/section.yaml';
      io.File yamlFile = io.File(yamlFileName);
      if (!yamlFile.existsSync()) {
        error = GrpcError.notFound('file not found: ' + yamlFileName);
        return Tuple3(result, lastModified, error);
      }
      if (yamlFile.lastModifiedSync().millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = yamlFile.lastModifiedSync();
      }
      String yamlContent = yamlFile.readAsStringSync();
      YamlMap dataMap = loadYaml(yamlContent, sourceUrl: Uri(path: yamlFileName));
      Section data = Section(id: sectionId);
      if (dataMap.containsKey('name')) {
        data.name = dataMap['name'];
      }
      if (dataMap.containsKey('description')) {
        data.description = dataMap['description'];
      }
      DateTime lessonsModified = lastModified;
      Tuple3<List<Lesson>,DateTime,GrpcError?> parsedResult = _getSectionLessons(sectionPrefix, dataMap);
      if (parsedResult.item3 != null) {
        error = parsedResult.item3;
        return Tuple3(result, lastModified, error);
      }
      data.lessons.addAll(parsedResult.item1);
      lessonsModified = parsedResult.item2;
      if (lessonsModified.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = lessonsModified;
      }
      result.add(data);
    }
    return Tuple3(result, lastModified, error);
  }

  void loadCourseIntoCache(String courseId) {
    String yamlFileName = courseId + '/course.yaml';
    String yamlFilePath = absolute(root + '/' + yamlFileName);
    io.File file = io.File(yamlFilePath);

    if (!file.existsSync()) {
      cache[courseId] = CourseDataCacheItem(
          loadError: GrpcError.internal('file $yamlFilePath not exists')
      );
      return;
    }
    DateTime lastModified = file.lastModifiedSync();
    String yamlContent = file.readAsStringSync();
    YamlMap dataMap = loadYaml(yamlContent, sourceUrl: Uri(path: yamlFilePath));
    CourseData data = CourseData();
    data.id = courseId;
    data.description = dataMap['description'] is String ? dataMap['description'] : '';
    if (dataMap.containsKey('max_submissions_per_hour')) {
      data.maxSubmissionsPerHour = dataMap['max_submissions_per_hour'];
    } else {
      data.maxSubmissionsPerHour = 10;
    }
    if (dataMap.containsKey('max_submission_file_size')) {
      data.maxSubmissionFileSize = dataMap['max_submission_file_size'];
    } else {
      data.maxSubmissionFileSize = 100 * 1024;
    }
    if (dataMap.containsKey('codestyle_files')) {
      YamlMap stylesMap = dataMap['codestyle_files'];
      DateTime stylesModified = lastModified;
      Tuple3<List<CodeStyle>,DateTime,GrpcError?> parseResult = _getCourseCodeStyles(courseId, stylesMap);
      if (parseResult.item3 != null) {
        cache[courseId] = CourseDataCacheItem(loadError: parseResult.item3);
        return;
      }
      data.codeStyles.addAll(parseResult.item1);
      if (stylesModified.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
        lastModified = stylesModified;
      }
    }
    Tuple3<List<Section>,DateTime,GrpcError?> parseResult = _getCourseSections(courseId, dataMap);
    if (parseResult.item3 != null) {
      cache[courseId] = CourseDataCacheItem(loadError: parseResult.item3);
      return;
    }
    DateTime sectionsLastModified = parseResult.item2;
    if (sectionsLastModified.millisecondsSinceEpoch > lastModified.millisecondsSinceEpoch) {
      lastModified = sectionsLastModified;
    }
    data.sections.addAll(parseResult.item1);
    CourseDataCacheItem cacheItem = CourseDataCacheItem(
      data: data,
      lastModified: lastModified,
      lastChecked: DateTime.now(),
    );
    cache[courseId] = cacheItem;
  }

  @override
  Future<CourseContentResponse> getCourseFullContent(ServiceCall? call, CourseContentRequest request) async {
    String courseId = request.courseDataId;
    if (courseId.isEmpty) {
      throw GrpcError.invalidArgument('course data id is required');
    }
    DateTime now = DateTime.now();
    DateTime nextCheck = now.add(CourseReloadInterval);
    bool inCache = cache.containsKey(courseId);
    if (!inCache) {
      loadCourseIntoCache(courseId);
    }
    CourseDataCacheItem course = cache[courseId]!;
    bool lastCheckTooOld = course.lastChecked!=null &&
        course.lastChecked!.millisecondsSinceEpoch >= nextCheck.millisecondsSinceEpoch;
    bool courseWasNotLoaded = course.loadError != null;
    if (lastCheckTooOld || courseWasNotLoaded) {
      loadCourseIntoCache(courseId);
      course = cache[courseId]!;
    }
    if (course.loadError != null) {
      throw course.loadError!;
    }
    if (request.cachedTimestamp.toInt() >= course.lastModified!.millisecondsSinceEpoch) {
      return CourseContentResponse(
        courseDataId: courseId,
        status: CourseContentStatus.NOT_CHANGED,
      );
    } else {
      return CourseContentResponse(
        courseDataId: courseId,
        status: CourseContentStatus.HAS_DATA,
        lastModified: Int64(course.lastModified!.millisecondsSinceEpoch),
        data: course.data,
      );
    }
  }

  @override
  Future<CourseContentResponse> getCoursePublicContent(ServiceCall call, CourseContentRequest request) async {
    CourseContentResponse fullResponse = await getCourseFullContent(call, request);
    // TODO clean non-public data
    return fullResponse;
  }

  @override
  Future<CoursesList> getCourses(ServiceCall call, CoursesFilter filter) async {
    List<Enrollment> enrollments = List.empty(growable: true);
    if (filter.user.id > 0) {
      enrollments = await getUserEnrollments(filter.user);
    }
    List<dynamic> allCourses = await connection.query(
      'select id,name,course_data,url_prefix from courses'
    );
    List<CoursesList_CourseListEntry> res = List.empty(growable: true);
    for (List<dynamic> row in allCourses) {
      Course candidate = Course();
      candidate.id = Int64(row[0]);
      candidate.name = row[1];
      candidate.dataId = row[2];
      candidate.urlPrefix = row[3];
      Role courseRole = Role.ROLE_STUDENT;
      if (enrollments.isNotEmpty) {
        bool enrollmentFound = false;
        for (Enrollment enr in enrollments) {
          if (enr.course.id == candidate.id) {
            enrollmentFound = true;
            courseRole = enr.role;
            break;
          }
        }
        if (!enrollmentFound) {
          continue;
        }
      }
      else if (filter.user.id > 0) {
        courseRole = await parent.userManagementService.getDefaultRole(filter.user);
      }
      if (filter.course.id > 0 && filter.course.id != candidate.id) {
        continue;
      }
      if (filter.course.name.isNotEmpty) {
        if (!UserManagementService.partialStringMatch(filter.partialStringMatch, candidate.name, filter.course.name)) {
          continue;
        }
      }
      CoursesList_CourseListEntry entry = CoursesList_CourseListEntry();
      entry.course = candidate;
      entry.role = courseRole;
      res.add(entry);
    }
    CoursesList result = CoursesList(courses: res);
    return result;
  }

  Future<List<Enrollment>> getUserEnrollments(User user) async {
    assert (user.id > 0);
    List<Enrollment> enrollments = List.empty(growable: true);
    List<dynamic> rows = await connection.query(
      'select courses_id, role from enrollments where users_id=@id',
      substitutionValues: { 'id': user.id.toInt() }
    );
    for (List<dynamic> fields in rows) {
      Course course = Course();
      int courseId = fields[0];
      int role = fields[1];
      course.id = Int64(courseId);
      Enrollment enrollment = Enrollment();
      enrollment.course = course;
      enrollment.role = Role.valueOf(role)!;
      enrollments.add(enrollment);
    }
    return enrollments;
  }



  
}