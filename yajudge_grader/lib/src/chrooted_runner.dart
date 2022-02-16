import 'dart:async';
import 'dart:core';

import 'package:fixnum/fixnum.dart';
import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:posix/posix.dart' as posix;
import 'abstract_runner.dart';

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
    log.info('using cache dir for course data ${locationProperties.coursesCacheDir}');
    io.Directory(locationProperties.coursesCacheDir).createSync(recursive: true);
    String problemCachePath = path.normalize(path.absolute(
      '${locationProperties.coursesCacheDir}/$courseId/$problemId'
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
    String? cgroupSystemPath;
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
    if (cgroupSystemPath == null) {
      Logger.root.severe('cant find cgroup2 filesystem mounted. Check your systemd boot settings');
    }
    return cgroupSystemPath!;
  }

  static void checkLinuxCgroupCapabilities() {
    if (!io.Platform.isLinux) {
      return;
    }
    String cgroupFsRoot = systemRootCgroupLocation();
    String myPid = '${io.pid}';
    final procPidCgroupFile = io.File('/proc/$myPid/cgroup');
    if (!procPidCgroupFile.existsSync()) {
      Logger.root.shout('cant open ${procPidCgroupFile.path}');
      io.exit(1);
    }
    String cgroupLocationSuffix = procPidCgroupFile.readAsStringSync()
      .trim().split(':')[2];
    List<String> parts = cgroupLocationSuffix.split('/');
    bool foundWritableSlice = false;
    while (parts.isNotEmpty) {
      String lastPart = parts.last;
      if (lastPart.endsWith('.slice')) {
        cgroupRoot = cgroupFsRoot + '/' + parts.join('/');
        final cgroupProcsFilePath = cgroupRoot + '/cgroup.procs';
        if (0 == posix.access(cgroupProcsFilePath, posix.R_OK | posix.W_OK)) {
          foundWritableSlice = true;
          break;
        }
      }
      parts = parts.sublist(0, parts.length-1);
    }
    if (!foundWritableSlice) {
      Logger.root.shout('no writable parent cgroup slice found. Launch me using systemd-run --slice=NAME');
      io.exit(1);
    }
    List<String> controllersAvailable = io.File(cgroupRoot+'/cgroup.controllers')
        .readAsStringSync().trim().split(' ');
    if (!controllersAvailable.contains('memory')) {
      Logger.root.severe('memory cgroup controller not available');
    }
    if (!controllersAvailable.contains('pids')) {
      Logger.root.severe('pids cgroup controller not available');
    }
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


  String get mounterToolPath {
    String binDir = path.dirname(io.Platform.script.path);
    String mounter = path.absolute(binDir, '../libexec/', 'overlay-mount');
    return mounter;
  }

  void mountOverlay() {
    String lowerDir = locationProperties.osImageDir;
    if (problemDir.path != overlayUpperDir!.path) {
      lowerDir += ':' + problemDir.path;
    }
    final env = {
      'YAJUDGE_OVERLAY_LOWERDIR': lowerDir,
      'YAJUDGE_OVERLAY_UPPERDIR': overlayUpperDir!.path,
      'YAJUDGE_OVERLAY_WORKDIR': overlayWorkDir!.path,
      'YAJUDGE_OVERLAY_MERGEDIR': overlayMergeDir!.path,
    };
    final status = io.Process.runSync(
      mounterToolPath, [],
      environment: env,
    );
    if (status.stderr.toString().isNotEmpty) {
      log.severe('mount overlay: ${status.stderr}');
    }
    if (status.exitCode != 0) {
      throw AssertionError('cant mount overlay filesystem: ${status.stderr}');
    }
    log.fine('mounted overlay at ${overlayMergeDir!.path}');
  }

  void unMountOverlay() {
    final env = {
      'YAJUDGE_OVERLAY_MERGEDIR': overlayMergeDir!.path,
    };
    final status = io.Process.runSync(
      mounterToolPath, ['-u'],
      environment: env,
    );
    if (status.stderr.toString().isNotEmpty) {
      log.severe('umount overlay: ${status.stderr}');
    }
    else {
      log.fine('unmounted overlay at ${overlayMergeDir!.path}');
    }
  }

  String submissionCgroupPath(int submissionId) {
    return cgroupRoot + '/submission-$submissionId';
  }

  void createSubmissionCgroup(int submissionId) {
    String path = submissionCgroupPath(submissionId);
    final dir = io.Directory(path);
    if (dir.existsSync()) {
      io.Process.runSync('rmdir', [path]);
    }
    try {
      dir.createSync(recursive: true);
    } catch (error) {
      log.severe('cant create cgroup $path: $error');
    }
    final subtreeControl = io.File('$path/cgroup.subtree_control');
    if (subtreeControl.existsSync()) {
      subtreeControl.writeAsStringSync('+pids +memory');
    }
  }

  void removeSubmissionCgroup(int submissionId) {
    String path = submissionCgroupPath(submissionId);
    final result = io.Process.runSync(
      'rmdir', [path]
    );
    if (result.exitCode != 0) {
      log.severe('cant remove cgroup $path: ${result.stderr.toString()}');
    } else {
      log.fine('removed cgroup for submission $submissionId');
    }
  }

  void setupCgroupLimits(String cgroupPath, GradingLimits limits) {
    final memoryMax = io.File('$cgroupPath/memory.max');
    if (!memoryMax.existsSync()) {
      log.severe('no memory cgroup controller enabled. Ensure you a running on system with systemd.unified_cgroup_hierarchy=1');
    }
    else if (limits.memoryMaxLimitMb > 0) {
      int valueInBytes = limits.memoryMaxLimitMb.toInt() * 1024 * 1024;
      String value = '$valueInBytes\n';
      memoryMax.writeAsStringSync(value, flush: true);
    }
  }

  @override
  Future<io.Process> start(int submissionId, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String,String>? environment,
    GradingLimits? limits,
    bool runTargetIsScript = false,
  }) {
    assert (arguments.length >= 1);
    String executable = arguments.first;
    arguments = arguments.sublist(1);
    arguments.removeWhere((element) => element.trim().isEmpty);
    if (limits == null) {
      limits = GradingLimits(
        procCountLimit: Int64(20),
      );
    }
    if (environment == null) {
      environment = Map<String,String>.from(io.Platform.environment);
    }
    if (submissionId != 0) {
      String cgroupPath = submissionCgroupPath(submissionId);
      environment['YAJUDGE_CGROUP_PATH'] = cgroupPath;
      setupCgroupLimits(cgroupPath, limits);
    }
    if (limits.stackSizeLimitMb > 0) {
      environment['YAJUDGE_STACK_SIZE_LIMIT_MB'] = limits.stackSizeLimitMb.toString();
    }
    if (limits.cpuTimeLimitSec > 0) {
      environment['YAJUDGE_CPU_TIME_LIMIT_SEC'] = limits.cpuTimeLimitSec.toString();
    }
    if (limits.fdCountLimit > 0) {
      environment['YAJUDGE_FD_COUNT_LIMIT'] = limits.fdCountLimit.toString();
    }
    if (limits.procCountLimit > 0) {
      environment['YAJUDGE_PROC_COUNT_LIMIT'] = limits.procCountLimit.toString();
    }

    String binDir = path.dirname(io.Platform.script.path);
    String limitedLauncher = path.absolute(binDir, '../libexec/', 'limited-run');
    String unshareFlags = '-muipUf';
    if (!limits.allowNetwork) {
      unshareFlags += 'n';
    }

    String rootDirArg = '--root=${overlayMergeDir!.path}';
    String workDirArg = '--wd=$workingDirectory';

    List<String> launcherArguments = [
      'unshare',
      unshareFlags,
      rootDirArg,
      workDirArg,
      executable
    ] + arguments;
    Future<io.Process> result = io.Process.start(
      limitedLauncher,
      launcherArguments,
      environment: environment,
    );
    return result;
  }

  @override
  void createDirectoryForSubmission(Submission submission) {
    if (submission.id >= 0) {
      createSubmissionDir(submission);
      mountOverlay();
      createSubmissionCgroup(submission.id.toInt());
    }
    else if (submission.id == -1) {
      createProblemTemporaryDirs();
      mountOverlay();
    }
  }

  @override
  void releaseDirectoryForSubmission(Submission submission) {
    unMountOverlay();
    if (submission.id >= 0) {
      removeSubmissionCgroup(submission.id.toInt());
    }
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