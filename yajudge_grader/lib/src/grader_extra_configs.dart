import 'package:fixnum/fixnum.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml/yaml.dart';
import 'dart:io';

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