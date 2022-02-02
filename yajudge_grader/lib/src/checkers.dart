import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as path;

abstract class AbstractChecker {
  bool get useFiles;
  bool matchData(List<int> observed, List<int> reference, String workDir, String options) => throw UnimplementedError();
  bool matchFiles(String observedFileName, String referenceFileName, String workDir, String options) => throw UnimplementedError();
}

class PythonChecker extends AbstractChecker {
  final String checkerPy;
  PythonChecker({required this.checkerPy});

  @override
  bool matchFiles(String observedFileName, String referenceFileName, String workDir, String options) {
    String binDir = path.dirname(io.Platform.script.path);
    String pyWrapper = path.normalize(path.absolute(binDir, '../libexec/', 'checker_wrapper.py'));
    final arguments = [
      pyWrapper, checkerPy, workDir, observedFileName, referenceFileName
    ];
    final processResult = io.Process.runSync('python3', arguments, runInShell: true);
    return processResult.exitCode == 0;
  }

  @override
  bool get useFiles => true;
}

class TextChecker extends AbstractChecker {
  @override
  bool matchData(List<int> observed, List<int> reference, String workDir, String options) {
    final opts = options.split(' ');
    final observedString = utf8.decode(observed, allowMalformed: true).trimRight();
    final referenceString = utf8.decode(reference, allowMalformed: true).trimRight();
    if (opts.contains('strict')) {
      return observedString == referenceString;
    }
    final observedLines = observedString.trimLeft().split('\n');
    final referenceLines = referenceString.trimLeft().split('\n');
    if (observedLines.length != referenceLines.length)
      return false;
    for (int i=0; i<observedLines.length; i++) {
      final a = observedLines[i].trim();
      final b = referenceLines[i].trim();
      if (a != b) {
        return false;
      }
    }
    return true;
  }
  @override
  bool get useFiles => false;
}

class DoubleSequenceChecker extends AbstractChecker {
  @override
  bool get useFiles => false;
  @override
  bool matchData(List<int> observed, List<int> reference, String workDir, String options) {
    String observedString = utf8.decode(observed, allowMalformed: true).trim();
    String referenceString = utf8.decode(reference, allowMalformed: true).trim();
    final rxDelim = RegExp(r'\s+');
    final observedList = observedString.split(rxDelim);
    final referenceList = referenceString.split(rxDelim);
    double epsilon = 0.000001;
    final opts = options.split(' ');
    for (final opt in opts) {
      if (opt.startsWith('epsilon=')) {
        String epsilonValue = opt.substring(8).trim();
        epsilon = double.parse(epsilonValue);
      }
    }
    if (observedList.length != referenceList.length) {
      return false;
    }
    for (int i=0; i<observedList.length; i++) {
      String observedValue = observedList[i];
      String referenceValue = referenceList[i];
      if (!matchDoubles(observedValue, referenceValue, epsilon))
        return false;
    }
    return true;
  }
  bool matchDoubles(String observed, String reference, double epsilon) {
    double? observedDouble = double.tryParse(observed);
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