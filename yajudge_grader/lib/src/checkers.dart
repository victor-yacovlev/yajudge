import 'dart:convert';
import 'dart:io' as io;
import 'package:path/path.dart' as path;

abstract class AbstractChecker {
  bool get useFiles;
  String matchData(List<String> args, List<int> stdin, List<int> stdout, List<int> reference, String workDir, String root, String options) => throw UnimplementedError();
  String matchFiles(List<String> args, String stdinName, String stdoutName, String referenceName, String workDir, String root, String options) => throw UnimplementedError();
}

class PythonChecker extends AbstractChecker {
  final String checkerPy;
  PythonChecker({required this.checkerPy});

  @override
  String matchFiles(List<String> args, String stdinName, String stdoutName, String referenceName, String workDir, String root, String options) {
    String binDir = path.dirname(io.Platform.script.path);
    String pyWrapper = path.normalize(path.absolute(binDir, '../libexec/', 'checker_wrapper.py'));
    final arguments = [
      pyWrapper, checkerPy, workDir, args.join(' '), stdinName, stdoutName, referenceName
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
    final stdoutString = utf8.decode(stdout, allowMalformed: true).trimRight();
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
    if (stdoutLines.length != referenceLines.length)
      return 'Line count mismatch.\nExpected:\n$referenceString\nGot:\n$stdoutString';
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
    final stdoutList = stdoutString.split(rxDelim);
    final referenceList = referenceString.split(rxDelim);
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
      if (!matchDoubles(stdoutValue, referenceValue, epsilon))
        return 'Value mismatch. Expected $referenceValue, got $stdoutValue, epsilon=$epsilon';
    }
    return '';
  }
  bool matchDoubles(String stdout, String reference, double epsilon) {
    double? observedDouble = double.tryParse(stdout);
    double? referenceDouble = double.tryParse(reference);
    if (observedDouble==null || referenceDouble==null) {
      return false;
    }
    double diff = observedDouble - referenceDouble;
    if (diff < 0)
      diff *= -1;
    return diff < epsilon;
  }
}

class StandardCheckersFactory {
  static final checkers = {
    'text': TextChecker(),
    'double-sequence': DoubleSequenceChecker(),
  };

  static AbstractChecker getChecker(String name) {
    if (checkers.containsKey(name))
      return checkers[name]!;
    throw UnimplementedError('standard checker not implemented: $name');
  }
}