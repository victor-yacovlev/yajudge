import 'package:fixnum/fixnum.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';

GradingLimits parseDefaultLimits(YamlMap conf) {
  int stackSize = 0;
  int memoryMax = 0;
  int cpuTime = 0;
  int realTime = 0;
  int procs = 0;
  int files = 0;
  int stdoutMax = 0;
  int stderrMax = 0;
  bool allowNetwork = false;
  if (conf['stack_size_limit_mb'] is int)
    stackSize = conf['stack_size_limit_mb'];
  if (conf['memory_max_limit_mb'] is int)
    memoryMax = conf['memory_max_limit_mb'];
  if (conf['cpu_time_limit_sec'] is int)
    cpuTime = conf['cpu_time_limit_sec'];
  if (conf['real_time_limit_sec'] is int)
    realTime = conf['real_time_limit_sec'];
  if (conf['proc_count_limit'] is int)
    procs = conf['proc_count_limit'];
  if (conf['fd_count_limit'] is int)
    files = conf['fd_count_limit'];
  if (conf['stdout_size_limit_mb'] is int)
    stdoutMax = conf['stdout_size_limit_mb'];
  if (conf['stderr_size_limit_mb'] is int)
    stderrMax = conf['stderr_size_limit_mb'];
  if (conf['allow_network'] is bool)
    allowNetwork = conf['allow_network'].toString().toLowerCase()=='true';
  return GradingLimits(
    stackSizeLimitMb: Int64(stackSize),
    memoryMaxLimitMb: Int64(memoryMax),
    cpuTimeLimitSec: Int64(cpuTime),
    realTimeLimitSec: Int64(realTime),
    procCountLimit: Int64(procs),
    fdCountLimit: Int64(files),
    stdoutSizeLimitMb: Int64(stdoutMax),
    stderrSizeLimitMb: Int64(stderrMax),
    allowNetwork: allowNetwork,
  );
}

class CompilersConfig {
  final String cCompiler;
  final String cxxCompiler;
  final List<String> cBaseOptions;
  final List<String> cxxBaseOptions;
  final bool enableSanitizers;
  final List<String> sanitizersOptions;
  final bool enableValgrind;
  final int extraValgrindMemory;
  final double scaleValgrindTime;

  CompilersConfig({
    required this.cCompiler,
    required this.cxxCompiler,
    required this.cBaseOptions,
    required this.cxxBaseOptions,
    required this.enableSanitizers,
    required this.sanitizersOptions,
    required this.enableValgrind,
    required this.extraValgrindMemory,
    required this.scaleValgrindTime
  });

  factory CompilersConfig.createDefault() {
    return CompilersConfig(
      cCompiler: 'gcc',
      cxxCompiler: 'g++',
      cBaseOptions: [],
      cxxBaseOptions: [],
      enableSanitizers: false,
      sanitizersOptions: [],
      enableValgrind: false,
      extraValgrindMemory: 0,
      scaleValgrindTime: 1.0,
    );
  }

  factory CompilersConfig.fromYaml(YamlMap conf) {
    String cCompiler = 'gcc';
    String cxxCompiler = 'g++';
    List<String> cBaseOptions = [];
    List<String> cxxBaseOptions = [];
    bool enableSanitizers = false;
    List<String> sanitizersOptions = [];
    bool enableValgrind = false;
    int extraValgrindMemory = 0;
    double scaleValgrindTime = 1.0;
    if (conf['c_compiler'] is String)
      cCompiler = conf['c_compiler'];
    if (conf['cxx_compiler'] is String)
      cxxCompiler = conf['cxx_compiler'];
    if (conf['c_base_options'] is String)
      cBaseOptions = conf['c_base_options'].toString().split(' ');
    if (conf['cxx_base_options'] is String)
      cxxBaseOptions = conf['cxx_base_options'].toString().split(' ');
    if (conf['enable_sanitizers'] is bool)
      enableSanitizers = conf['enable_sanitizers'].toString().toLowerCase()=='true';
    if (conf['enable_valgrind'] is bool)
      enableValgrind = Platform.isLinux && conf['enable_valgrind'].toString().toLowerCase()=='true';
    if (conf['sanitizers_compile_options'] is String)
      sanitizersOptions = conf['sanitizers_compile_options'].toString().split(' ');
    if (conf['valgrind_extra_memory_limit_mb'] is int)
      extraValgrindMemory = int.parse(conf['valgrind_extra_memory_limit_mb'].toString());
    if (conf['valgrind_cpu_time_scale'] is double)
      scaleValgrindTime = double.parse(conf['valgrind_cpu_time_scale'].toString());
    return CompilersConfig(cCompiler: cCompiler, cxxCompiler: cxxCompiler,
        cBaseOptions: cBaseOptions, cxxBaseOptions: cxxBaseOptions,
        enableSanitizers: enableSanitizers, sanitizersOptions: sanitizersOptions,
        enableValgrind: enableValgrind,
        extraValgrindMemory: extraValgrindMemory,
        scaleValgrindTime: scaleValgrindTime);
  }

  GradingLimits applyValgrindToGradingLimits(GradingLimits base) {
    return base.copyWith((l) {
      double cpuTime = l.cpuTimeLimitSec.toDouble();
      double realTime = l.realTimeLimitSec.toDouble();
      int memoryMax = l.memoryMaxLimitMb.toInt();
      if (cpuTime > 0 && scaleValgrindTime > 0) {
        cpuTime *= scaleValgrindTime;
        l.cpuTimeLimitSec = Int64(cpuTime.toInt());
      }
      if (realTime > 0 && scaleValgrindTime > 0) {
        realTime *= scaleValgrindTime;
        l.realTimeLimitSec = Int64(realTime.toInt());
      }
      if (memoryMax > 0 && extraValgrindMemory > 0) {
        l.memoryMaxLimitMb = Int64(memoryMax + extraValgrindMemory);
      }
    });
  }

}