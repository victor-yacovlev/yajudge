import 'dart:async';
import 'dart:convert';

import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;

abstract class AbstractRunner {
  void createDirectoryForSubmission(Submission submission);
  void releaseDirectoryForSubmission(Submission submission);

  Future<YajudgeProcess> start(Submission submission, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String,String>? environment,
    GradingLimits? limits,
    bool runTargetIsScript,
    String coprocessFileName,
  });

  void killProcess(YajudgeProcess process);

  String submissionPrivateDirectory(Submission submission);
  String submissionWorkingDirectory(Submission submission);
  String submissionProblemDirectory(Submission submission);
  String submissionRootPrefix(Submission submission);
  String submissionFileSystemRootPrefix(Submission submission);
}

class YajudgeProcess {
  final Future<int> realPid;
  final String cgroupDirectory;
  final int stdoutSizeLimit;
  final int stderrSizeLimit;
  final io.Process ioProcess;

  final List<int> _stdout = [];
  final List<int> _stderr = [];
  late final Future _stdoutListenerFuture;
  late final Future _stderrListenerFuture;


  YajudgeProcess({
    required this.realPid,
    required this.cgroupDirectory, 
    required this.ioProcess,
    this.stdoutSizeLimit = -1,
    this.stderrSizeLimit = -1,
  }) {
    _registerOutputListeners(ioProcess);
  }

  Future<List<int>> get stdout async {
    await exitCode;
    await _stdoutListenerFuture;
    return _stdout;
  }

  Future<List<int>> get stderr async {
    await exitCode;
    await _stderrListenerFuture;
    return _stderr;
  }

  Future<String> get stdoutAsString async {
    await exitCode;
    await _stdoutListenerFuture;
    return utf8.decode(_stdout, allowMalformed: true);
  }

  Future<String> get stderrAsString async {
    await exitCode;
    await _stderrListenerFuture;
    return utf8.decode(_stderr, allowMalformed: true);
  }

  Future<String> get outputAsString async {
    final stdout = await stdoutAsString;
    final stderr = await stderrAsString;
    String output = stdout;
    if (stderr.isNotEmpty) {
      if (output.isNotEmpty) {
        output += '\n';
      }
      output += stderr;
    }
    return output;
  }

  void _registerOutputListeners(io.Process process) {
    _stdoutListenerFuture = process.stdout.listen((chunk) {
      bool allow = -1==stdoutSizeLimit || (chunk.length + _stdout.length) < stdoutSizeLimit;
      if (allow) {
        _stdout.addAll(chunk);
      }
    }).asFuture();
    _stderrListenerFuture = process.stderr.listen((chunk) {
      bool allow = -1==stderrSizeLimit || (chunk.length + _stderr.length) < stderrSizeLimit;
      if (allow) {
        _stderr.addAll(chunk);
      }
    }).asFuture();
  }

  Future<int> get exitCode async {
    return ioProcess.exitCode;
  }

  Future<bool> get ok async {
    int code = await exitCode;
    return code == 0;
  }

  Future<bool> get fail async {
    int code = await exitCode;
    return code != 0;
  }

  Future<void> writeToStdin(List<int> bytes) async {
    ioProcess.stdin.add(bytes);
    await ioProcess.stdin.flush();
  }

  Future<void> closeStdin() async {
    await ioProcess.stdin.close();
  }

  void attachStdoutConsumer(void Function(List<int> data) listener) {
    if (_stdout.isNotEmpty) {
      // in case if there are already something written to stdout
      listener(_stdout);
    }
    ioProcess.stdout.listen(listener);
  }

}
