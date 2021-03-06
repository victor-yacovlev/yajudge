import 'dart:async';
import 'dart:io';
import 'package:build/build.dart';
import 'package:path/path.dart' as path;

class YajudgeGrpcGenerator implements Builder {
  final BuilderOptions options;
  YajudgeGrpcGenerator(this.options);

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    print('Running builder for build step ${buildStep}');
    String homeEnv = Platform.environment['HOME']!;
    String pathEnv = Platform.environment['PATH']!;
    pathEnv = '$homeEnv/.pub-cache/bin:' + pathEnv;
    var environment = Map<String,String>.of(Platform.environment);
    environment['PATH'] = pathEnv;
    String protoFilePath = buildStep.inputId.path;
    String protoFileDir = path.dirname(protoFilePath);
    Directory('lib/src/generated').createSync(recursive: true);
    ProcessResult processResult = Process.runSync(
      'protoc',
      ['-I', protoFileDir, protoFilePath, '--dart_out=grpc:lib/src/generated'],
      environment: environment,
      runInShell: true,
    );
    assert (processResult.exitCode == 0);
  }

  @override
  Map<String, List<String>> get buildExtensions {
    return const {
      '.proto': ['.pb.dart', '.pbenum.dart', '.pbgrpc.dart', '.pbjson.dart']
    };
  }

}

Builder yajudgeGrpcGenerator(BuilderOptions options) => YajudgeGrpcGenerator(options);