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

class _ServiceWorker {
  GraderStatus _status = GraderStatus.Unknown;
  GraderStatus get status => _status;
  final log = Logger('_ServiceWorker');
  late final SendPort _requestsPort;
  late final ReceivePort _responsesPort;
  late final Isolate _isolate;
  final String debugName;
  Completer<Submission>? _resultCompleter;

  _ServiceWorker(this.debugName);

  void initialize() {
    _responsesPort = ReceivePort('responses port for $debugName');
    final futureIsolate = Isolate.spawn(
        _run,
        _responsesPort.sendPort,
        debugName: 'isolate $debugName',
    );
    futureIsolate.then((value) {
      _isolate = value;
    });
    futureIsolate.onError((error, stackTrace) {
      log.severe('cant start worker isolate: $error', error, stackTrace);
      return futureIsolate;
    });
    _responsesPort.listen(_handleMessageFromIsolate);
  }

  void shutdown() {
    _requestsPort.send(GraderStatus.ShuttingDown);
    io.sleep(Duration(seconds: 1));
    _isolate.kill();
  }

  void _handleMessageFromIsolate(dynamic message) {
    if (message is GraderStatus) {
      _status = message;
    }
    else if (message is SendPort) {
      _requestsPort = message;
    }
    else if (message is Submission) {
      assert(_resultCompleter!=null);
      _resultCompleter!.complete(message);
    }
    else if (message is Error) {
      if (_resultCompleter!=null) {
        _resultCompleter!.completeError(message);
      }
      else {
        throw message;
      }
    }
  }

  static void _run(SendPort resultsStreamWriter) async {
    final requestsPort = ReceivePort();
    resultsStreamWriter.send(requestsPort.sendPort);
    resultsStreamWriter.send(GraderStatus.Idle);
    await for (final message in requestsPort) {
      if (message is GraderStatus && message==GraderStatus.ShuttingDown) {
        Isolate.exit();
      }
      else if (message is Map) {
        resultsStreamWriter.send(GraderStatus.Busy);
        final submission = message['submission'] as Submission;
        final locationProperties = message['locationProperties'] as GraderLocationProperties;
        final defaultLimits = message['defaultLimits'] as GradingLimits;
        final defaultSecurityContext = message['defaultSecurityContext'] as SecurityContext;
        final compilersConfig = message['compilersConfig'] as CompilersConfig;
        final overrideLimits = message['overrideLimits'] as GradingLimits?;
        final processor = SubmissionProcessor(
          submission: submission,
          runner: GraderService.createRunner(submission, locationProperties),
          locationProperties: locationProperties,
          defaultLimits: defaultLimits,
          defaultSecurityContext: defaultSecurityContext,
          compilersConfig: compilersConfig,
          overrideLimits: overrideLimits,
        );
        Submission? result;
        Object? error;
        try {
          await processor.processSubmission();
          result = processor.submission;
        }
        catch (err) {
          error = err;
        }
        if (result != null) {
          resultsStreamWriter.send(result);
        }
        else {
          resultsStreamWriter.send(error);
        }
        resultsStreamWriter.send(GraderStatus.Idle);
      }
    }
  }

  Future<Submission> processSubmission(Map<String,dynamic> parameters) {
    _status = GraderStatus.Busy;
    _resultCompleter = Completer<Submission>();
    try {
      _requestsPort.send(parameters);
      return _resultCompleter!.future;
    } catch (error) {
      _resultCompleter = null;
      return Future.error(error);
    }
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

    final job = {
      'submission': submission,
      'locationProperties': locationProperties,
      'compilersConfig': compilersConfig,
      'defaultSecurityContext': defaultSecurityContext,
      'defaultLimits': defaultLimits,
      'overrideLimits': overrideLimits,
    };

    return worker.processSubmission(job);
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
