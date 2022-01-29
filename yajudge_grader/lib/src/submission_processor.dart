import 'dart:io' as io;

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yajudge_grader/src/chrooted_runner.dart';

class SubmissionProcessor {
  Submission submission;
  final CourseData courseData;
  final ProblemData problemData;
  final ChrootedRunner runner;
  final Logger log = Logger('SubmissionProcessor');

  SubmissionProcessor({
    required this.submission,
    required this.runner,
    required this.courseData,
    required this.problemData,
  });

  Future<void> processSubmission() async {
    try {
      runner.createProblemCacheDir(courseData, problemData);
      runner.createSubmissionDir(submission);
      runner.mountOverlay();
      runner.createSubmissionCgroup(submission.id.toInt());
      if (!await checkCodeStyles()) {
        return;
      }
      if (!await buildSolution()) {
        return;
      }
    } catch (error) {
      log.severe(error);
    } finally {
      runner.removeSubmissionCgroup(submission.id.toInt());
      runner.unMountOverlay();
    }
  }

  Future<bool> checkCodeStyles() async {
    for (final codeStyle in courseData.codeStyles) {
      String error = await checkCodeStyle(codeStyle);
      if (error.isNotEmpty) {
        submission = submission.copyWith((changed) {
          changed.status = SolutionStatus.STYLE_CHECK_ERROR;
        });
        return false;
      }
    }
    return true;
  }

  Future<bool> buildSolution() {
    bool hasCMakeLists = false;
    bool hasMakefile = false;
    bool hasGoFiles = false;
    for (final file in submission.solutionFiles.files) {
      if (file.name.toLowerCase() == 'makefile') {
        hasMakefile = true;
      }
      if (file.name.toLowerCase() == 'cmakelists.txt') {
        hasCMakeLists = true;
      }
      if (file.name.toLowerCase().endsWith('.go')) {
        hasGoFiles = true;
      }
    }
    if (hasCMakeLists) {
      return buildCMakeProject();
    } else if (hasMakefile) {
      return buildMakeProject();
    } else if (hasGoFiles) {
      return buildGoProject();
    } else {
      return buildProjectFromFiles();
    }
  }

  Future<bool> buildCMakeProject() {
    throw UnimplementedError('CMake project not implemented yet');
  }

  Future<bool> buildMakeProject() {
    throw UnimplementedError('Make project not implemented yet');
  }

  Future<bool> buildGoProject() {
    throw UnimplementedError('golang project not implemented yet');
  }

  Future<bool> buildProjectFromFiles() async {
    bool hasCFiles = false;
    bool hasGnuAsmFiles = false;
    bool hasCXXFiles = false;
    for (final file in submission.solutionFiles.files) {
      if (file.name.endsWith('.S') || file.name.endsWith('.s')) {
        hasGnuAsmFiles = true;
      }
      if (file.name.endsWith('.c')) {
        hasCFiles = true;
      }
      if (file.name.endsWith('.cxx') ||
          file.name.endsWith('.cc') ||
          file.name.endsWith('.cpp')) {
        hasCXXFiles = true;
      }
    }
    String compiler = '';
    if (hasCXXFiles) {
      compiler = 'clang++';
    } else if (hasCFiles || hasGnuAsmFiles) {
      compiler = 'clang';
    }
    if (compiler.isEmpty) {
      throw UnimplementedError('dont know how to build files out of ASM/C/C++');
    }
    // bool noStdLib =
    //     problemData.gradingOptions.extraCompileOptions.contains('-nostdlib');

    var compileOptions = ['-c', '-O2', '-Werror', '-g'];
    List<String> objectFiles = [];
    for (final sourceFile in submission.solutionFiles.files) {
      String suffix = path.extension(sourceFile.name);
      if (!['.S', '.s', '.c', '.cpp', '.cxx', '.cc'].contains(suffix)) continue;
      String objectFileName = sourceFile.name + '.o';
      final compilerArguments = compileOptions +
          problemData.gradingOptions.extraCompileOptions +
          ['-o', objectFileName, sourceFile.name];
      io.ProcessResult compileResult = await runner.runIsolated(
          submission.id.toInt(), compiler, compilerArguments);
      if (compileResult.exitCode != 0) {
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: ${compileResult.stderr}');
        String message = compileResult.stderr + compileResult.stdout;
        submission = submission.copyWith((changed) {
          changed.status = SolutionStatus.COMPILATION_ERROR;
          changed.buildErrors = message;
        });
        return false;
      } else {
        log.fine('successfully compiled ${sourceFile.name} from ${submission.id}');
        objectFiles.add(objectFileName);
      }
    }
    final linkerArguments = ['-o', 'solution'] +
        problemData.gradingOptions.extraLinkOptions +
        objectFiles;
    io.ProcessResult linkerResult = await runner.runIsolated(
        submission.id.toInt(), compiler, linkerArguments);
    if (linkerResult.exitCode != 0) {
      log.fine('cant link ${submission.id}: ${linkerResult.stderr}');
      String message = linkerResult.stderr + linkerResult.stdout;
      submission = submission.copyWith((changed) {
        changed.status = SolutionStatus.COMPILATION_ERROR;
        changed.buildErrors = message;
      });
    } else {
      log.fine('successfully linked ${submission.id}');
    }
    return true;
  }

  Future<String> checkCodeStyle(CodeStyle codeStyle) async {
    if (['.c', '.cpp', '.cxx', '.cc'].contains(codeStyle.sourceFileSuffix)) {
      // use clang-format
      for (final file in submission.solutionFiles.files) {
        String fileSuffix = path.extension(file.name);
        if (!['.c', '.cpp', '.cxx', '.cc'].contains(fileSuffix)) continue;
        io.ProcessResult clangResult;
        clangResult = await runner.runIsolated(
          submission.id.toInt(),
          'clang-format',
          ['-style=file', file.name],
        );
        String formattedCode = (clangResult.stdout as String).trim();
        String sourcePath = path.normalize('${runner.submissionUpperDir.path}/work/${file.name}');
        String sourceCode =
            io.File(sourcePath)
                .readAsStringSync()
                .trim();
        if (formattedCode != sourceCode) {
          return formattedCode;
        }
      }
    }
    return '';
  }
}
