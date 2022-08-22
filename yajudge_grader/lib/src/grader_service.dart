import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'grader_extra_configs.dart';
import 'chrooted_runner.dart';
import 'grading_worker.dart';
import 'problem_loader.dart';
import 'simple_runner.dart';

import 'abstract_runner.dart';
import 'submission_processor.dart';

const reconnectTimeout = Duration(seconds: 5);

class TokenAuthGrpcInterceptor implements ClientInterceptor {
  final String _token;
  final Logger log = Logger('GraderExternalApiClient');

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
    return invoker(method, request, newOptions)..onError((error, stackTrace) {
      log.severe('error accessing method ${method.path}: $error, stacktrace: $stackTrace');
      return Future.error(error!);
    });
  }

  CallOptions getNewOptions(CallOptions options) {
    return options.mergedWith(CallOptions(metadata: {
      'token': _token,
    }));
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
  final ServiceProperties serviceProperties;
  final DefaultBuildProperties defaultBuildProperties;
  final DefaultRuntimeProperties defaultRuntimeProperties;
  int _idleWorkersCount = 0;

  late final CourseContentProviderClient contentService;
  late final SubmissionManagementClient submissionsService;

  late final double _performanceRating;
  Timer? _statusPushTimer;
  static String? serviceLogFilePath;  // to recreate log object while in isolate


  bool shuttingDown = false;
  int shutdownExitCode = 0;

  int availableWorkersCount = 1;

  GraderService({
    required this.rpcProperties,
    required this.locationProperties,
    required this.identityProperties,
    required this.jobsConfig,
    required this.serviceProperties,
    required this.defaultLimits,
    required this.defaultBuildProperties,
    required this.defaultRuntimeProperties,
    this.overrideLimits,
    required this.defaultSecurityContext,
  }) {
    final coursesEndpoint = rpcProperties.endpoints['yajudge.CourseContentProvider']!;
    final submissionsEndpoint = rpcProperties.endpoints['yajudge.SubmissionManagement']!;
    final interceptor = TokenAuthGrpcInterceptor(rpcProperties.privateToken);
    if (coursesEndpoint.connectionEquals(submissionsEndpoint)) {
      // connect once and use endpoint for both services
      final clientChannel = connectToEndpoint(coursesEndpoint);
      contentService = CourseContentProviderClient(clientChannel, interceptors: [interceptor]);
      submissionsService = SubmissionManagementClient(clientChannel, interceptors: [interceptor]);
    }
    else {
      final coursesChannel = connectToEndpoint(coursesEndpoint);
      contentService = CourseContentProviderClient(coursesChannel, interceptors: [interceptor]);
      final submissionsChannel = connectToEndpoint(submissionsEndpoint);
      submissionsService = SubmissionManagementClient(submissionsChannel, interceptors: [interceptor]);
    }
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
    log.info('estimating performance rating, this will take some time...');
    _performanceRating = estimatePerformanceRating();
    log.info('performance rating: $_performanceRating');
    int maxWorkersCount = estimateWorkersCount();
    availableWorkersCount = jobsConfig.workers;
    if (availableWorkersCount <= 0 || availableWorkersCount > maxWorkersCount) {
      availableWorkersCount = maxWorkersCount;
    }
    _idleWorkersCount = availableWorkersCount;
  }

  static int estimateWorkersCount() {
    return io.Platform.numberOfProcessors;
  }

  static ClientChannel connectToEndpoint(Endpoint endpoint) {
    if (endpoint.isUnix) {
      String path = endpoint.unixPath;
      final unixAddress = io.InternetAddress(path, type: io.InternetAddressType.unix);
      return ClientChannel(unixAddress,
        port: 0,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
      );
    }
    else {
      String host = endpoint.host;
      if (host.isEmpty) {
        host = 'localhost';
      }
      int port = endpoint.port;
      bool useSsl = endpoint.useSsl;
      return GrpcOrGrpcWebClientChannel.toSingleEndpoint(
        host: host,
        port: port,
        transportSecure: useSsl,
      );
    }
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
        '${record.time}: ${record.level.name} - ${record.loggerName}: ${record.message}\n';
      }
      else {
        messageLine =
        '${record.time}: ${record.level.name} - [$isolateName] ${record.loggerName}: ${record.message}\n';
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
      if (serviceProperties.pidFilePath != null) {
        io.File(serviceProperties.pidFilePath!).deleteSync();
      }
      io.exit(shutdownExitCode);
    }
  }

  ConnectedServiceProperties graderProperties() => ConnectedServiceProperties(
    role: ServiceRole.SERVICE_GRADING,
    name: identityProperties.name,
    platform: GradingPlatform(arch: identityProperties.arch),
    performanceRating: _performanceRating,
    archSpecificOnlyJobs: jobsConfig.archSpecificOnly,
    numberOfWorkers: availableWorkersCount,
  );

  Future<ServiceStatus> waitForAnyWorkerIdle() async {
    final completer = Completer<ServiceStatus>();
    bool checkForReady() {
      if (shuttingDown) {
        completer.complete(ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN);
        return true;
      }
      if (_idleWorkersCount > 0) {
        completer.complete(ServiceStatus.SERVICE_STATUS_IDLE);
        return true;
      }
      return false;
    }
    if (!checkForReady()) {
      Timer.periodic(Duration(milliseconds: 250), (timer) {
        if (checkForReady()) {
          timer.cancel();
        }
      });
    }
    return completer.future;
  }

  Future<void> serveSubmissionsStream() async {
    final masterStream = submissionsService.receiveSubmissionsToProcess(graderProperties());
    _statusPushTimer?.cancel();
    _statusPushTimer = Timer.periodic(Duration(seconds: 10), (_) {
      pushGraderStatus();
    });

    final submissionsInProgress = <int>{};

    try {
      await pushGraderStatus();
      await for (Submission submission in masterStream) {
        int submissionId = submission.id.toInt();
        if (submissionsInProgress.contains(submissionId)) {
          continue;  // prevent periodical push of the same submission
        }
        waitForAnyWorkerIdle();
        if (shuttingDown) {
          return;
        }
        submissionsInProgress.add(submissionId);
        log.info('processing submission ${submission.id} from master');
        processSubmission(submission).then((result) async {
          try {
            await submissionsService.updateGraderOutput(result);
          }
          catch (e) {
            log.severe('cant send back grader output on submission ${result.id} '
                'with status ${result.status.name} (${result.status.value}): $e'
            );
          }
          submissionsInProgress.remove(submissionId);
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
        log.severe('got unhandled error $error');
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

  Future<void> pushGraderStatus() async {
    bool pushOK = false;
    while (!shuttingDown && !pushOK) {
      ServiceStatus status = ServiceStatus.SERVICE_STATUS_UNKNOWN;
      if (shuttingDown) {
        status = ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN;
      }
      else {
        status = isIdle()? ServiceStatus.SERVICE_STATUS_IDLE : ServiceStatus.SERVICE_STATUS_BUSY;
      }
      try {
        await submissionsService.setExternalServiceStatus(ConnectedServiceStatus(
          properties: graderProperties(),
          status: status,
          capacity: _idleWorkersCount,
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
    return _idleWorkersCount > 0;
  }

  bool isBusy() {
    return !isIdle();
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

  Future<Submission> processSubmission(Submission submission) async {
    submission = submission.deepCopy();
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;

    log.info('processing submission ${submission.id} $courseId/$problemId');

    final problemLoader = ProblemLoader(
      submission: submission,
      contentService: contentService,
      runner: createRunner(submission, locationProperties),
      locationProperties: locationProperties,
      defaultSecurityContext: defaultSecurityContext,
      buildProperties: defaultBuildProperties,
    );

    await problemLoader.loadProblemData();

    final singleThreaded = availableWorkersCount == 1;

    if (!singleThreaded) {
      final currentStatus = await waitForAnyWorkerIdle();
      if (currentStatus == ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN) {
        return Future.error('server shutting down');
      }
    }

    // these two fields should be overwritten by worker if processing success
    submission.status = SolutionStatus.CHECK_FAILED;
    submission.buildErrorLog = 'submission processing not completed';

    if (singleThreaded) {
      final runner = createRunner(
          submission,
          locationProperties
      );
      final submissionProcessor = SubmissionProcessor(
        runner: runner,
        locationProperties: locationProperties,
        defaultLimits: defaultLimits,
        defaultBuildProperties: defaultBuildProperties,
        defaultRuntimeProperties: defaultRuntimeProperties,
        defaultSecurityContext: defaultSecurityContext,
      );
      return submissionProcessor.processSubmission(submission);
    }
    else {
      final job = WorkerRequest(
        submission: submission,
        locationProperties: locationProperties,
        defaultSecurityContext: defaultSecurityContext,
        defaultBuildProperties: defaultBuildProperties,
        defaultRuntimeProperties: defaultRuntimeProperties,
        defaultLimits: defaultLimits,
      );

      final worker = Worker(submission);
      _idleWorkersCount --;
      final completer = Completer<Submission>();
      worker.process(job).then((value) {
        _idleWorkersCount ++;
        completer.complete(value);
      }, onError: (error, stackTrace) {
        _idleWorkersCount ++;
        completer.completeError(error, stackTrace);
      });
      return completer.future;
    }
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('grader shutting down due to $reason');
    shuttingDown = true;
    try {
      await submissionsService.setExternalServiceStatus(ConnectedServiceStatus(
        properties: graderProperties(),
        status: ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN,
      ));
    } catch (_) {

    }
    shutdownExitCode = error ? 1 : 0;
    io.sleep(Duration(seconds: 2));
    io.exit(shutdownExitCode);
  }

}
