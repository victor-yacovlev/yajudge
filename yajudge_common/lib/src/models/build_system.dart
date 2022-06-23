import '../../yajudge_common.dart';

BuildSystem buildSystemFromString(dynamic conf) {
  String c = '';
  if (conf is String) {
    c = conf.toLowerCase().replaceAll('-', '_');
  }
  switch (c) {
    case 'none':
    case 'no':
    case 'skip':
      return BuildSystem.SkipBuild;
    case 'c':
    case 'cpp':
    case 'cxx':
    case 'c++':
    case 'gcc':
    case 'clang':
      return BuildSystem.ClangToolchain;
    case 'make':
    case 'makefile':
      return BuildSystem.MakefileProject;
    case 'go':
    case 'golang':
      return BuildSystem.GoLangProject;
    case 'cmake':
    case 'cmakelists':
    case 'cmakelists.txt':
      return BuildSystem.CMakeProject;
    case 'java':
    case 'javac':
      return BuildSystem.JavaPlainProject;
    case 'maven':
    case 'mvn':
    case 'pom':
    case 'pom.xml':
      return BuildSystem.MavenProject;
    default:
      return BuildSystem.AutodetectBuild;
  }
}

String buildSystemToString(BuildSystem buildSystem) {
  switch (buildSystem) {
    case BuildSystem.AutodetectBuild:
      return 'auto';
    case BuildSystem.CMakeProject:
      return 'cmake';
    case BuildSystem.ClangToolchain:
      return 'clang';
    case BuildSystem.GoLangProject:
      return 'go';
    case BuildSystem.JavaPlainProject:
      return 'javac';
    case BuildSystem.MakefileProject:
      return 'make';
    case BuildSystem.MavenProject:
      return 'mvn';
    case BuildSystem.PythonCheckers:
      return 'pylint';
    case BuildSystem.SkipBuild:
      return 'none';
    default:
      return 'auto';
  }
}