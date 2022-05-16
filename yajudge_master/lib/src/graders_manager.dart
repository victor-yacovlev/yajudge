import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';

class GraderConnection {
  final Logger log = Logger('GraderConnection');

  final ServiceCall call;
  final GraderProperties properties;
  final StreamController<Submission> sink = StreamController<Submission>();
  GraderStatus status = GraderStatus.Unknown;

  GraderConnection(this.call, this.properties) {
    String identity = '${properties.name} with CPU=${properties.platform.arch} and PR=${properties.performanceRating}';
    if (properties.archSpecificOnlyJobs) {
      identity += ' (takes only arch-specific jobs)';
    }
    log.info('attached grader $identity');
  }

  void destroy(Object? error, StackTrace? stackTrace) {
    status = GraderStatus.ShuttingDown;
    sink.close();
    if (error != null) {
      log.severe('grader ${properties.name} disconnected due to error $error');
    }
    else {
      log.info('grader ${properties.name} disconnected');
    }
  }

  bool pushSubmission(Submission submission) {
    if (status != GraderStatus.Idle) {
      return false;
    }
    sink.add(submission);
    return true;
  }


}

class GradersManager {
  final Logger log = Logger('GradersManager');
  final Map<String,GraderConnection> _connections = {};

  bool get hasGraders => _connections.isNotEmpty;

  GradersManager() {
    Timer.periodic(Duration(milliseconds: 500), (_) {
      checkForInactiveGraders();
    });
  }

  void checkForInactiveGraders() {
    List<String> gradersToRemove = [];
    for (final graderConnection in _connections.values) {
      final serviceCall = graderConnection.call;
      if (serviceCall.isCanceled) {
        graderConnection.destroy(null, null);
        gradersToRemove.add(graderConnection.properties.name);
      }
    }
    for (final name in gradersToRemove) {
      _connections.remove(name);
    }
  }

  StreamController<Submission> registerNewGrader(ServiceCall call, GraderProperties announce) {
    // Check if here was not removed connection to the same grader
    if (_connections.containsKey(announce.name)) {
      _connections[announce.name]!.destroy(null, null);
    }

    // Create new grader connection
    _connections[announce.name] = GraderConnection(call, announce);
    return _connections[announce.name]!.sink;
  }

  void setGraderStatus(String name, GraderStatus status) {
    if (!_connections.containsKey(name)) {
      return;
    }
    _connections[name]!.status = status;
    if (status == GraderStatus.ShuttingDown) {
      _connections[name]!.destroy(null, null);
      _connections.remove(name);
    }
  }

  void deregisterGrader(String name, [Object? error, StackTrace? stackTrace]) {
    if (!_connections.containsKey(name)) {
      return;
    }
    _connections[name]!.destroy(error, stackTrace);
    _connections.remove(name);
  }

  GraderConnection? findGrader(GradingPlatform platformRequired) {
    List<GraderConnection> candidates = [];
    for (final grader in _connections.values) {
      if (grader.status != GraderStatus.Idle) {
        continue;  // grader not ready yet or processing another submission
      }
      if (platformRequired.arch != Arch.ARCH_ANY) {
        // problem requires specific CPU
        if (platformRequired.arch != grader.properties.platform.arch) {
          continue; // CPU not matched
        }
      }
      if (grader.properties.archSpecificOnlyJobs && platformRequired.arch == Arch.ARCH_ANY) {
        // grader accepts only arch-specific jobs but not generic
        continue;
      }
      candidates.add(grader);
    }

    // return null if no matching graders found
    if (candidates.isEmpty) return null;

    // if several graders available then return best performance rated
    if (candidates.length > 1) {
      candidates.sort((GraderConnection a, GraderConnection b) {
        return a.properties.performanceRating.compareTo(b.properties.performanceRating);
      });
    }
    return candidates.last;
  }


}