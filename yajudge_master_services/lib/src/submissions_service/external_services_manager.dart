import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';

class ExternalServiceConnection {
  final Logger log = Logger('ExternalServiceConnection');

  final ServiceCall call;
  final ConnectedServiceProperties properties;
  final StreamController<Submission> sink = StreamController<Submission>();
  ServiceStatus status = ServiceStatus.SERVICE_STATUS_UNKNOWN;
  int capacity = 0;

  ExternalServiceConnection(this.call, this.properties) {
    String identity =
        '${properties.name} with CPU=${properties.platform.arch}'
        ', THREADS=${properties.numberOfWorkers}'
        ' and PR=${properties.performanceRating}';
    if (properties.archSpecificOnlyJobs) {
      identity += ' (takes only arch-specific jobs)';
    }
    String serviceName = properties.role.name;
    status = ServiceStatus.SERVICE_STATUS_IDLE;
    capacity = properties.numberOfWorkers;
    log.info('attached $serviceName $identity');
  }

  void destroy(Object? error, StackTrace? stackTrace) {
    status = ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN;
    sink.close();
    if (error != null) {
      log.severe('${properties.role.name} ${properties.name} disconnected due to error $error');
    }
    else {
      log.info('${properties.role.name} ${properties.name} disconnected');
    }
  }

  bool pushSubmission(Submission submission) {
    if (status != ServiceStatus.SERVICE_STATUS_IDLE || capacity <= 0) {
      return false;
    }
    sink.add(submission);
    capacity --;
    return true;
  }


}

class ExternalServicesManager {
  final Logger log = Logger('ExternalServicesManager');
  final Map<String,ExternalServiceConnection> _connections = {};

  bool get hasGraders => _connections.isNotEmpty;

  ExternalServicesManager() {
    Timer.periodic(Duration(milliseconds: 500), (_) {
      checkForInactiveGraders();
    });
  }

  void checkForInactiveGraders() {
    List<String> gradersToRemove = [];
    for (final service in _connections.entries) {
      final serviceCall = service.value.call;
      if (serviceCall.isCanceled) {
        service.value.destroy(null, null);
        gradersToRemove.add(service.key);
      }
    }
    for (final identity in gradersToRemove) {
      _connections.remove(identity);
    }
  }

  StreamController<Submission> registerNewService(ServiceCall call, ConnectedServiceProperties announce) {
    // Check if here was not removed connection to the same service
    final identity = '${announce.name}|${announce.role}';
    if (_connections.containsKey(identity)) {
      _connections[identity]!.destroy(null, null);
    }

    // Create new service connection
    _connections[identity] = ExternalServiceConnection(call, announce);
    return _connections[identity]!.sink;
  }

  void setServiceStatus(ServiceRole role, String name, ServiceStatus status, int capacity) {
    final identity = '$name|$role';
    if (!_connections.containsKey(identity)) {
      return;
    }
    _connections[identity]!.status = status;
    _connections[identity]!.capacity = capacity;
    if (status == ServiceStatus.SERVICE_STATUS_SHUTTING_DOWN) {
      _connections[identity]!.destroy(null, null);
      _connections.remove(identity);
    }
  }

  void deregisterService(ServiceRole role, String name, [Object? error, StackTrace? stackTrace]) {
    final identity = '$name|$role';
    if (!_connections.containsKey(identity)) {
      return;
    }
    _connections[identity]!.destroy(error, stackTrace);
    _connections.remove(identity);
  }

  ExternalServiceConnection? findService(ServiceRole role, GradingPlatform platformRequired) {
    List<ExternalServiceConnection> candidates = [];
    for (final service in _connections.values) {
      if (service.properties.role != role) {
        continue;  // not suitable service
      }
      if (service.status != ServiceStatus.SERVICE_STATUS_IDLE && service.capacity > 0) {
        continue;  // service not ready yet or processing another submission
      }
      if (platformRequired.arch != Arch.ARCH_ANY) {
        // problem requires specific CPU
        if (platformRequired.arch != service.properties.platform.arch) {
          continue; // CPU not matched
        }
      }
      if (service.properties.archSpecificOnlyJobs && platformRequired.arch == Arch.ARCH_ANY) {
        // service accepts only arch-specific jobs but not generic
        continue;
      }
      candidates.add(service);
    }

    // return null if no matching graders found
    if (candidates.isEmpty) return null;

    // if several graders available then return best performance rated
    if (candidates.length > 1) {
      candidates.sort((ExternalServiceConnection a, ExternalServiceConnection b) {
        final aRating = a.properties.performanceRating * a.capacity;
        final bRating = b.properties.performanceRating * b.capacity;
        return aRating.compareTo(bRating);
      });
    }
    return candidates.last;
  }


}