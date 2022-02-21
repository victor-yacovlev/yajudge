import 'dart:async';

import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:posix/posix.dart' as posix;
import 'abstract_runner.dart';
import 'assets_loader.dart';

class ChrootedRunner extends AbstractRunner {
  final GraderLocationProperties locationProperties;
  final Logger log = Logger('ChrootedRunner');
  final String courseId;
  final String problemId;

  late final io.Directory problemDir;
  io.Directory? overlayUpperDir;
  io.Directory? overlayMergeDir;
  io.Directory? overlayWorkDir;

  static String cgroupRoot = '';

  ChrootedRunner({
    required this.locationProperties,
    required this.courseId,
    required this.problemId,
  }) {
    log.info('using work dir root ${locationProperties.workDir}');
    io.Directory(locationProperties.workDir).createSync(recursive: true);
    log.info('using Linux distribution from ${locationProperties.osImageDir}');
    if (!io.Directory(locationProperties.osImageDir).existsSync()) {
      log.shout('Linux distribution chroot not found');
      throw AssertionError('Linux distribution chroot not found');
    }
    log.info('using cache dir for course data ${locationProperties.cacheDir}');
    io.Directory(locationProperties.cacheDir).createSync(recursive: true);
    String problemCachePath = path.normalize(path.absolute(
      '${locationProperties.cacheDir}/$courseId/$problemId'
    ));
    problemDir = io.Directory(problemCachePath);
  }

  static String systemRootCgroupLocation() {
    if (!io.Platform.isLinux) {
      return '';
    }
    io.ProcessResult mountResult = io.Process.runSync('mount', []);
    assert(mountResult.exitCode == 0);
    final lines = mountResult.stdout.toString().split('\n');
    final rxMount = RegExp(r'cgroup2 on (\S+) type cgroup2 (.+)');
    String cgroupSystemPath = '';
    for (final line in lines) {
      if (rxMount.hasMatch(line)) {
        RegExpMatch match = rxMount.firstMatch(line)!;
        String path = match.group(1)!;
        if (path.startsWith('/sys/fs/')) {
          cgroupSystemPath = path;
          break;
        }
      }
    }
    return cgroupSystemPath;
  }

  static String initializeLinuxCgroup() {
    // io.sleep(Duration(minutes: 5));
    String cgroupFsRoot = systemRootCgroupLocation();
    if (cgroupFsRoot.isEmpty) {
      return 'cant find cgroup2 filesystem mounted. Check your systemd boot settings';
    }
    String myPid = '${io.pid}';
    final procPidCgroupFile = io.File('/proc/$myPid/cgroup');
    if (!procPidCgroupFile.existsSync()) {
      return 'cant open ${procPidCgroupFile.path}';
    }
    String cgroupLocationSuffix = procPidCgroupFile.readAsStringSync()
      .trim().split(':')[2];
    List<String> parts = cgroupLocationSuffix.split('/');
    bool foundWritableSlice = false;
    while (parts.isNotEmpty) {
      String lastPart = parts.last;
      if (lastPart.endsWith('.slice')) {
        cgroupRoot = path.normalize(path.absolute(cgroupFsRoot + '/' + parts.join('/')));
        final cgroupProcsFilePath = cgroupRoot + '/cgroup.procs';
        if (0 == posix.access(cgroupProcsFilePath, posix.R_OK | posix.W_OK)) {
          foundWritableSlice = true;
          break;
        }
      }
      parts = parts.sublist(0, parts.length-1);
    }
    if (!foundWritableSlice) {
      return 'no writable parent cgroup slice or service found. My current cgroup location is ${cgroupLocationSuffix}. Launch me using systemd-run --slice=NAME';
    }
    List<String> controllersAvailable = io.File(cgroupRoot+'/cgroup.controllers')
        .readAsStringSync().trim().split(' ');
    if (!controllersAvailable.contains('memory')) {
      return 'memory cgroup controller not available';
    }
    if (!controllersAvailable.contains('pids')) {
      return 'pids cgroup controller not available';
    }
    // io.sleep(Duration(minutes: 5)); // to explore WTF
    // Check if it is possible to create subgroup with pids and memory
    final checkDirectory = io.Directory('$cgroupRoot/check');
    try {
      checkDirectory.createSync();
    }
    catch (error) {
      return 'cant create subdirectory ${checkDirectory.path}: $error';
    }
    final checkSubtreeControl = io.File('$cgroupRoot/check/cgroup.subtree_control');
    try {
      checkSubtreeControl.writeAsStringSync('+pids');
    }
    catch (error) {
      return 'cant write +pids to ${checkSubtreeControl.path}: $error';
    }
    try {
      checkSubtreeControl.writeAsStringSync('+memory');
    }
    catch (error) {
      return 'cant write +memory to ${checkSubtreeControl.path}: $error';
    }
    return '';
  }

  void createProblemTemporaryDirs() {
    // to build helpers
    overlayUpperDir = io.Directory(problemDir.path);
    String base = path.absolute(locationProperties.workDir, '$courseId', '$problemId');
    overlayWorkDir = io.Directory(base + '/workdir');
    overlayMergeDir = io.Directory(base + '/mergedir');
    overlayWorkDir!.createSync(recursive: true);
    overlayMergeDir!.createSync(recursive: true);
  }
  
  void createSubmissionDir(Submission submission) {
    String submissionPath = path.normalize(path.absolute(locationProperties.workDir, '${submission.id}'));
    overlayUpperDir = io.Directory(submissionPath + '/upperdir');
    overlayWorkDir = io.Directory(submissionPath + '/workdir');
    overlayMergeDir = io.Directory(submissionPath + '/mergedir');
    overlayUpperDir!.createSync(recursive: true);
    overlayWorkDir!.createSync(recursive: true);
    overlayMergeDir!.createSync(recursive: true);
    io.Directory submissionBuildDir = io.Directory(overlayUpperDir!.path + '/build');
    io.Directory submissionTestsDir = io.Directory(overlayUpperDir!.path + '/tests');
    submissionBuildDir.createSync(recursive: true);
    submissionTestsDir.createSync(recursive: true);
    final fileNames = submission.solutionFiles.files.map((e) => e.name);
    io.File(submissionBuildDir.path+'/.solution_files').writeAsStringSync(
      fileNames.join('\n')
    );
    for (final file in submission.solutionFiles.files) {
      String filePath = '${submissionBuildDir.path}/${file.name}';
      String fileDir = path.dirname(filePath);
      io.Directory(fileDir).createSync(recursive: true);
      io.File(filePath).writeAsBytesSync(file.data);
    }
    io.Directory problemTestsDir = io.Directory(problemDir.path+'/tests');
    for (final entry in problemTestsDir.listSync(recursive: true)) {
      if (entry.statSync().type == io.FileSystemEntityType.directory) {
        String entryPath = entry.path.substring(problemTestsDir.path.length);
        io.Directory testsSubdir = io.Directory(submissionTestsDir.path+'/'+entryPath);
        testsSubdir.createSync(recursive: true);
      }
    }
    log.fine('created submission directory layout $submissionPath');
  }

  String get runWrapperToolPath {
    final wrappersDir = io.Directory(locationProperties.cacheDir + '/wrappers');
    if (!wrappersDir.existsSync()) {
      wrappersDir.createSync(recursive: true);
    }
    final names = [
      'run_wrapper_stage01.sh',
      'run_wrapper_stage02.sh',
      'run_wrapper_stage03.sh',
      'run_wrapper_stage04.sh',
      'run_wrapper_stage05.sh',
    ];
    for (final name in names) {
      final file = io.File(wrappersDir.path + '/' + name);
      if (!file.existsSync()) {
        final content = assetsLoader.fileAsBytes(name);
        file.writeAsBytesSync(content);
      }
    }
    return path.absolute(wrappersDir.path, names.first);
  }

  String submissionCgroupPath(Submission submission) {
    if (submission.id >= 0) {
      return cgroupRoot + '/submission-${submission.id}';
    }
    else {
      return cgroupRoot + '/problem-${submission.problemId}';
    }
  }

  void createSubmissionCgroup(Submission submission) {
    // cleanup cgroup directories from possible previous run
    removeSubmissionCgroup(submission);

    String path = submissionCgroupPath(submission);
    final dir = io.Directory(path);
    try {
      dir.createSync(recursive: true);
    } catch (error) {
      log.severe('cant create cgroup $path: $error');
    }
    final subtreeControl = io.File('$path/cgroup.subtree_control');
    if (subtreeControl.existsSync()) {
      try {
        subtreeControl.writeAsStringSync('+pids +memory');
      }
      catch (error) {
        log.severe('cant write +pids +memory to ${subtreeControl.path}: $error');
      }
    }
  }

  void _removeCgroup(String path) {
    final dir = io.Directory(path);
    final cgroupKill = io.File('$path/cgroup.kill');
    final cgroupProcs = io.File('$path/cgroup.procs');
    final cgroupFreeze = io.File('$path/cgroup.freeze');
    if (dir.existsSync()) {
      if (cgroupKill.existsSync()) {
        // Linux Kernel 5.14+ has cgroup.kill file to kill cgroup
        cgroupKill.writeAsStringSync('1');
      }
      else {
        // freeze process group to prevent spawning new processes
        cgroupFreeze.writeAsStringSync('1');
        // get all processes list and then kill em all
        final procsLines = cgroupProcs.readAsLinesSync();
        for (final line in procsLines) {
          io.Process.runSync('kill', ['-SIGKILL', line]);
        }
        // unfreeze process group
        cgroupFreeze.writeAsStringSync('0');
      }

      // wait to let processes die
      io.sleep(Duration(milliseconds: 100));

      // remove cgroup with no processes
      final result = io.Process.runSync('rmdir', [path]);
      if (result.exitCode != 0) {
        log.severe('cant remove cgroup $path: ${result.stderr.toString()}');
      }
    }
  }

  void removeSubmissionCgroup(Submission submission) {
    String path = submissionCgroupPath(submission);
    final dir = io.Directory(path);
    if (dir.existsSync()) {
      for (final entry in dir.listSync()) {
        if (entry is io.Directory) {
          _removeCgroup(entry.absolute.path);
        }
      }
      _removeCgroup(path);
    }
  }


  @override
  Future<YajudgeProcess> start(Submission submission, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String,String>? environment,
    GradingLimits? limits,
    bool runTargetIsScript = false,
  }) async {
    assert (arguments.length >= 1);
    String executable = arguments.first;
    arguments = arguments.sublist(1);
    arguments.removeWhere((element) => element.trim().isEmpty);
    if (environment == null) {
      environment = Map<String,String>.from(io.Platform.environment);
    }
    else {
      environment = Map<String,String>.from(environment);
    }
    String cgroupPath = submissionCgroupPath(submission);
    environment['YAJUDGE_CGROUP_PATH'] = cgroupPath;

    String cgroupSubmodule = path.basenameWithoutExtension(executable);
    environment['YAJUDGE_CGROUP_SUBDIR'] = cgroupSubmodule;

    if (limits != null) {
      if (limits.stackSizeLimitMb > 0) {
        environment['YAJUDGE_CPU_STACK_SIZE_LIMIT'] = (1024*limits.stackSizeLimitMb.toInt()).toString();
      }
      if (limits.cpuTimeLimitSec > 0) {
        environment['YAJUDGE_CPU_TIME_LIMIT'] = limits.cpuTimeLimitSec.toString();
      }
      if (limits.fdCountLimit > 0) {
        environment['YAJUDGE_FD_COUNT_LIMIT'] = limits.fdCountLimit.toString();
      }
      if (limits.procCountLimit > 0) {
        environment['YAJUDGE_PROC_COUNT_LIMIT'] = limits.procCountLimit.toString();
      }
      if (limits.memoryMaxLimitMb > 0) {
        environment['YAJUDGE_PROC_MEMORY_LIMIT'] = (1024*1024*limits.memoryMaxLimitMb.toInt()).toString();
      }
      if (limits.allowNetwork) {
        environment['YAJUDGE_ALLOW_NETWORK'] = '1';
      }
      if (limits.realTimeLimitSec > 0) {
        environment['YAJUDGE_REAL_TIME_LIMIT'] = '${limits.realTimeLimitSec}';
      }
    }

    String lowerDir = locationProperties.osImageDir;
    if (problemDir.path != overlayUpperDir!.path) {
      lowerDir += ':' + problemDir.path;
    }
    environment['YAJUDGE_OVERLAY_LOWERDIR'] = lowerDir;
    environment['YAJUDGE_OVERLAY_UPPERDIR'] = overlayUpperDir!.path;
    environment['YAJUDGE_OVERLAY_WORKDIR'] = overlayWorkDir!.path;
    environment['YAJUDGE_OVERLAY_MERGEDIR'] = overlayMergeDir!.path;
    environment['YAJUDGE_ROOT_DIR'] = overlayMergeDir!.path;
    environment['YAJUDGE_WORK_DIR'] = workingDirectory;

    final runWrapperScript = runWrapperToolPath;

    List<String> launcherArguments = [
      runWrapperScript,
      executable
    ] + arguments;

    final ioProcess = await io.Process.start(
      'bash',
      launcherArguments,
      environment: environment,
    );

    final cgroupDirectory = '$cgroupPath/$cgroupSubmodule';

    int pid = -1;
    int maxTries = 100;
    final delay = Duration(milliseconds: 50);
    final cgroupProcs = io.File('$cgroupDirectory/cgroup.procs');
    for (int i=0; i<maxTries; i++) {
      if (cgroupProcs.existsSync()) {
        break;
      }
      io.sleep(delay);
    }
    final cgroupProcLines = cgroupProcs.readAsLinesSync();
    for (final line in cgroupProcLines) {
      if (line.isEmpty)
        continue;
      final exeLink = io.Link('/proc/${line.trim()}/exe');
      if (exeLink.existsSync()) {
        try {
          // process might finish too fast and link will not valid,
          // so check it in try-catch block
          String linkTarget = exeLink.targetSync();
          if (path.basename(linkTarget) == path.basename(executable)) {
            pid = int.parse(line.trim());
            break;
          }
        }
        catch (_) {
        }
      }
    }

    int stdoutSizeLimit = -1;
    int stderrSizeLimit = -1;
    if (limits != null && limits.stdoutSizeLimitMb > 0) {
      stdoutSizeLimit = 1024 * 1024 * limits.stdoutSizeLimitMb.toInt();
    }
    if (limits != null && limits.stderrSizeLimitMb > 0) {
      stderrSizeLimit = 1024 * 1024 * limits.stderrSizeLimitMb.toInt();
    }

    log.fine('started process $executable');

    return YajudgeProcess(
      cgroupDirectory: cgroupDirectory,
      ioProcess: ioProcess,
      realPid: pid,
      stdoutSizeLimit: stdoutSizeLimit,
      stderrSizeLimit: stderrSizeLimit,
    );
  }

  @override
  void killProcess(YajudgeProcess process) {
    if (process.cgroupDirectory.isNotEmpty) {
      // just remove cgroup: it will kill all related processes
      _removeCgroup(process.cgroupDirectory);
    }
    else {
      io.Process.runSync('kill', ['-KILL', '${process.realPid}']);
    }
  }

  @override
  void createDirectoryForSubmission(Submission submission) {
    if (submission.id >= 0) {
      createSubmissionDir(submission);
    }
    else if (submission.id == -1) {
      createProblemTemporaryDirs();
    }
    createSubmissionCgroup(submission);
  }

  @override
  void releaseDirectoryForSubmission(Submission submission) {
    removeSubmissionCgroup(submission);
  }

  @override
  String submissionPrivateDirectory(Submission submission) {
    return overlayUpperDir!.path;
  }

  @override
  String submissionWorkingDirectory(Submission submission) {
    return overlayMergeDir!.path;
  }

  @override
  String submissionProblemDirectory(Submission submission) {
    return problemDir.path;
  }

  @override
  String submissionRootPrefix(Submission submission) {
    return '/';
  }

  @override
  String submissionFileSystemRootPrefix(Submission submission) {
    return submissionPrivateDirectory(submission);
  }


}