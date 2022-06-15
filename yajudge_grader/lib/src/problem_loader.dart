import 'dart:io' as io;
import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'abstract_runner.dart';
import 'grader_extra_configs.dart';


class ProblemLoader {
  final Submission submission;
  final GraderLocationProperties locationProperties;
  final CourseManagementClient coursesService;
  final DefaultBuildProperties buildProperties;
  final SecurityContext defaultSecurityContext;
  final AbstractRunner runner;
  final log = Logger('ProblemLoader');

  ProblemLoader({
    required this.submission,
    required this.coursesService,
    required this.locationProperties,
    required this.buildProperties,
    required this.defaultSecurityContext,
    required this.runner,
  });

  Future<void> loadProblemData() async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;
    String root = locationProperties.cacheDir;
    final problemDir = io.Directory(path.absolute(root, courseId, problemId.replaceAll(':', '/')));
    final problemTimeStampFile = io.File('${problemDir.path}/.timestamp');
    int timeStamp = 0;
    if (problemTimeStampFile.existsSync()) {
      String timeStampData = problemTimeStampFile.readAsStringSync().trim();
      timeStamp = int.parse(timeStampData);
    }
    final request = ProblemContentRequest(
      courseDataId: courseId,
      problemId: problemId,
      cachedTimestamp: Int64(timeStamp),
    );
    final response = await coursesService.getProblemFullContent(request);
    if (response.status == ContentStatus.HAS_DATA) {
      problemDir.createSync(recursive: true);
      io.Directory buildDir = io.Directory('${problemDir.path}/build');
      io.Directory optsDir = io.Directory('${problemDir.path}/build');
      io.Directory testsDir = io.Directory('${problemDir.path}/tests');
      buildDir.createSync(recursive: true);
      testsDir.createSync(recursive: true);
      final problemData = response.data.deepCopy();
      final opts = problemData.gradingOptions;
      opts.extraBuildFiles.saveAll(buildDir);
      opts.coprocess = await buildSupplementaryProgram(
          opts.coprocess, buildDir.path, courseId, problemId
      );
      opts.interactor = await buildSupplementaryProgram(
          opts.interactor, buildDir.path, courseId, problemId
      );
      opts.testsGenerator = await buildSupplementaryProgram(
          opts.testsGenerator, buildDir.path, courseId, problemId
      );
      opts.customChecker = await buildSupplementaryProgram(
          opts.customChecker, buildDir.path, courseId, problemId
      );
      opts.saveToPlainFiles(optsDir);
      opts.saveTests(testsDir);
      problemTimeStampFile.writeAsStringSync('${response.lastModified.toInt()}\n');
    }
  }

  Future<File> buildSupplementaryProgram(
      File sourceFile,
      String buildDirPath, String courseId, String problemId
      ) async {
    final sourceName = sourceFile.name;
    final binaryName = path.basenameWithoutExtension(sourceName);
    bool useC = sourceName.endsWith('.c');
    bool useCxx = sourceName.endsWith('.cxx') || sourceName.endsWith('.cpp');
    if (!useC && !useCxx) {
      return sourceFile;  // do not build
    }
    final buildDir = io.Directory(buildDirPath);
    buildDir.createSync(recursive: true);
    sourceFile.save(buildDir);

    final compilerProperties = buildProperties.propertiesForLanguage(
        useCxx? ProgrammingLanguage.cxx : ProgrammingLanguage.c
    );
    
    final compiler = compilerProperties.compiler;
    final baseOptions = compilerProperties.property('compile_options');

    const targetName = 'build_supplementary';
    runner.createDirectoryForSubmission(Submission(id: Int64(-1), problemId: problemId), targetName);

    final arguments = baseOptions + ['-o', binaryName, sourceName];
    final process = await runner.start(
      Submission(id: Int64(-1), problemId: problemId),
      [compiler] + arguments,
      workingDirectory: '/build',
      targetName: targetName,
    );

    bool compilerOk = await process.ok;
    if (!compilerOk) {
      String errorMessage = await process.outputAsString;
      log.severe(
          'cant build supplementary $sourceName: $compiler ${arguments.join(
              ' ')}:\n$errorMessage\n');
    }

    final binaryContent = io.File('$buildDirPath/$binaryName')
      .readAsBytesSync();

    runner.releaseDirectoryForSubmission(Submission(id: Int64(-1)), targetName);

    return File(name: binaryName, data: binaryContent);
  }

}