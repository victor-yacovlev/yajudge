import 'dart:async';
import 'dart:io' as io;
import 'dart:math';
import 'dart:isolate';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'grader_extra_configs.dart';
import 'chrooted_runner.dart';
import 'problem_loader.dart';
import 'simple_runner.dart';
import 'submission_processor.dart';
import 'package:path/path.dart' as path;

import 'abstract_runner.dart';

const reconnectTimeout = Duration(seconds: 5);

class TokenAuthGrpcInterceptor implements ClientInterceptor {
  final String _token;

  TokenAuthGrpcInterceptor(this._token) : super();

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
      ClientMethod<Q, R> method,
      Stream<Q> requests,
      CallOptions options,
      ClientStreamingInvoker<Q, R> invoker) {
    final newOptions = getNewOptions(options);
    return invoker(method, requests, newOptions);
  }

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    final newOptions = getNewOptions(options);
    return invoker(method, request, newOptions);
  }

  CallOptions getNewOptions(CallOptions options) {
    return options.mergedWith(CallOptions(metadata: {
      'token': _token,
    }));
  }
}

class _ServiceWorkerRequest {
  final Submission submission;
  final GraderLocationProperties locationProperties;
  final CompilersConfig compilersConfig;
  final SecurityContext defaultSecurityContext;
  final GradingLimits defaultLimits;
  final GradingLimits? overrideLimits;
  late final String cgroupRoot;
  late final String logFilePath;

  _ServiceWorkerRequest({
    required this.submission,
    required this.locationProperties,
    required this.compilersConfig,
    required this.defaultSecurityContext,
    required this.defaultLimits,
    required this.overrideLimits,
  });
}

class _ServiceWorkerResponse {
  final Submission? submission;
  final Object? error;

  _ServiceWorkerResponse.ok(this.submission): error = null;
  _ServiceWorkerResponse.error(this.error): submission = null;
}

class _ServiceWorker {
  GraderStatus _status = GraderStatus.Unknown;

  get status => _status;
  SendPort? _sendPort;
  Completer<_ServiceWorkerResponse>? _resultCompleter;
  final String workerName;

  _ServiceWorker(this.workerName);

  Future<void> initialize() async {
    final sendPortCompleter = Completer<SendPort>();
    ReceivePort isolateToMainStream = ReceivePort();

    isolateToMainStream.listen((data) {
      if (data is SendPort) {
        SendPort mainToIsolateStream = data;
        sendPortCompleter.complete(mainToIsolateStream);
      } else if (data is _ServiceWorkerResponse) {
        _resultCompleter?.complete(data);
        _resultCompleter = null;
        _status = GraderStatus.Idle;
      }
    });

    await Isolate.spawn(
      _run,
      isolateToMainStream.sendPort,
      debugName: 'isolate $workerName',
    );
    _sendPort = await sendPortCompleter.future;
    _status = GraderStatus.Idle;
  }

  void _run(SendPort isolateToMainStream) {
    ReceivePort mainToIsolateStream = ReceivePort();
    isolateToMainStream.send(mainToIsolateStream.sendPort);

    mainToIsolateStream.listen((data) async {
      if (data is _ServiceWorkerRequest) {
        final request = data;
        if (GraderService.serviceLogFilePath == null) {
          GraderService.configureLogger(request.logFilePath, Isolate.current.debugName!);
        }
        final runner = GraderService.createRunner(
            request.submission,
            request.locationProperties
        );
        if (runner is ChrootedRunner) {
          ChrootedRunner.cgroupRoot = request.cgroupRoot;
        }
        final processor = SubmissionProcessor(
          submission: request.submission,
          runner: runner,
          locationProperties: request.locationProperties,
          defaultLimits: request.defaultLimits,
          defaultSecurityContext: request.defaultSecurityContext,
          compilersConfig: request.compilersConfig,
          overrideLimits: request.overrideLimits,
        );
        try {
          await processor.processSubmission();
          final result = processor.submission;
          isolateToMainStream.send(_ServiceWorkerResponse.ok(result));
        }
        catch (error) {
          isolateToMainStream.send(_ServiceWorkerResponse.error(error));
        }
      } else if (data is GraderStatus && data==GraderStatus.ShuttingDown) {
        _status = GraderStatus.ShuttingDown;
        Isolate.exit();
      }
    });
  }

  void sendRequest(_ServiceWorkerRequest request) {
    assert(_sendPort!=null);
    _sendPort!.send(
        request
          ..logFilePath = GraderService.serviceLogFilePath!
          ..cgroupRoot = ChrootedRunner.cgroupRoot
    );
  }

  Future<_ServiceWorkerResponse> process(_ServiceWorkerRequest request) {
    _status = GraderStatus.Busy;
    _resultCompleter = Completer<_ServiceWorkerResponse>();
    sendRequest(request);
    return _resultCompleter!.future;
  }

  void shutdown() {
    assert(_sendPort!=null);
    _sendPort!.send(GraderStatus.ShuttingDown);
  }

}


class GraderService {
  final Logger log = Logger('GraderService');

  final RpcProperties rpcProperties;
  final GraderLocationProperties locationProperties;
  final GraderIdentityProperties identityProperties;
  final JobsConfig jobsConfig;
  final GradingLimits defaultLimits;
  final GradingLimits? overrideLimits;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;
  final ServiceProperties serviceProperties;
  final bool usePidFile;
  final bool processLocalInboxOnly;
  final List<_ServiceWorker> _workers = [];

  late final ClientChannel masterServer;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;

  late final double _performanceRating;
  Timer? _statusPushTimer;
  static String? serviceLogFilePath;  // to recreate log object while in isolate


  bool shuttingDown = false;
  int shutdownExitCode = 0;

  GraderService({
    required this.rpcProperties,
    required this.locationProperties,
    required this.identityProperties,
    required this.jobsConfig,
    required this.serviceProperties,
    required this.usePidFile,
    required this.defaultLimits,
    this.overrideLimits,
    required this.defaultSecurityContext,
    required this.compilersConfig,
    this.processLocalInboxOnly = false,
  }) {
    masterServer = GrpcOrGrpcWebClientChannel.toSingleEndpoint(
        host: rpcProperties.host,
        port: rpcProperties.port,
        transportSecure: rpcProperties.useSsl,
    );
    final interceptor = TokenAuthGrpcInterceptor(rpcProperties.privateToken);
    coursesService =
        CourseManagementClient(masterServer, interceptors: [interceptor]);
    submissionsService =
        SubmissionManagementClient(masterServer, interceptors: [interceptor]);
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
    log.info('estimating performance rating, this will take some time...');
    _performanceRating = estimatePerformanceRating();
    log.info('performance rating: $_performanceRating');
    int maxWorkersCount = estimateWorkersCount();
    int availableWorkersCount = jobsConfig.workers;
    if (availableWorkersCount <= 0 || availableWorkersCount > maxWorkersCount) {
      availableWorkersCount = maxWorkersCount;
    }
    for (int i=0; i<availableWorkersCount; i++) {
      _workers.add(_ServiceWorker('$i'));
      _workers.last.initialize();
    }
  }

  static int estimateWorkersCount() {
    return io.Platform.numberOfProcessors;
  }

  static double estimatePerformanceRating() {
    // calculate maxPrimesCount prime numbers and measure a time in milliseconds
    // returns 1_000_000/time (higher is better performance)
    const maxPrimesCount = 20000;
    int currentPrime = 2;
    int primesFound = 0;
    final startTime = DateTime.now();
    while (primesFound < maxPrimesCount) {
      bool isPrime = true;
      for (int divider=2; divider<currentPrime; divider++) {
        isPrime = (currentPrime % divider) > 0;
        if (!isPrime) {
          break;
        }
      }
      if (isPrime) {
        primesFound ++;
      }
      currentPrime ++;
    }
    final endTime = DateTime.now();
    final milliseconds = endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch;
    double result = 1000000.0 / milliseconds;
    return result;
  }

  static void configureLogger(String logFilePath, String isolateName) {
    serviceLogFilePath = logFilePath;
    if (logFilePath.isNotEmpty && logFilePath!='stdout') {
      if (isolateName.isEmpty) {
        print('Using log file $logFilePath');
      }
      final logFile = io.File(logFilePath);
      final openedFile = logFile.openSync(mode: io.FileMode.writeOnlyAppend);
      _initializeLogger(openedFile, isolateName);
      if (isolateName.isEmpty) {
        print(
            'Logger initialized so next non-critical messages will be in $logFilePath');
      }
    }
    else {
      if (isolateName.isEmpty) {
        print('Log file not set so will use stdout for logging');
      }
      _initializeLogger(null, isolateName);
    }
  }

  static void _initializeLogger(io.RandomAccessFile? outFile, String isolateName) {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) async {
      String messageLine;
      if (isolateName.isEmpty) {
        messageLine =
        '${record.time}: ${record.level.name} - ${record.message}\n';
      }
      else {
        messageLine =
        '${record.time}: ${record.level.name} - [$isolateName] ${record.message}\n';
      }
      try {
        if (outFile != null) {
          outFile.lockSync();
          outFile.writeStringSync(messageLine);
          outFile.flushSync();
          outFile.unlockSync();
        } else {
          io.stdout.nonBlocking.write(messageLine);
        }
      }
      catch (error) {
        print('LOG: $messageLine');
        print('Got logger error: $error');
      }
    });
  }

  void handleGraderError(Object? error) {
    Level logLevel = Level.SEVERE;
    bool waitBeforeRestart = false;
    if (error is GrpcError) {
      if (error.code == StatusCode.unauthenticated) {
        logLevel = Level.SHOUT;
      }
      if (error.code == StatusCode.unavailable) {
        waitBeforeRestart = true;
      }
    }
    log.log(logLevel, '$error');
    if (logLevel == Level.SHOUT) {
      io.exit(5);
    }
    if (waitBeforeRestart) {
      Future.delayed(reconnectTimeout).then((_) => serveSupervised());
    } else {
      serveSupervised();
    }
  }

  void serveSupervised() {
    runZonedGuarded(() async {
      await serveSubmissionsStream();
      // await serveIncomingSubmissions();
    },
    (error, stackTrace) {
      handleGraderError(e);
    })!.then((_) {
      checkForShutdown();
      io.sleep(Duration(seconds: 2));
      serveSupervised();
    });
  }

  void checkForShutdown() {
    if (shuttingDown) {
      if (usePidFile && serviceProperties.pidFilePath!='disabled') {
        io.File(serviceProperties.pidFilePath).deleteSync();
      }
      io.exit(shutdownExitCode);
    }
  }

  void processLocalInboxSubmission() {
    final localInboxDir = io.Directory('${locationProperties.workDir}/inbox');
    final localDoneDir = io.Directory('${locationProperties.workDir}/done');
    // Check submissions from local file system
    if (localInboxDir.existsSync()) {
      for (final entry in localInboxDir.listSync()) {
        String name = path.basename(entry.path);
        final inboxFile = io.File('${localInboxDir.path}/$name');
        if (!localDoneDir.existsSync()) {
          localDoneDir.createSync(recursive: true);
        }
        final doneFile = io.File('${localDoneDir.path}/$name');
        final inboxData = inboxFile.readAsBytesSync();
        final localSubmission = LocalGraderSubmission.fromBuffer(inboxData);
        final futureResult = processSubmission(localSubmission.submission, localSubmission.gradingLimits);
        futureResult.then((result) {
          doneFile.writeAsBytesSync(result.writeToBuffer());
          inboxFile.deleteSync();
        });
      }
    }
  }

  // Future<void> serveIncomingSubmissions() async {
  //
  //   while (!shuttingDown) {
  //     bool processed = false;
  //     Submission submission = Submission();
  //
  //     // Check submission from master server
  //     if (!processLocalInboxOnly) {
  //       submission =
  //       await submissionsService.takeSubmissionToGrade(GraderProperties(
  //         name: identityProperties.name,
  //         platform: GradingPlatform(arch: identityProperties.arch),
  //       ));
  //       if (submission.id.toInt() > 0) {
  //         submission = await processSubmission(submission);
  //         submission = submission.copyWith((s) {
  //           s.graderName = identityProperties.name;
  //         });
  //         await submissionsService.updateGraderOutput(submission);
  //         processed = true;
  //       }
  //     }
  //
  //     // Wait and retry if there is no submissions
  //     if (!processed) {
  //       io.sleep(Duration(seconds: 2));
  //     }
  //   }
  // }

  GraderProperties graderProperties() => GraderProperties(
    name: identityProperties.name,
    platform: GradingPlatform(arch: identityProperties.arch),
    performanceRating: _performanceRating,
    archSpecificOnlyJobs: jobsConfig.archSpecificOnly,
  );

  Future<GraderStatus> waitForAnyWorkerIdle() async {
    while (isBusy()) {
      io.sleep(Duration(milliseconds: 250));
    }
    if (shuttingDown) {
      return GraderStatus.ShuttingDown;
    }
    else {
      return GraderStatus.Idle;
    }
  }

  Future<void> serveSubmissionsStream() async {
    final masterStream = submissionsService.receiveSubmissionsToGrade(graderProperties());
    _statusPushTimer?.cancel();
    _statusPushTimer = Timer.periodic(Duration(seconds: 10), (_) {
      pushGraderStatus();
    });


    try {
      await pushGraderStatus();
      await for (Submission submission in masterStream) {
        waitForAnyWorkerIdle();
        if (shuttingDown) {
          return;
        }
        log.info('processing submission ${submission.id} from master');
        processSubmission(submission).then((result) async {
          await submissionsService.updateGraderOutput(result);
          await pushGraderStatus();
          log.info('done processing submission ${submission.id} from master');
        });
      }
    }
    catch (error) {
      if (isConnectionError(error)) {
        // pushGraderStatus has implementation to check when connection will restored
        pushGraderStatus();
        return; // restart connection by supervisor
      }
      else {
        // log error and become restarted by supervisor
        rethrow;
      }
    }

  }
  
  bool isConnectionError(dynamic error) {
    bool serviceUnavailableError = error is GrpcError && error.code==StatusCode.unavailable;
    bool connectionLostError = error is GrpcError && error.code==StatusCode.unknown
        && error.message!=null && error.message!.toLowerCase().startsWith('http/2 error');
    bool httpDeadlineError = error is GrpcError && error.code==StatusCode.deadlineExceeded;
    return serviceUnavailableError || connectionLostError || httpDeadlineError;
  }

  Future<void> processLocalInboxSubmissions() async {
    while (!shuttingDown) {
      bool processed = false;
      final localInboxDir = io.Directory('${locationProperties.workDir}/inbox');
      final localDoneDir = io.Directory('${locationProperties.workDir}/done');

      if (localInboxDir.existsSync()) {
        for (final entry in localInboxDir.listSync()) {
          if (!isIdle()) {
            break;
          }
          String name = path.basename(entry.path);
          final inboxFile = io.File('${localInboxDir.path}/$name');
          if (!localDoneDir.existsSync()) {
            localDoneDir.createSync(recursive: true);
          }
          final doneFile = io.File('${localDoneDir.path}/$name');
          await pushGraderStatus();
          log.info('processing local inbox submission $name');
          final inboxData = inboxFile.readAsBytesSync();
          final localSubmission = LocalGraderSubmission.fromBuffer(inboxData);
          final submission = await processSubmission(localSubmission.submission, localSubmission.gradingLimits);
          doneFile.writeAsBytesSync(submission.writeToBuffer());
          inboxFile.deleteSync();
          await pushGraderStatus();
          log.info('done processing local inbox submission $name');
          processed = true;
        }
      }
      // wait and retry if there is no submissions
      if (!processed && !shuttingDown) {
        io.sleep(Duration(seconds: 2));
      }
    }
  }

  Future<void> pushGraderStatus() async {
    bool pushOK = false;
    while (!shuttingDown && !pushOK) {
      GraderStatus status = GraderStatus.Unknown;
      if (shuttingDown) {
        status = GraderStatus.ShuttingDown;
      }
      else {
        status = isIdle()? GraderStatus.Idle : GraderStatus.Busy;
      }
      try {
        await submissionsService.setGraderStatus(GraderStatusMessage(
          properties: graderProperties(),
          status: status,
        ));
        pushOK = true;
      }
      catch (error) {
        pushOK = false;
        if (isConnectionError(error)) {
          io.sleep(Duration(seconds: 2));
        }
        else {
          rethrow;
        }
      }
    }
  }

  bool isIdle() {
    bool hasIdle = false;
    for (final worker in _workers) {
      if (worker.status == GraderStatus.Idle) {
        hasIdle = true;
        break;
      }
    }
    return hasIdle;
  }

  bool isBusy() {
    bool allBusy = true;
    for (final worker in _workers) {
      if (worker.status != GraderStatus.Busy) {
        allBusy = false;
        break;
      }
    }
    return allBusy;
  }

  static AbstractRunner createRunner(Submission submission, GraderLocationProperties locationProperties) {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;
    if (io.Platform.isLinux) {
      return ChrootedRunner(
        locationProperties: locationProperties,
        courseId: courseId,
        problemId: problemId,
      );
    }
    else {
      return SimpleRunner(locationProperties: locationProperties);
    }
  }

  Future<Submission> processSubmission(Submission submission, [GradingLimits? overrideLimits]) async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;

    log.info('processing submission ${submission.id} $courseId/$problemId');

    final problemLoader = ProblemLoader(
      submission: submission,
      coursesService: coursesService,
      runner: createRunner(submission, locationProperties),
      locationProperties: locationProperties,
      compilersConfig: compilersConfig,
      defaultSecurityContext: defaultSecurityContext,
    );

    await problemLoader.loadProblemData();

    _ServiceWorker? worker;
    do {
      waitForAnyWorkerIdle();
      for (final w in _workers) {
        if (w.status == GraderStatus.Idle) {
          worker = w;
          break;
        }
      }
    } while (worker == null);

    final job = _ServiceWorkerRequest(
      submission: submission,
      locationProperties: locationProperties,
      compilersConfig: compilersConfig,
      defaultSecurityContext: defaultSecurityContext,
      defaultLimits: defaultLimits,
      overrideLimits: overrideLimits,
    );

    final resultCompleter = Completer<Submission>();
    final workerResult = worker.process(job);

    workerResult.then((_ServiceWorkerResponse value) {
      if (value.submission != null) {
        resultCompleter.complete(value.submission!);
      } else {
        resultCompleter.completeError(value.error!);
      }
    });

    return resultCompleter.future;
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('grader shutting down due to $reason');
    shuttingDown = true;
    try {
      await submissionsService.setGraderStatus(GraderStatusMessage(
        properties: graderProperties(),
        status: GraderStatus.ShuttingDown,
      ));
    } catch (_) {

    }
    shutdownExitCode = error ? 1 : 0;
    io.sleep(Duration(seconds: 2));
    io.exit(shutdownExitCode);
  }

}
