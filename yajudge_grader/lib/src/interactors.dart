import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'abstract_runner.dart';
import 'assets_loader.dart';
import 'package:posix/posix.dart' as posix;

abstract class AbstractInteractor {
  Future<Function> interact(YajudgeProcess targetProcess, String workDir, String dataFileName);
}

class PythonInteractor extends AbstractInteractor {
  final GraderLocationProperties locationProperties;
  final String interactorPy;

  PythonInteractor({required this.locationProperties, required this.interactorPy});

  @override
  Future<Function> interact(YajudgeProcess targetProcess, String workDir, String dataFileName) async {
    final log = Logger('interactor');
    final wrappersDir = io.Directory('${locationProperties.cacheDir}/wrappers');
    if (!wrappersDir.existsSync()) {
      wrappersDir.createSync(recursive: true);
      posix.chmod(wrappersDir.absolute.path, '770');
    }
    final wrapperFile = io.File('${wrappersDir.path}/interactor_wrapper.py');
    if (!wrapperFile.existsSync()) {
      final content = assetsLoader.fileAsBytes('interactor_wrapper.py');
      wrapperFile.writeAsBytesSync(content);
      posix.chmod(wrapperFile.absolute.path, '660');
    }

    final targetPid = await targetProcess.realPid;
    if (targetPid == -1) {
      log.severe('target pid is not valid');
      return (){};
    }

    final arguments = [
      wrapperFile.path, interactorPy,
      workDir, '$targetPid',  dataFileName,
    ];

    final interactorProcess = await io.Process.start(
      'python3',
      arguments,
      runInShell: true,
    );

    void targetStdoutConsumer(List<int> data) {
      interactorProcess.stdin.add(data);
      interactorProcess.stdin.flush();
    }

    void targetStdinProducer(List<int> data) {
      targetProcess.writeToStdin(data);
    }

    targetProcess.attachStdoutConsumer(targetStdoutConsumer);
    interactorProcess.stdout.listen(targetStdinProducer);

    void interactorShutdown() async {
      io.sleep(Duration(milliseconds: 250));
      interactorProcess.kill(io.ProcessSignal.sigterm);
      int exitCode = await interactorProcess.exitCode;
      if (exitCode != 0) {
        log.severe('interactor finished with exit code $exitCode');
      }
      else {
        log.fine('interactor successfully finished');
      }
    }

    return interactorShutdown;
  }
}

class InteractorFactory {
  final GraderLocationProperties locationProperties;

  InteractorFactory({required this.locationProperties});

  AbstractInteractor getInteractor(String fileName) {
    if (fileName.endsWith('.py')) {
      return PythonInteractor(locationProperties: locationProperties, interactorPy: fileName);
    }
    else {
      throw UnimplementedError('interactors other than Python not implemented');
    }
  }
}