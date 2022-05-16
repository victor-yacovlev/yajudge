import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'grader_extra_configs.dart';
import 'chrooted_runner.dart';
import 'simple_runner.dart';
import 'submission_processor.dart';
import 'package:path/path.dart' as path;

import 'abstract_runner.dart';

const ReconnectTimeout = Duration(seconds: 5);

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

class GraderService {
  final Logger log = Logger('GraderService');

  final RpcProperties rpcProperties;
  final GraderLocationProperties locationProperties;
  final GraderIdentityProperties identityProperties;
  final GradingLimits defaultLimits;
  final GradingLimits? overrideLimits;
  final SecurityContext defaultSecurityContext;
  final CompilersConfig compilersConfig;
  final ServiceProperties serviceProperties;
  final bool usePidFile;
  final bool processLocalInboxOnly;

  late final ClientChannel masterServer;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;

  late final double _performanceRating;
  GraderStatus _graderStatus = GraderStatus.Unknown;
  Timer? _statusPushTimer;


  bool shuttingDown = false;
  int shutdownExitCode = 0;

  GraderService({
    required this.rpcProperties,
    required this.locationProperties,
    required this.identityProperties,
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
      Future.delayed(ReconnectTimeout).then((_) => serveSupervised());
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

  Future<void> serveIncomingSubmissions() async {
    final localInboxDir = io.Directory('${locationProperties.workDir}/inbox');
    final localDoneDir = io.Directory('${locationProperties.workDir}/done');
    while (!shuttingDown) {
      bool processed = false;
      Submission submission = Submission();

      // Check submission from master server
      if (!processLocalInboxOnly) {
        submission =
        await submissionsService.takeSubmissionToGrade(GraderProperties(
          name: identityProperties.name,
          platform: GradingPlatform(arch: identityProperties.arch),
        ));
        if (submission.id.toInt() > 0) {
          submission = await processSubmission(submission);
          submission = submission.copyWith((s) {
            s.graderName = identityProperties.name;
          });
          await submissionsService.updateGraderOutput(submission);
          processed = true;
        }
      }

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
          submission = await processSubmission(localSubmission.submission, localSubmission.gradingLimits);
          doneFile.writeAsBytesSync(submission.writeToBuffer());
          inboxFile.deleteSync();
          processed = true;
        }
      }

      // Wait and retry if there is no submissions
      if (!processed) {
        io.sleep(Duration(seconds: 2));
      }
    }
  }

  GraderProperties graderProperties() => GraderProperties(
    name: identityProperties.name,
    platform: GradingPlatform(arch: identityProperties.arch),
    performanceRating: _performanceRating,
  );

  Future<void> serveSubmissionsStream() async {
    final masterStream = submissionsService.receiveSubmissionsToGrade(graderProperties());
    _statusPushTimer?.cancel();
    _statusPushTimer = Timer.periodic(Duration(seconds: 10), (_) {
      pushGraderStatus();
    });


    try {
      await setGraderStatus(GraderStatus.Idle);
      await for (Submission submission in masterStream) {
        while (isBusy()) {
          io.sleep(Duration(seconds: 1));
        }
        if (shuttingDown) {
          setGraderStatus(GraderStatus.ShuttingDown);
          return;
        }
        log.info('processing submission ${submission.id} from master');
        final result = await processSubmission(submission);
        await submissionsService.updateGraderOutput(result);
        setGraderStatus(shuttingDown? GraderStatus.ShuttingDown : GraderStatus.Idle);
        log.info('done processing submission ${submission.id} from master');
      }
    }
    catch (error) {
      if (isConnectionError(error)) {
        // pushGraderStatus has implementation to check when connection will restored
        log.info('lost connection to master server');
        pushGraderStatus();
        log.info('restored connection to master server');
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
          setGraderStatus(GraderStatus.Busy);
          log.info('processing local inbox submission $name');
          final inboxData = inboxFile.readAsBytesSync();
          final localSubmission = LocalGraderSubmission.fromBuffer(inboxData);
          final submission = await processSubmission(localSubmission.submission, localSubmission.gradingLimits);
          doneFile.writeAsBytesSync(submission.writeToBuffer());
          inboxFile.deleteSync();
          setGraderStatus(shuttingDown? GraderStatus.ShuttingDown : GraderStatus.Idle);
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

  Future<void> setGraderStatus(GraderStatus status) async {
    _graderStatus = status;
    await pushGraderStatus();
  }

  Future<void> pushGraderStatus() async {
    bool pushOK = false;
    while (!shuttingDown && !pushOK) {
      try {
        await submissionsService.setGraderStatus(GraderStatusMessage(
          properties: graderProperties(),
          status: _graderStatus,
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
    return _graderStatus==GraderStatus.Idle;
  }

  bool isBusy() {
    return _graderStatus==GraderStatus.Busy;
  }

  Future<Submission> processSubmission(Submission submission, [GradingLimits? overrideLimits]) async {
    final courseId = submission.course.dataId;
    final problemId = submission.problemId;

    log.info('processing submission ${submission.id} $courseId/$problemId');

    AbstractRunner runner;
    if (io.Platform.isLinux) {
      runner = ChrootedRunner(
        locationProperties: locationProperties,
        courseId: courseId,
        problemId: problemId,
      );
    }
    else {
      runner = SimpleRunner(locationProperties: locationProperties);
    }

    SubmissionProcessor processor = SubmissionProcessor(
      submission: submission,
      runner: runner,
      locationProperties: locationProperties,
      defaultLimits: defaultLimits,
      defaultSecurityContext: defaultSecurityContext,
      compilersConfig: compilersConfig,
      coursesService: coursesService,
      overrideLimits: overrideLimits,
    );

    await processor.loadProblemData();
    await processor.processSubmission();

    Submission result = processor.submission;
    log.info('done processing submission ${submission.id} with status ${result.status.name}');
    return result;
  }

  void shutdown(String reason, [bool error = false]) async {
    log.info('grader shutting down due to $reason');
    shuttingDown = true;
    setGraderStatus(GraderStatus.ShuttingDown);
    shutdownExitCode = error ? 1 : 0;
    io.sleep(Duration(seconds: 2));
    io.exit(shutdownExitCode);
  }

}
