import 'dart:convert';
import 'dart:typed_data';
import 'package:yajudge_client/wsapi/courses.dart';

import 'utils.dart';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:ini/ini.dart';

typedef _OpenFileNative = Pointer<Utf8> Function(Pointer<Utf8> pattern);
typedef _FreeStringNative = Void Function(Pointer<Utf8> str);
typedef _FreeString = void Function(Pointer<Utf8> str);

class NativeLocalFile extends LocalFile {
  NativeLocalFile(String path) : super(path);

  @override
  Future<Uint8List> readContents() {
    File file = File(path);
    return file.readAsBytes();
  }
}

class NativePlatformUtils extends PlatformsUtils {
  @override
  bool isNativeApp() => true;

  @override
  void saveSettingsValue(String key, String? value) {
    List<String> parts = key.split('/');
    String filePath = userSettingsFilePath('settings');
    File file = File(filePath);
    Config config;
    if (file.existsSync()) {
      List<String> lines = file.readAsLinesSync();
      config = Config.fromStrings(lines);
    } else {
      config = Config();
    }
    if (value == null) {
      config.removeOption(parts[0], parts[1]);
    } else {
      if (!config.hasSection(parts[0])) {
        config.addSection(parts[0]);
      }
      config.set(parts[0], parts[1], value);
    }
    Directory parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    file.writeAsStringSync(config.toString());
  }

  @override
  String? getWsApiUrl() {
    String filePath = globalSettingsFilePath('yajudge');
    File file = File(filePath);
    if (!file.existsSync()) {
      return null;
    }
    List<String> lines = file.readAsLinesSync();
    Config config = Config.fromStrings(lines);
    if (config.hasOption('Server', 'ws_api_url')) {
      return config.get('Server', 'ws_api_url');
    } else {
      return null;
    }
  }

  @override
  String? loadSettingsValue(String key) {
    List<String> parts = key.split('/');
    // MacOS runs flutter apps in containers
    String filePath = userSettingsFilePath('settings');
    File file = File(filePath);
    if (!file.existsSync()) {
      return null;
    }
    List<String> lines = file.readAsLinesSync();
    Config config = Config.fromStrings(lines);
    if (config.hasOption(parts[0], parts[1])) {
      return config.get(parts[0], parts[1]);
    } else {
      return null;
    }
  }

  String userSettingsFilePath(String base) {
    return Platform.environment['HOME']! + '/.config/yajudge/' + base + '.ini';
  }

  String cachedCourseFilePath(String base) {
    return Platform.environment['HOME']! + '/.cache/yajudge/' + base + '.json';
  }

  String globalSettingsFilePath(String base) {
    String userFile = userSettingsFilePath(base);
    if (!File(userFile).existsSync()) {
      return '/etc/yajudge/' + base + '.ini';
    }
    return userFile;
  }

  @override
  Future<CourseContentResponse?> findCachedCourse(String courseId) {
    if (disableCoursesCache) {
      return Future.value(null);
    }
    String fileName = cachedCourseFilePath(courseId);
    if (!File(fileName).existsSync()) {
      return Future.value(null);
    }
    String jsonContents = File(fileName).readAsStringSync();
    var jsonData = jsonDecode(jsonContents);
    CourseContentResponse result = CourseContentResponse.fromJson(jsonData);
    return Future.value(result);
  }

  @override
  void storeCourseInCache(CourseContentResponse courseContent) {
    if (disableCoursesCache) {
      return;
    }
    String fileName = cachedCourseFilePath(courseContent.courseDataId);
    var jsonData = courseContent.toJson();
    String jsonContents = jsonEncode(jsonData);
    File file = File(fileName);
    Directory parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    file.writeAsString(jsonContents, flush: true);
  }

  Future<LocalFile?> pickLocalFileOpen(List<String>? allowedSuffices) {
    Pointer<Utf8> patternArgument = Pointer.fromAddress(0);
    if (allowedSuffices != null && allowedSuffices.isNotEmpty) {
      String pattern = allowedSuffices.join(';');
      patternArgument = pattern.toNativeUtf8();
    }
    DynamicLibrary library = DynamicLibrary.executable();
    _OpenFileNative openFileFunc =
      library.lookupFunction<_OpenFileNative,_OpenFileNative>('file_picker_open_file');
    _FreeString freeFunc =
      library.lookupFunction<_FreeStringNative,_FreeString>('file_picker_free_string');
    if (openFileFunc == null) {
      return Future.error('Cant find required native symbols in runner executable');
    }
    Pointer<Utf8> nativeFilePath = openFileFunc(patternArgument);
    if (nativeFilePath.address==0) {
      return Future.value(null);
    }
    String filePath = nativeFilePath.toDartString();
    freeFunc(nativeFilePath);
    return Future.value(NativeLocalFile(filePath));
  }

}

PlatformsUtils getPlatformSettings() {
  if (Platform.isMacOS || Platform.isLinux) {
    return NativePlatformUtils();
  }
  throw 'This platform is not supported';
}