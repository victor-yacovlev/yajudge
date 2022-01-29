import 'dart:async';
import 'dart:io' as io;

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:grpc/grpc_or_grpcweb.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yajudge_grader/src/chrooted_runner.dart';
import 'package:yajudge_grader/src/submission_processor.dart';

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
  late final ClientChannel masterServer;
  late final CourseManagementClient coursesService;
  late final SubmissionManagementClient submissionsService;
  Map<String, CourseDataCacheItem> _courses = {};

  GraderService(
      {required this.rpcProperties,
      required this.locationProperties,
      required this.identityProperties}) {
    masterServer = GrpcOrGrpcWebClientChannel.grpc(
      rpcProperties.host,
      port: rpcProperties.port,
      options: ChannelOptions(
        credentials: const ChannelCredentials.insecure(),
      ),
    );
    final interceptor = TokenAuthGrpcInterceptor(rpcProperties.privateToken);
    coursesService =
        CourseManagementClient(masterServer, interceptors: [interceptor]);
    submissionsService =
        SubmissionManagementClient(masterServer, interceptors: [interceptor]);
    io.ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
    io.ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
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
      await serveIncomingSubmissions();
    }, (e, s) => handleGraderError(e))!
        .then((_) => serveSupervised());
  }

  Future<void> serveIncomingSubmissions() async {
    final graderProps = GraderProperties(
        name: identityProperties.name,
        platform: GradingPlatform(
          os: identityProperties.os,
          arch: identityProperties.arch,
          runtimes: identityProperties.runtimes,
          compilers: identityProperties.compilers,
        ));
    final stream = submissionsService.receiveSubmissionsToGrade(graderProps);
    try {
      await for (final submission in stream) {
        processSubmission(submission).then((Submission result) {
          submissionsService.updateGraderOutput(result);
        });
      }
    } finally {
      stream.cancel();
    }
  }

  Future<Submission> processSubmission(Submission submission) {
    return loadCourseData(submission.course.dataId).then((courseData) {
      final courseId = submission.course.dataId;
      final problemId = submission.problemId;
      ProblemData? problemData = findProblemById(courseData, problemId);
      if (problemData == null) {
        throw GrpcError.notFound('problem $problemId not found in $courseId');
      }
      log.info('processing submission ${submission.id} $courseId/$problemId');
      ChrootedRunner runner =
          ChrootedRunner(locationProperties: locationProperties);
      SubmissionProcessor processor = SubmissionProcessor(
        submission: submission,
        runner: runner,
        problemData: problemData,
        courseData: courseData,
      );
      return processor.submission;
    });
  }

  Future<CourseData> loadCourseData(String courseId) async {
    CourseDataCacheItem? cachedCourse;
    if (_courses.containsKey(courseId)) {
      cachedCourse = _courses[courseId]!;
    }
    Int64 timestamp = Int64(0);
    if (cachedCourse != null) {
      timestamp = Int64(
          cachedCourse.lastModified!.toUtc().millisecondsSinceEpoch ~/ 1000);
    }
    final response = await coursesService.getCourseFullContent(
      CourseContentRequest(
        courseDataId: courseId,
        cachedTimestamp: timestamp,
      ),
    );
    if (response.status == CourseContentStatus.HAS_DATA) {
      log.info('loaded course $courseId content from master server');
      cachedCourse = CourseDataCacheItem(
        data: response.data,
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          response.lastModified.toInt(),
          isUtc: true,
        ),
      );
      _courses[courseId] = cachedCourse;
    }
    if (cachedCourse == null) {
      throw GrpcError.notFound('cant load course $courseId from server');
    }
    return cachedCourse.data!;
  }

  void shutdown(String reason, [bool error = false]) async {
    masterServer.shutdown().timeout(Duration(seconds: 2), onTimeout: () {
      log.info('grader shutdown due to $reason');
      io.exit(error ? 1 : 0);
    });
  }
}
