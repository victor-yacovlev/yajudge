import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:yaml/yaml.dart';

import '../../yajudge_common.dart';

extension GradingLimitsExtension on GradingLimits {

  static GradingLimits fromYaml(dynamic confOrNull) {
    if (confOrNull is! YamlMap) {
      return GradingLimits();
    }
    YamlMap conf = confOrNull;
    int stackSize = 0;
    int memoryMax = 0;
    int cpuTime = 0;
    int realTime = 0;
    int procs = 0;
    int procStartDelay = 0;
    int files = 0;
    int stdoutMax = 0;
    int stderrMax = 0;
    bool allowNetwork = false;

    if (conf['stack_size_limit_mb'] is int) {
      stackSize = conf['stack_size_limit_mb'];
    }
    if (conf['memory_max_limit_mb'] is int) {
      memoryMax = conf['memory_max_limit_mb'];
    }
    if (conf['cpu_time_limit_sec'] is int) {
      cpuTime = conf['cpu_time_limit_sec'];
    }
    if (conf['real_time_limit_sec'] is int) {
      realTime = conf['real_time_limit_sec'];
    }
    if (conf['proc_count_limit'] is int) {
      procs = conf['proc_count_limit'];
    }
    if (conf['new_proc_delay_msec'] is int) {
      procStartDelay = conf['new_proc_delay_msec'];
    }
    if (conf['fd_count_limit'] is int) {
      files = conf['fd_count_limit'];
    }
    if (conf['stdout_size_limit_mb'] is int) {
      stdoutMax = conf['stdout_size_limit_mb'];
    }
    if (conf['stderr_size_limit_mb'] is int) {
      stderrMax = conf['stderr_size_limit_mb'];
    }
    if (conf['allow_network'] is bool) {
      allowNetwork = conf['allow_network'].toString().toLowerCase()=='true';
    }
    return GradingLimits(
      stackSizeLimitMb: Int64(stackSize),
      memoryMaxLimitMb: Int64(memoryMax),
      cpuTimeLimitSec: Int64(cpuTime),
      realTimeLimitSec: Int64(realTime),
      procCountLimit: Int64(procs),
      newProcDelayMsec: Int64(procStartDelay),
      fdCountLimit: Int64(files),
      stdoutSizeLimitMb: Int64(stdoutMax),
      stderrSizeLimitMb: Int64(stderrMax),
      allowNetwork: allowNetwork,
    );
  }

  GradingLimits mergedWith(GradingLimits u) {
    GradingLimits s = deepCopy();
    if (u.stackSizeLimitMb != 0) {
      s.stackSizeLimitMb = u.stackSizeLimitMb;
    }
    if (u.memoryMaxLimitMb != 0) {
      s.memoryMaxLimitMb = u.memoryMaxLimitMb;
    }
    if (u.cpuTimeLimitSec != 0) {
      s.cpuTimeLimitSec = u.cpuTimeLimitSec;
    }
    if (u.realTimeLimitSec != 0) {
      s.realTimeLimitSec = u.realTimeLimitSec;
    }
    if (u.procCountLimit != 0) {
      s.procCountLimit = u.procCountLimit;
    }
    if (u.fdCountLimit != 0) {
      s.fdCountLimit = u.fdCountLimit;
    }
    if (u.stdoutSizeLimitMb != 0) {
      s.stdoutSizeLimitMb = u.stdoutSizeLimitMb;
    }
    if (u.stderrSizeLimitMb != 0) {
      s.stderrSizeLimitMb = u.stderrSizeLimitMb;
    }
    if (u.allowNetwork) {
      s.allowNetwork = u.allowNetwork;
    }
    return s;
  }

  String toYamlString({int level = 0}) {
    String indent = level > 0 ? '  ' * level : '';
    String result = '';
    if (stackSizeLimitMb > 0) {
      result += '${indent}stack_size_limit_mb: $stackSizeLimitMb\n';
    }
    if (memoryMaxLimitMb > 0) {
      result += '${indent}memory_max_limit_mb: $memoryMaxLimitMb\n';
    }
    if (cpuTimeLimitSec > 0) {
      result += '${indent}cpu_time_limit_sec: $cpuTimeLimitSec\n';
    }
    if (realTimeLimitSec > 0) {
      result += '${indent}real_time_limit_sec: $realTimeLimitSec\n';
    }
    if (procCountLimit > 0) {
      result += '${indent}proc_count_limit: $procCountLimit\n';
    }
    if (newProcDelayMsec > 0) {
      result += '${indent}new_proc_delay_msec: $newProcDelayMsec\n';
    }
    if (fdCountLimit > 0) {
      result += '${indent}fd_count_limit: $fdCountLimit\n';
    }
    if (stdoutSizeLimitMb > 0) {
      result += '${indent}stdout_size_limit_mb: $stdoutSizeLimitMb\n';
    }
    if (stderrSizeLimitMb > 0) {
      result += '${indent}stderr_size_limit_mb: $stderrSizeLimitMb\n';
    }
    if (allowNetwork) {
      result += '${indent}allow_network: $allowNetwork\n';
    }
    return result;
  }

}