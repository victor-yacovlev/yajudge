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

  late final io.Directory problemDir;
  late final io.Directory submissionUpperDir;
  late final io.Directory submissionMergeDir;
  late final io.Directory submissionWorkDir;

  static final String cgroupRoot = detectRootCgroupLocation();

  ChrootedRunner({
    required this.locationProperties,
    required String courseId,
    required String problemId,
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

  static String detectRootCgroupLocation() {
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
    assert(cgroupSystemPath != null);
    int uid = posix.getuid();
    return path.normalize('$cgroupSystemPath/user.slice/user-$uid.slice/user@$uid.service/yajudge-grader.service');
  }

  static void initialCgroupSetup() {
    if (!io.Platform.isLinux) {
      return;
    }
    String cgroupRootPath = detectRootCgroupLocation();
    final cgroupRootDir = io.Directory(cgroupRootPath);
    if (cgroupRootDir.existsSync()) {
      io.Process.runSync('rmdir', [cgroupRootPath]);
    }
    cgroupRootDir.createSync(recursive: true);
    String binDir = path.dirname(io.Platform.script.path);
    String helper = path.normalize(path.absolute(binDir, '../libexec', 'initial-cgroup-setup'));
    String myPid = '${io.pid}';
    if (io.File(helper).existsSync()) {
      final result = io.Process.runSync(
        helper,
        [cgroupRootPath, myPid]
      );
      if (result.stdout.toString().isNotEmpty) {
        print(result.stdout.toString());
      }
      if (result.stderr.toString().isNotEmpty) {
        print(result.stderr.toString());
      }
      assert (result.exitCode==0);
    }
  }

  
  void createSubmissionDir(Submission submission) {
    String submissionPath = path.normalize(path.absolute(locationProperties.workDir, '${submission.id}'));
    submissionUpperDir = io.Directory(submissionPath + '/upperdir');
    submissionWorkDir = io.Directory(submissionPath + '/workdir');
    submissionMergeDir = io.Directory(submissionPath + '/mergedir');
    submissionUpperDir.createSync(recursive: true);
    submissionWorkDir.createSync(recursive: true);
    submissionMergeDir.createSync(recursive: true);
    io.Directory submissionBuildDir = io.Directory(submissionUpperDir.path + '/build');
    io.Directory submissionTestsDir = io.Directory(submissionUpperDir.path + '/tests');
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
    final env = {
      'YAJUDGE_OVERLAY_LOWERDIR': locationProperties.osImageDir + ':' + problemDir.path,
      'YAJUDGE_OVERLAY_UPPERDIR': submissionUpperDir.path,
      'YAJUDGE_OVERLAY_WORKDIR': submissionWorkDir.path,
      'YAJUDGE_OVERLAY_MERGEDIR': submissionMergeDir.path,
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
    log.fine('mounted overlay at ${submissionMergeDir.path}');
  }

  void unMountOverlay() {
    final env = {
      'YAJUDGE_OVERLAY_MERGEDIR': submissionMergeDir.path,
    };
    final status = io.Process.runSync(
      mounterToolPath, ['-u'],
      environment: env,
    );
    if (status.stderr.toString().isNotEmpty) {
      log.severe('umount overlay: ${status.stderr}');
    }
    if (status.exitCode != 0) {
      throw AssertionError('cant unmount overlay filesystem: ${status.stderr}');
    }
    log.fine('unmounted overlay at ${submissionMergeDir.path}');
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
    final pidsMax = io.File('$cgroupPath/pids.max');
    if (!pidsMax.existsSync()) {
      log.severe('no pids cgroup controller enabled. Ensure you a running on system with systemd.unified_cgroup_hierarchy=1');
    }
    else if (limits.procCountLimit.toInt() > 0) {
      pidsMax.writeAsStringSync(limits.procCountLimit.toString());
    }
    final memoryMax = io.File('$cgroupPath/memory.max');
    if (!memoryMax.existsSync()) {
      log.severe('no memory cgroup controller enabled. Ensure you a running on system with systemd.unified_cgroup_hierarchy=1');
    }
    else if (limits.memoryMaxLimitMb > 0) {
      int valueInBytes = limits.memoryMaxLimitMb.toInt() * 1024 * 1024;
      memoryMax.writeAsStringSync('$valueInBytes');
    }
  }

  @override
  Future<io.Process> start(int submissionId, String executable, List<String> arguments, {
    String workingDirectory = '/build',
    Map<String,String>? environment,
    GradingLimits? limits,
  }) {
    if (limits == null) {
      limits = GradingLimits(
        procCountLimit: Int64(20),
      );
    }
    if (environment == null) {
      environment = Map<String,String>.from(io.Platform.environment);
    }
    String cgroupPath = submissionCgroupPath(submissionId);
    environment['YAJUDGE_CGROUP_PATH'] = cgroupPath;
    setupCgroupLimits(cgroupPath, limits);
    if (limits.stackSizeLimitMb > 0) {
      environment['YAJUDGE_STACK_SIZE_LIMIT_MB'] = limits.stackSizeLimitMb.toString();
    }
    if (limits.cpuTimeLimitSec > 0) {
      environment['YAJUDGE_CPU_TIME_LIMIT_SEC'] = limits.cpuTimeLimitSec.toString();
    }
    if (limits.fdCountLimit > 0) {
      environment['YAJUDGE_FD_COUNT_LIMIT'] = limits.fdCountLimit.toString();
    }
    String binDir = path.dirname(io.Platform.script.path);
    String cgroupLauncher = path.absolute(binDir, '../libexec/', 'limited-run');
    String unshareFlags = '-muipUf';
    if (!limits.allowNetwork) {
      unshareFlags += 'n';
    }
    String rootDirArg = '--root=${submissionMergeDir.path}';
    String workDirArg = '--wd=$workingDirectory';
    List<String> launcherArguments = [
      'unshare',
      unshareFlags,
      rootDirArg,
      workDirArg,
      executable
    ] + arguments;
    Future<io.Process> result = io.Process.start(
      cgroupLauncher,
      launcherArguments,
      environment: environment,
    );
    return result;
  }

  @override
  void createDirectoryForSubmission(Submission submission) {
    createSubmissionDir(submission);
    mountOverlay();
    createSubmissionCgroup(submission.id.toInt());
  }

  @override
  void releaseDirectoryForSubmission(Submission submission) {
    unMountOverlay();
    removeSubmissionCgroup(submission.id.toInt());
  }

  @override
  String submissionPrivateDirectory(Submission submission) {
    return submissionUpperDir.path;
  }

  @override
  String submissionWorkingDirectory(Submission submission) {
    return submissionMergeDir.path;
  }

  @override
  String submissionProblemDirectory(Submission submission) {
    return problemDir.path;
  }

}