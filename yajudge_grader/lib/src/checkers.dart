import 'dart:io' as io;
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