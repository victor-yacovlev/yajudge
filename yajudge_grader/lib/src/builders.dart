import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'abstract_runner.dart';
import 'grader_extra_configs.dart';
import 'package:path/path.dart' as path;

class BuildError extends Error {
  final String buildMessage;

  BuildError(this.buildMessage);
}

class BuildArtifact {
  final ExecutableTarget executableTarget;
  final List<String> fileNames;

  BuildArtifact({
    required this.executableTarget,
    required this.fileNames,
  });
}

class StyleCheckResult {
  final String fileName;
  final String message;
  final bool acceptable;

  StyleCheckResult(this.fileName, this.message, this.acceptable);
}

abstract class AbstractBuilder {

  final DefaultBuildProperties defaultBuildProperties;
  final AbstractRunner runner;
  final log = Logger('Builder');

  AbstractBuilder({
    required this.defaultBuildProperties,
    required this.runner,
  });

  bool canBuild(Submission submission);
  bool canCheckCodeStyle(Submission submission) => false;
  ExecutableTarget get defaultBuildTarget => ExecutableTarget.AutodetectExecutable;

  Future<Iterable<BuildArtifact>> build({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties extraBuildProperties,
    required ExecutableTarget target,
  });

  Future<Iterable<StyleCheckResult>> checkStyle({
    required Submission submission,
    required String buildDirRelativePath,
  }) async => [];

}

class CLangBuilder extends AbstractBuilder {
  CLangBuilder({required super.defaultBuildProperties, required super.runner});

  static List<String> _sanitizeOptions({
    required TargetProperties buildProperties,
    required ExecutableTarget target,
  }) {
    final enableSanitizers = buildProperties.property('enable_sanitizers').toSet();
    final disableSanitizers = buildProperties.property('disable_sanitizers').toSet();
    final sanitizersToUse = enableSanitizers.difference(disableSanitizers);
    List<String> sanitizersToEnable;
    if (target==ExecutableTarget.NativeWithValgrind) {
      sanitizersToEnable = [];
    }
    else {
      sanitizersToEnable = sanitizersToUse.toList();
    }

    List<String> sanitizerOptions = sanitizersToEnable.map(
            (e) => '-fsanitize=$e'
    ).toList();
    return sanitizerOptions;
  }

  @override
  bool canCheckCodeStyle(Submission submission) {
    final fileSet = submission.solutionFiles;
    for (final file in fileSet.files) {
      final fileName = file.name;
      final fileSuffix = path.extension(fileName);
      String styleFile = _styleFileName(submission, fileSuffix);
      if (styleFile == '.clang-format') {
        return true;
      }
    }
    return false;
  }

  @override
  bool canBuild(Submission submission) {
    final fileSet = submission.solutionFiles;
    return hasCFiles(fileSet) || hasCXXFiles(fileSet) || hasGnuAsmFiles(fileSet);
  }

  static bool hasCFiles(FileSet fileSet) {
    return fileSet.files.any((e) => e.name.endsWith('.c'));
  }

  static bool hasCXXFiles(FileSet fileSet) {
    return fileSet.files.any(
            (e) => e.name.endsWith('.cxx') ||
                e.name.endsWith('.cpp') ||
                e.name.endsWith('.cc')
    );
  }

  static bool hasGnuAsmFiles(FileSet fileSet) {
    return fileSet.files.any(
            (e) => e.name.endsWith('.S') ||
            e.name.endsWith('.s')
    );
  }

  TargetProperties _resolveBuildProperties({
    required Submission submission,
    required TargetProperties extraBuildProperties,
  }) {
    final fileSet = submission.solutionFiles;
    TargetProperties cProperties =
    defaultBuildProperties.propertiesForLanguage(ProgrammingLanguage.c)
        .mergeWith(extraBuildProperties);
    TargetProperties cxxProperties =
    defaultBuildProperties.propertiesForLanguage(ProgrammingLanguage.cxx)
        .mergeWith(extraBuildProperties);
    TargetProperties asmProperties =
    defaultBuildProperties.propertiesForLanguage(ProgrammingLanguage.gnuAsm)
        .mergeWith(extraBuildProperties);

    TargetProperties buildProperties;
    if (hasCXXFiles(fileSet)) {
      buildProperties = cxxProperties;
    }
    else if (hasGnuAsmFiles(fileSet)) {
      buildProperties = asmProperties;
    }
    else if (hasCFiles(fileSet)) {
      buildProperties = cProperties;
    }
    else {
      throw BuildError('no suitable source files for gcc/clang toolchain');
    }
    return buildProperties;
  }

  Future<BuildArtifact> _buildTarget({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties buildProperties,
    required ExecutableTarget target,
    required List<String> sanitizerOptions,
  }) async {

    final fileSet = submission.solutionFiles;

    final submissionRootPath = runner.submissionPrivateDirectory(submission);
    final buildFullPath = '$submissionRootPath/$buildDirRelativePath';
    final buildDir = io.Directory(buildFullPath);
    final compiler = buildProperties.compiler;
    final compileOptions = buildProperties.property('compile_options');

    String objectSuffix;
    String binaryTargetName;
    if (sanitizerOptions.isNotEmpty) {
      sanitizerOptions += ['-fno-sanitize-recover=all'];
      objectSuffix = '.san.o';
      binaryTargetName = 'solution-san';
    }
    else {
      objectSuffix = '.o';
      binaryTargetName = 'solution';
    }

    List<String> objectFiles = [];
    for (final sourceFile in fileSet.files) {
      String suffix = path.extension(sourceFile.name);
      if (!['.S', '.s', '.c', '.cpp', '.cxx', '.cc'].contains(suffix)) continue;
      String objectFileName = sourceFile.name + objectSuffix;
      final compilerArguments = ['-c'] +
              compileOptions.toList() +
              sanitizerOptions +
              ['-o', objectFileName] +
              [sourceFile.name];
      final compilerCommand = [compiler] + compilerArguments;
      final compilerProcess = await runner.start(
        submission,
        compilerCommand,
        workingDirectory: buildDirRelativePath,
      );
      bool compilerOk = await compilerProcess.ok;
      if (!compilerOk) {
        String message = await compilerProcess.outputAsString;
        String detailedMessage = '${compilerCommand.join(' ')}\n$message}';
        io.File('${buildDir.path}/compile.log').writeAsStringSync(detailedMessage);
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: $detailedMessage');
        throw BuildError(detailedMessage);
      } else {
        log.fine('successfully compiled ${sourceFile.name} from ${submission.id}');
        objectFiles.add(objectFileName);
      }
    } // done compiling source files into object files

    final linkOptions = buildProperties.property('link_options');
    final linkerArguments = ['-o', binaryTargetName] +
        sanitizerOptions +
        linkOptions +
        objectFiles;
    final linkerCommand = [compiler] + linkerArguments;
    final linkerProcess = await runner.start(
        submission,
        linkerCommand,
        workingDirectory: buildDirRelativePath,
    );
    bool linkerOk = await linkerProcess.ok;
    if (!linkerOk) {
      String message = await linkerProcess.outputAsString;
      String detailedMessage = '${linkerCommand.join(' ')}\n$message';
      log.fine('cant link ${submission.id}: $detailedMessage');
      io.File('${buildDir.path}/compile.log').writeAsStringSync(detailedMessage);
      throw BuildError(detailedMessage);
    } else {
      log.fine('successfully linked target $binaryTargetName for ${submission.id}');
      return BuildArtifact(
          executableTarget: target,
          fileNames: ['$buildDirRelativePath/$binaryTargetName'],
      );
    }
  }

  @override
  Future<Iterable<StyleCheckResult>> checkStyle({
    required Submission submission,
    required String buildDirRelativePath,
  }) async {
    final fileSet = submission.solutionFiles;
    List<StyleCheckResult> result = [];
    for (final file in fileSet.files) {
      final fileName = file.name;
      final fileSuffix = path.extension(fileName);
      final styleFile = _styleFileName(submission, fileSuffix);
      if (styleFile.isEmpty) {
        continue;
      }
      final clangProcess = await runner.start(
        submission,
        ['clang-format', '-style=file', fileName],
        workingDirectory: buildDirRelativePath,
      );
      bool clangFormatOk = await clangProcess.ok;
      if (!clangFormatOk) {
        String message = await clangProcess.outputAsString;
        log.severe('clang-format failed: $message');
        throw Exception(message);
      }
      String submissionPath = runner.submissionPrivateDirectory(submission);
      String sourcePath = path.normalize('$submissionPath/build/$fileName');
      String formattedPath = '$sourcePath.formatted';
      final formattedFile = io.File(formattedPath);
      formattedFile.writeAsStringSync(await clangProcess.outputAsString);

      final diffProcess = await runner.start(
        submission,
        ['diff', fileName, '$fileName.formatted'],
        workingDirectory: '/build',
      );
      bool diffOk = await diffProcess.ok;
      String diffOut = await diffProcess.outputAsString;
      if (!diffOk) {
        final failedStyleCheck = StyleCheckResult(fileName, diffOut, false);
        result.add(failedStyleCheck);
      }
      else {
        final acceptedStyleCheck = StyleCheckResult(fileName, diffOut, true);
        result.add(acceptedStyleCheck);
      }
    }
    return result;
  }

  String _styleFileName(Submission submission, String suffix) {
    String solutionPath = '${runner.submissionProblemDirectory(submission)}/build';
    if (suffix.startsWith('.')) {
      suffix = suffix.substring(1);
    }
    String styleLinkPath = '$solutionPath/.style_$suffix';
    if (io.File(styleLinkPath).existsSync()) {
      return io.File(styleLinkPath).readAsStringSync().trim();
    }
    return '';
  }

  @override
  Future<Iterable<BuildArtifact>> build({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties extraBuildProperties,
    required ExecutableTarget target,
  }) async {
    List<BuildArtifact> artifacts = [];

    TargetProperties buildProperties = _resolveBuildProperties(
        submission: submission,
        extraBuildProperties: extraBuildProperties
    );

    final sanitizerOptions = _sanitizeOptions(
        buildProperties: buildProperties,
        target: target
    );

    bool hasC = hasCFiles(submission.solutionFiles);
    bool hasCxx = hasCXXFiles(submission.solutionFiles);
    bool noStdLib = buildProperties.property('link_options').contains('-nostdlib');
    bool sanitizersAvailable = !noStdLib && (hasC || hasCxx);
    bool buildSanitizersTarget = sanitizersAvailable &&
        sanitizerOptions.isNotEmpty &&
        {
          ExecutableTarget.NativeWithSanitizers,
          ExecutableTarget.NativeWithSanitizersAndValgrind,
        }.contains(target);
    bool buildPlainTarget = !buildSanitizersTarget ||
        {
          ExecutableTarget.Native,
          ExecutableTarget.NativeWithValgrind,
          ExecutableTarget.NativeWithSanitizersAndValgrind,
        }.contains(target);
    bool enableValgrind = io.Platform.isLinux &&
        {
          ExecutableTarget.NativeWithValgrind,
          ExecutableTarget.NativeWithSanitizersAndValgrind,
        }.contains(target);

    assert(buildPlainTarget || buildSanitizersTarget);

    if (buildPlainTarget) {
      final plainTarget = await _buildTarget(
          submission: submission,
          buildDirRelativePath: buildDirRelativePath,
          buildProperties: buildProperties,
          target: enableValgrind? ExecutableTarget.NativeWithValgrind : ExecutableTarget.Native,
          sanitizerOptions: [],
      );
      artifacts.add(plainTarget);
    }

    if (buildSanitizersTarget) {
      final sanitizedTarget = await _buildTarget(
        submission: submission,
        buildDirRelativePath: buildDirRelativePath,
        buildProperties: buildProperties,
        target: ExecutableTarget.NativeWithSanitizers,
        sanitizerOptions: sanitizerOptions,
      );
      artifacts.add(sanitizedTarget);
    }

    return artifacts;
  }

  @override
  ExecutableTarget get defaultBuildTarget => ExecutableTarget.NativeWithSanitizersAndValgrind;
}

class VoidBuilder extends AbstractBuilder {
  VoidBuilder({required super.defaultBuildProperties, required super.runner});

  @override
  Future<Iterable<BuildArtifact>> build({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties extraBuildProperties,
    required ExecutableTarget target
  }) async {
    final fileSet = submission.solutionFiles;
    final scriptFileNames = fileSet.files.map((file) => '$buildDirRelativePath/${file.name}');
    return [BuildArtifact(
      executableTarget: target,
      fileNames: scriptFileNames.toList(),
    )];
  }

  @override
  bool canBuild(Submission submission) => true;
}

class MakefileBuilder extends AbstractBuilder {
  MakefileBuilder({required super.defaultBuildProperties, required super.runner});

  @override
  Future<Iterable<BuildArtifact>> build({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties extraBuildProperties,
    required ExecutableTarget target
  }) async {
    final buildDir = io.Directory('${runner.submissionPrivateDirectory(submission)}/build');
    DateTime beforeMake = DateTime.now();
    io.sleep(Duration(milliseconds: 250));
    final makeProcess = await runner.start(
      submission,
      ['make'],
      workingDirectory: '/build',
    );
    bool makeOk = await makeProcess.ok;
    if (!makeOk) {
      String message = await makeProcess.outputAsString;
      log.fine('cant build Makefile project from ${submission.id}:\n$message');
      io.File('${buildDir.path}/make.log').writeAsStringSync(message);
      throw BuildError(message);
    } else {
      log.fine('successfully compiled Makefile project from ${submission.id}');
    }
    final entriesAfterMake = buildDir.listSync(recursive: true);
    List<io.FileSystemEntity> newEntries = [];
    for (final entry in entriesAfterMake) {
      DateTime modified = entry.statSync().modified;
      if (modified.millisecondsSinceEpoch <= beforeMake.millisecondsSinceEpoch) {
        continue;
      }
      else {
        newEntries.add(entry);
      }
    }
    final newEntriesForTarget = newEntries.where((e) => _artifactMatchesTarget(e, target));
    if (newEntriesForTarget.isEmpty) {
      String message = 'no suitable targets created by make in Makefile project from ${submission.id}';
      log.fine(message);
      io.File('${buildDir.path}/make.log').writeAsStringSync(message);
      throw BuildError(message);
    }
    List<String> artifactFileNames = [];
    for (final entry in newEntriesForTarget) {
      String relativePath = entry.path;
      if (relativePath.startsWith(buildDir.path)) {
        relativePath = relativePath.substring(buildDir.path.length);
      }
      relativePath = '$buildDirRelativePath/$relativePath';
      relativePath = path.normalize(relativePath);
      artifactFileNames.add(relativePath);
    }
    final artifact = BuildArtifact(
      executableTarget: target,
      fileNames: artifactFileNames,
    );
    return [artifact];
  }

  bool _artifactMatchesTarget(io.FileSystemEntity entity, ExecutableTarget target) {
    switch (target) {
      case ExecutableTarget.JavaClass:
        return entity.path.endsWith('.class');
      case ExecutableTarget.JavaJar:
        return entity.path.endsWith('.jar');
      case ExecutableTarget.Native:
      case ExecutableTarget.NativeWithSanitizers:
      case ExecutableTarget.NativeWithSanitizersAndValgrind:
      case ExecutableTarget.NativeWithValgrind:
        final mode = entity.statSync().mode;
        final isExecutable = mode & 0x1 > 0;
        return isExecutable;
      case ExecutableTarget.QemuSystemImage:
        return entity.path.endsWith('.img');
      default:
        return true;
    }
  }

  @override
  bool canBuild(Submission submission) {
    final fileSet = submission.solutionFiles;
    return fileSet.files.any((element) => element.name.toLowerCase()=='makefile');
  }

}

class JavaBuilder extends AbstractBuilder {
  JavaBuilder({required super.defaultBuildProperties, required super.runner});

  @override
  ExecutableTarget get defaultBuildTarget => ExecutableTarget.JavaClass;

  @override
  Future<Iterable<BuildArtifact>> build({
    required Submission submission,
    required String buildDirRelativePath,
    required TargetProperties extraBuildProperties,
    required ExecutableTarget target,
  }) async {
    final buildProperties = defaultBuildProperties
      .propertiesForLanguage(ProgrammingLanguage.java)
      .mergeWith(extraBuildProperties);

    final fileSet = submission.solutionFiles;

    final submissionRootPath = runner.submissionPrivateDirectory(submission);
    final buildFullPath = '$submissionRootPath/$buildDirRelativePath';
    final buildDir = io.Directory(buildFullPath);
    final compiler = buildProperties.compiler;
    final compileOptions = buildProperties.property('compile_options');

    List<String> classFiles = [];
    for (final sourceFile in fileSet.files) {
      String suffix = path.extension(sourceFile.name);
      if (suffix != '.java') continue;
      final classFileName = '${sourceFile.name.substring(0, sourceFile.name.length-5)}.class';
      final compilerArguments = compileOptions.toList() + [sourceFile.name];
      final compilerCommand = [compiler] + compilerArguments;
      final compilerProcess = await runner.start(
        submission,
        compilerCommand,
        workingDirectory: buildDirRelativePath,
      );
      bool compilerOk = await compilerProcess.ok;
      if (!compilerOk) {
        String message = await compilerProcess.outputAsString;
        String detailedMessage = '${compilerCommand.join(' ')}\n$message}';
        io.File('${buildDir.path}/compile.log').writeAsStringSync(detailedMessage);
        log.fine('cant compile ${sourceFile.name} from ${submission.id}: $detailedMessage');
        throw BuildError(detailedMessage);
      } else {
        log.fine('successfully compiled ${sourceFile.name} from ${submission.id}');
        classFiles.add(classFileName);
      }
    } // done compiling source files into object files

    return [BuildArtifact(
      executableTarget: ExecutableTarget.JavaClass,
      fileNames: classFiles,
    )];
  }

  @override
  bool canBuild(Submission submission) {
    final fileSet = submission.solutionFiles;
    return fileSet.files.any((element) => element.name.endsWith('.java'));
  }

}

class UnknownBuildSystemError extends Error {
  UnknownBuildSystemError();
}

class BuilderFactory {
  final DefaultBuildProperties defaultBuildProperties;
  final AbstractRunner runner;

  BuilderFactory(this.defaultBuildProperties, this.runner);

  AbstractBuilder createBuilder(Submission submission, GradingOptions gradingOptions) {
    switch (gradingOptions.buildSystem) {
      case BuildSystem.AutodetectBuild:
        return _detectBuildSystem(submission);
      case BuildSystem.CMakeProject:
        throw UnimplementedError('CMake project support not implemented yet');
      case BuildSystem.ClangToolchain:
        return CLangBuilder(
            defaultBuildProperties: defaultBuildProperties, runner: runner
        );
      case BuildSystem.GoLangProject:
        throw UnimplementedError('Go language support not implemented yet');
      case BuildSystem.JavaPlainProject:
        return JavaBuilder(
            defaultBuildProperties: defaultBuildProperties, runner: runner
        );
      case BuildSystem.MakefileProject:
        return MakefileBuilder(
            defaultBuildProperties: defaultBuildProperties, runner: runner
        );
      case BuildSystem.MavenProject:
        throw UnimplementedError('Maven project support not implemented yet');
      case BuildSystem.PythonCheckers:
        throw UnimplementedError('Python linters support not implemented yet');
      case BuildSystem.SkipBuild:
        return VoidBuilder(
            defaultBuildProperties: defaultBuildProperties, runner: runner
        );
      default:
        throw UnknownBuildSystemError();
    }
  }

  AbstractBuilder _detectBuildSystem(Submission submission) {
    final implementedBuilders = {
      MakefileBuilder(defaultBuildProperties: defaultBuildProperties, runner: runner),
      CLangBuilder(defaultBuildProperties: defaultBuildProperties, runner: runner),
      JavaBuilder(defaultBuildProperties: defaultBuildProperties, runner: runner),
      VoidBuilder(defaultBuildProperties: defaultBuildProperties, runner: runner),
    };
    for (final builder in implementedBuilders) {
      if (builder.canBuild(submission)) {
        return builder;
      }
    }
    throw UnknownBuildSystemError();
  }

}
