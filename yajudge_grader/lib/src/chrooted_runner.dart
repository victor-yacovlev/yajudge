import 'dart:core';

import 'package:logging/logging.dart';
import 'package:yajudge_common/yajudge_common.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:posix/posix.dart' as posix;
import 'package:yajudge_grader/src/limits.dart';

class ChrootedRunner {
  final GraderLocationProperties locationProperties;
  final Logger log = Logger('ChrootedRunner');

  late final io.Directory problemDir;
  late final io.Directory submissionUpperDir;
  late final io.Directory submissionMergeDir;
  late final io.Directory submissionWorkDir;

  static final String cgroupRoot = detectRootCgroupLocation();

  ChrootedRunner({
    required this.locationProperties,
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
  }

  static String detectRootCgroupLocation() {
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
    return '$cgroupSystemPath/user.slice/user-$uid.slice/user@$uid.service/yajudge-grader.service';
  }

  static void moveMyselfToCgroup() {
    String rootPath = detectRootCgroupLocation();
    io.Directory rootDir = io.Directory(rootPath);
    if (rootDir.existsSync()) {
      try {
        rootDir.deleteSync(recursive: true);
      } catch (_) {

      }
    }
    rootDir.createSync(recursive: true);
    String binDir = path.dirname(io.Platform.script.path);
    String helper = path.absolute(binDir, '../libexec', 'move-pid-to-cgroup');
    String myPid = '${io.pid}';
    if (io.File(helper).existsSync()) {
      final result = io.Process.runSync(
        helper,
        [rootPath, myPid]
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

  void createProblemCacheDir(CourseData courseData, ProblemData problemData) {
    String problemPath = path.absolute(locationProperties.coursesCacheDir, problemData.id);
    problemDir = io.Directory(problemPath);
    problemDir.createSync(recursive: true);
    io.Directory problemFilesDir = io.Directory(problemPath + '/work');
    problemFilesDir.createSync(recursive: true);
    for (final style in courseData.codeStyles) {
      String styleFilePath = '${problemFilesDir.path}/${style.styleFile.name}';
      io.File(styleFilePath).writeAsBytesSync(style.styleFile.data);
    }
    for (final file in problemData.graderFiles.files) {
      String filePath = path.normalize('${problemFilesDir.path}/${file.name}');
      String fileDir = path.dirname(filePath);
      io.Directory(fileDir).createSync(recursive: true);
      io.File(filePath).writeAsBytesSync(file.data);
    }
    log.fine('created problem cache $problemPath');
  }
  
  void createSubmissionDir(Submission submission) {
    String submissionPath = path.absolute(locationProperties.workDir, '${submission.id}');
    submissionUpperDir = io.Directory(submissionPath + '/upperdir');
    submissionWorkDir = io.Directory(submissionPath + '/workdir');
    submissionMergeDir = io.Directory(submissionPath + '/mergedir');
    submissionUpperDir.createSync(recursive: true);
    submissionWorkDir.createSync(recursive: true);
    submissionMergeDir.createSync(recursive: true);
    io.Directory submissionFilesDir = io.Directory(submissionUpperDir.path + '/work');
    for (final file in submission.solutionFiles.files) {
      String filePath = path.normalize('${submissionFilesDir.path}/${file.name}');
      String fileDir = path.dirname(filePath);
      io.Directory(fileDir).createSync(recursive: true);
      io.File(filePath).writeAsBytesSync(file.data);
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
    try {
      io.Directory dir = io.Directory(path);
      dir.createSync(recursive: true);
    } catch (error) {
      log.severe('cant create cgroup $path: $error');
    }
  }

  void removeSubmissionCgroup(int submissionId) {
    String path = submissionCgroupPath(submissionId);
    try {
      io.Directory dir = io.Directory(path);
      dir.deleteSync(recursive: true);
    } catch (error) {
      log.severe('cant delete cgroup $path: $error');
    }
  }

  void setupCgroupLimits(String cgroupPath, Limits limits) {

  }

  Future<io.ProcessResult> runIsolated(int submissionId, String executable, List<String> arguments, {
    String workingDirectory = '/work',
    Map<String,String>? environment,
    Limits? limits,
  }) {
    if (limits == null) {
      limits = Limits();
    }
    if (environment == null) {
      environment = Map<String,String>.from(io.Platform.environment);
    }
    String cgroupPath = submissionCgroupPath(submissionId);
    environment['YAJUDGE_CGROUP_PATH'] = cgroupPath;
    setupCgroupLimits(cgroupPath, limits);
    String binDir = path.dirname(io.Platform.script.path);
    String cgroupLauncher = path.absolute(binDir, '../libexec/', 'cgroup-run');
    String unshareFlags = '-muipUf';
    if (limits.isolateNetwork) {
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
    Future<io.ProcessResult> result = io.Process.run(cgroupLauncher, launcherArguments);
    return result;
  }

}