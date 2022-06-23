import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';

import '../../yajudge_common.dart';
import 'dart:io' as io;

import 'build_system.dart';
import 'executable_target.dart';
import 'grading_limits.dart';
import 'misc.dart';
import 'security_context.dart';

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