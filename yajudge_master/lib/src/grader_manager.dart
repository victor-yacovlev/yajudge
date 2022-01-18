import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'service.dart';

class GraderConnection {
  final GraderProperties properties;
  final streamController = StreamController<Submission>(sync: true);

  GraderConnection(this.properties);

}

class GraderManager {
  final MasterService parent;
  final Logger log = Logger('GraderManager');
  List<GraderConnection> _graders = [];
  int _lastUsedIndex = -1;

  GraderManager({required this.parent});

  GraderConnection registerNewGrader(GraderProperties properties) {
    GraderConnection grader = GraderConnection(properties);
    log.info('connected grader ${properties.name}');
    grader.streamController.onCancel = () => deregisterGrader(grader);
    _graders.add(grader);
    return grader;
  }

  void deregisterGrader(GraderConnection connection) {
    _graders.remove(connection);
    log.info('disconnected grader ${connection.properties.name}');
    parent.submissionManagementService.unassignGrader(connection.properties.name);
  }

  void processSubmission(GraderConnection grader, Submission sub) {
    graderCanAcceptSubmission(sub, grader.properties)
        .then((bool canAccept) {
      if (canAccept) {
        int id = sub.id.toInt();
        String graderName = grader.properties.name;
        parent.submissionManagementService.assignGrader(id, graderName);
        grader.streamController.add(sub);
      }
    });
  }

  void checkForDelayedSubmissions(GraderConnection grader) {
    parent.submissionManagementService.getSubmissionsToGrade()
        .then((List<Submission> submissions) {
      for (Submission sub in submissions) {
        int graderIndex = (_lastUsedIndex + 1) % _graders.length;
        _lastUsedIndex = graderIndex;
        GraderConnection grader = _graders[graderIndex];
        processSubmission(grader, sub);
      }
    });
    String graderName = grader.properties.name;
    parent.submissionManagementService.getUnfinishedSubmissionsToGrade(graderName)
    .then((List<Submission> submissions) {
      for (Submission sub in submissions) {
        processSubmission(grader, sub);
      }
    });
  }

  Future<bool> graderCanAcceptSubmission(Submission sub, GraderProperties properties) async {
    ProblemData problem = await getProblemDataForSubmission(sub);
    bool platformMatch = true;
    bool osMatch = true;
    GradingPlatform platformRequired = problem.gradingOptions.platformRequired;
    GradingPlatform graderPlatform = properties.platform;
    if (platformRequired.arch != Arch.ARCH_ANY) {
      platformMatch = platformRequired.arch == graderPlatform.arch;
    }
    if (platformRequired.os != OS.OS_ANY) {
      switch (platformRequired.os) {
        case OS.OS_WINDOWS:
          osMatch = graderPlatform.os == OS.OS_WINDOWS; break;
        case OS.OS_LINUX:
          osMatch = graderPlatform.os == OS.OS_LINUX; break;
        case OS.OS_DARWIN:
          osMatch = graderPlatform.os == OS.OS_DARWIN; break;
        case OS.OS_BSD:
          osMatch = graderPlatform.os == OS.OS_BSD; break;
        case OS.OS_POSIX:
          osMatch = graderPlatform.os != OS.OS_WINDOWS; break;
      }
    }
    bool runtimesMatch = true;
    for (GradingRuntime rt in problem.gradingOptions.runtimes) {
      if (!rt.optional && !rt.name.startsWith('default')) {
        bool runtimeFound = properties.platform.runtimes.contains(rt.name);
        if (!runtimeFound) {
          runtimesMatch = false;
          break;
        }
      }
    }
    return platformMatch && osMatch && runtimesMatch;
  }

  Future<ProblemData> getProblemDataForSubmission(Submission sub) async {
    String courseDataId;
    if (sub.course.dataId.isEmpty) {
      List<dynamic> rows = await parent.connection.query(
          'select course_data from courses where id=@id',
          substitutionValues: {'id': sub.course.id.toInt()}
      );
      courseDataId = rows[0][0];
    } else {
      courseDataId = sub.course.dataId;
    }
    CourseData courseData = (await parent.courseManagementService.getCourseFullContent(
        null, CourseContentRequest(courseDataId: courseDataId),
    )).data;
    ProblemData? problem = findProblemById(courseData, sub.problemId);
    if (problem == null) {
      throw GrpcError.notFound('problem ${sub.problemId} not found in $courseDataId}');
    }
    return problem;
  }

  Future<Submission> enqueueSubmissionToGrader(Submission sub, GraderConnection grader) {
    grader.streamController.sink.add(sub);
    final updated = Submission(
      id: sub.id,
      user: sub.user,
      course: sub.course,
      solutionFiles: sub.solutionFiles,
      timestamp: sub.timestamp,
      problemId: sub.problemId,
      status: SolutionStatus.GRADER_ASSIGNED,
      graderName: grader.properties.name,
    );
    return parent.submissionManagementService.updateGraderOutput(null, updated);
  }

  void shutdown() {
    _graders.forEach((connection) => deregisterGrader(connection));
  }
}