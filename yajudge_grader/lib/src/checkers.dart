import 'dart:convert';
import 'dart:io' as io;
import 'package:yajudge_common/yajudge_common.dart';

import 'assets_loader.dart';

abstract class AbstractChecker {
  bool get useFiles;
  String matchData(List<String> args, List<int> stdin, List<int> stdout, List<int> reference, String workDir, String root, String options) => throw UnimplementedError();
  String matchFiles(List<String> args, String stdinName, String stdoutName, String referenceName, String workDir, String root, String options) => throw UnimplementedError();
}

class PythonChecker extends AbstractChecker {
  final GraderLocationProperties locationProperties;
  final String checkerPy;

  PythonChecker({required this.locationProperties, required this.checkerPy});

  @override
  String matchFiles(List<String> args, String stdinName, String stdoutName, String referenceName, String workDir, String root, String options) {
    final wrappersDir = io.Directory(locationProperties.cacheDir + '/wrappers');
    if (!wrappersDir.existsSync()) {
      wrappersDir.createSync(recursive: true);
    }
    final wrapperFile = io.File(wrappersDir.path + '/checker_wrapper.py');
    if (!wrapperFile.existsSync()) {
      final content = assetsLoader.fileAsBytes('checker_wrapper.py');
      wrapperFile.writeAsBytesSync(content);
    }

    final arguments = [
      wrapperFile.path, checkerPy,
      workDir, args.join(' '), stdinName, stdoutName, referenceName
    ];

    Map<String,String> environment = Map.from(io.Platform.environment);
    environment['YAJUDGE_ROOT'] = root;
    final processResult = io.Process.runSync(
        'python3',
        arguments,
        environment: environment,
        runInShell: true,
    );
    bool matchOk = processResult.exitCode == 0;
    if (!matchOk) {
      String message = processResult.stdout + '\n' + processResult.stderr;
      message = message.trim();
      if (message.isEmpty) {
        message = 'Checker exited with code ${processResult.exitCode}';
      }
      return message;
    }
    else {
      return '';
    }
  }

  @override
  bool get useFiles => true;
}

class TextChecker extends AbstractChecker {
  @override
  String matchData(List<String> args, List<int> stdin, List<int> stdout, List<int> reference, String workDir, String root, String options) {
    final opts = options.split(' ');
    String stdoutString = '';
    try {
      stdoutString = utf8.decode(stdout, allowMalformed: false).trimRight();
    }
    catch (e) {
      if (e is FormatException) {
        return 'Invalid characters in output.\nExpected printable text, got binary data.';
      }
    }
    final referenceString = utf8.decode(reference, allowMalformed: true).trimRight();
    if (opts.contains('strict')) {
      if (stdoutString == referenceString) {
        return '';
      }
      else {
        return 'Text mismatch in strict mode.\nExpected:\n$referenceString\nGot:\n$stdoutString';
      }
    }
    final stdoutLines = stdoutString.trimLeft().split('\n');
    final referenceLines = referenceString.trimLeft().split('\n');
    if (stdoutLines.length != referenceLines.length) {
      return 'Line count mismatch.\nExpected:\n$referenceString\nGot:\n$stdoutString';
    }
    for (int i=0; i<stdoutLines.length; i++) {
      final a = stdoutLines[i].trim();
      final b = referenceLines[i].trim();
      if (a != b) {
        return 'Text line mismatch.\nExpected:\n$b\nGot:\n$a';
      }
    }
    return '';
  }
  @override
  bool get useFiles => false;
}

class DoubleSequenceChecker extends AbstractChecker {
  @override
  bool get useFiles => false;
  @override
  String matchData(List<String> args, List<int> stdin, List<int> stdout, List<int> reference, String workDir, String root, String options) {
    String stdoutString = utf8.decode(stdout, allowMalformed: true).trim();
    String referenceString = utf8.decode(reference, allowMalformed: true).trim();
    final rxDelim = RegExp(r'\s+');
    final stdoutList = stdoutString.isEmpty? [] : stdoutString.split(rxDelim);
    final referenceList = referenceString.isEmpty? [] : referenceString.split(rxDelim);
    double epsilon = 0.000001;
    final opts = options.split(' ');
    for (final opt in opts) {
      if (opt.startsWith('epsilon=')) {
        String epsilonValue = opt.substring(8).trim();
        epsilon = double.parse(epsilonValue);
      }
    }
    if (stdoutList.length != referenceList.length) {
      return 'Count of numbers mismatch.\nExpected:\n$referenceList\nGot:\n$stdoutList';
    }
    for (int i=0; i<stdoutList.length; i++) {
      String stdoutValue = stdoutList[i];
      String referenceValue = referenceList[i];
      if (!matchDoubles(stdoutValue, referenceValue, epsilon)) {
        return 'Value mismatch. Expected $referenceValue, got $stdoutValue, epsilon=$epsilon';
      }
    }
    return '';
  }
  bool matchDoubles(String stdout, String reference, double epsilon) {
    double? stdoutDouble = double.tryParse(stdout);
    double? referenceDouble = double.tryParse(reference);
    if (stdoutDouble==null || referenceDouble==null) {
      return false;
    }
    double diff = stdoutDouble - referenceDouble;
    if (diff < 0) {
      diff *= -1;
    }
    return diff < epsilon;
  }
}

class IntSequenceChecker extends AbstractChecker {
  @override
  bool get useFiles => false;
  @override
  String matchData(List<String> args, List<int> stdin, List<int> stdout, List<int> reference, String workDir, String root, String options) {
    String stdoutString = utf8.decode(stdout, allowMalformed: true).trim();
    String referenceString = utf8.decode(reference, allowMalformed: true).trim();
    final rxDelim = RegExp(r'\s+');
    final stdoutList = stdoutString.isEmpty? [] : stdoutString.split(rxDelim);
    final referenceList = referenceString.isEmpty? [] : referenceString.split(rxDelim);
    if (stdoutList.length != referenceList.length) {
      return 'Count of numbers mismatch.\nExpected:\n$referenceList\nGot:\n$stdoutList';
    }
    for (int i=0; i<stdoutList.length; i++) {
      String stdoutValue = stdoutList[i];
      String referenceValue = referenceList[i];
      if (!matchInts(stdoutValue, referenceValue)) {
        return 'Value mismatch. Expected $referenceValue, got $stdoutValue';
      }
    }
    return '';
  }
  bool matchInts(String stdout, String reference) {
    int? observedInt = int.tryParse(stdout);
    int? referenceInt = int.tryParse(reference);
    if (observedInt==null || referenceInt==null) {
      return false;
    }
    return observedInt == referenceInt;
  }
}

class StandardCheckersFactory {
  static final checkers = {
    'text': TextChecker(),
    'double-sequence': DoubleSequenceChecker(),
    'int-sequence': IntSequenceChecker(),
  };

  static AbstractChecker getChecker(String name) {
    if (checkers.containsKey(name)) {
      return checkers[name]!;
    }
    throw UnimplementedError('standard checker not implemented: $name');
  }
}