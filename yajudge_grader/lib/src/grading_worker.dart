import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'submission_processor.dart';
import 'chrooted_runner.dart';
import 'grader_extra_configs.dart';
import 'grader_service.dart';

class WorkerRequest {
  final Submission submission;
  final GraderLocationProperties locationProperties;
  final CompilersConfig compilersConfig;
  final SecurityContext defaultSecurityContext;
  final GradingLimits defaultLimits;
  final GradingLimits? overrideLimits;
  late final String cgroupRoot;
  late final String logFilePath;
  late final SendPort sendPort;

  WorkerRequest({
    required this.submission,
    required this.locationProperties,
    required this.compilersConfig,
    required this.defaultSecurityContext,
    required this.defaultLimits,
    required this.overrideLimits,
  });
}

class WorkerResponse {
  final Submission? submission;
  final Object? error;

  WorkerResponse.ok(this.submission): error = null;
  WorkerResponse.error(this.error): submission = null;

  @override
  String toString() {
    if (submission != null) {
      return '${submission!.id} with status ${submission!.status.value} (${submission!.status.name})';
    } else {
      return 'error $error';
    }
  }

  void complete(Completer<Submission> completer) {
    if (submission != null) {
      completer.complete(submission!);
    } else {
      completer.completeError(error!);
    }
  }
}

class Worker {

  final Submission submission;

  Worker(this.submission);

  String get isolateName {
    return 'isolate for ${submission.id}';
  }

  void _runInThread(WorkerRequest request) async {
    final sendPort = request.sendPort;
    _setupStaticFieldsForIsolate(request);
    final response = await _runGradingProcessor(request);
    Isolate.exit(sendPort, response);
  }

  void _setupStaticFieldsForIsolate(WorkerRequest request) {
    GraderService.configureLogger(request.logFilePath, Isolate.current.debugName!);
    ChrootedRunner.cgroupRoot = request.cgroupRoot;
  }

  Future<WorkerResponse> _runGradingProcessor(WorkerRequest request) async {
    final log = Logger('WorkerIsolate');
    log.info('processing request submission ${request.submission.id}');
    final runner = GraderService.createRunner(
        request.submission,
        request.locationProperties
    );
    final processor = SubmissionProcessor(
      submission: request.submission,
      runner: runner,
      locationProperties: request.locationProperties,
      defaultLimits: request.defaultLimits,
      defaultSecurityContext: request.defaultSecurityContext,
      compilersConfig: request.compilersConfig,
      overrideLimits: request.overrideLimits,
    );
    WorkerResponse response;
    try {
      await processor.processSubmission();
      final result = processor.submission;
      response = WorkerResponse.ok(result);
    } catch (error) {
      response = WorkerResponse.error(error);
    }
    if (response.submission!=null) {
      log.fine('submission ${response.submission!.id} done with status ${response.submission!.status.value} (${response.submission!.status.name})');
    }
    else {
      log.severe('submission ${request.submission.id} processing failed: ${response.error}');
    }
    return response;
  }

  Future<Submission> process(WorkerRequest request) {
    final resultCompleter = Completer<Submission>();
    final receivePort = ReceivePort();
    final fullRequest = request
      ..sendPort=receivePort.sendPort
      ..logFilePath=GraderService.serviceLogFilePath!
      ..cgroupRoot=ChrootedRunner.cgroupRoot
    ;
    receivePort.listen((message) {
      if (message is WorkerResponse) {
        message.complete(resultCompleter);
      }
    });
    Isolate.spawn(
      _runInThread,
      fullRequest,
      debugName: isolateName,
    );
    return resultCompleter.future;
  }

}
