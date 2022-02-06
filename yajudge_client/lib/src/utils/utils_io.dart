import 'dart:convert';
import 'dart:typed_data';

import 'package:yajudge_common/yajudge_common.dart';
import 'package:yaml_writer/yaml_writer.dart';

import 'utils.dart';
import 'dart:io' as io;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:yaml/yaml.dart';

typedef _OpenFileNative = Pointer<Utf8> Function(Pointer<Utf8> pattern);
typedef _SaveFileNative = Pointer<Utf8> Function(Pointer<Utf8> name);
typedef _FreeStringNative = Void Function(Pointer<Utf8> str);
typedef _FreeString = void Function(Pointer<Utf8> str);

class NativeLocalFile extends LocalFile {
  NativeLocalFile(String path) : super(path);

  @override
  Future<Uint8List> readContents() {
    io.File file = io.File(path);
    return file.readAsBytes();
  }

  @override
  void writeContent(List<int> data) {
    io.File file = io.File(path);
    file.writeAsBytesSync(data);
  }
}

class NativePlatformUtils extends PlatformsUtils {
  @override
  bool isNativeApp() => true;

  @override
  void saveSettingsValue(String key, String? value) {
    List<String> parts = key.split('/');
    String filePath = userSettingsFilePath('client');
    io.File file = io.File(filePath);
    Map<String,dynamic> root;
    if (file.existsSync()) {
      YamlNode document = loadYaml(file.readAsStringSync(), sourceUrl: Uri.file(filePath));
      root = convertYamlNodeToNativeStructures(document);
    } else {
      root = {};
    }
    Map? parent = root;
    for (int i=0; i<parts.length-1; i++) {
      String part = parts[i];
      if (parent!.containsKey(part) && parent[part] is YamlMap) {
        parent = parent[part];
      } else {
        if (value == null) {
          break;
        }
        parent[part] = Map<String,dynamic>();
        parent = parent[part];
      }
    }
    if (value == null && parent != null) {
      parent.remove(parts.last);
    } else if (value != null && parent != null) {
      parent[parts.last] = value;
    }
    io.Directory parentDir = file.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    YAMLWriter yamlWriter = YAMLWriter();
    String yamlContent = yamlWriter.write(root);
    file.writeAsStringSync(yamlContent);
  }

  static dynamic convertYamlNodeToNativeStructures(dynamic root) {
    if (root is YamlScalar) {
      return root.value;
    } else if (root is YamlList) {
      List result = [];
      for (YamlNode entry in root.value) {
        result.add(convertYamlNodeToNativeStructures(entry));
      }
      return result;
    } else if (root is YamlMap) {
      Map<String,dynamic> result = {};
      for (MapEntry entry in root.entries) {
        String key = entry.key;
        dynamic value = entry.value;
        result[key] = convertYamlNodeToNativeStructures(value);
      }
      return result;
    } else {
      return root.toString();
    }
  }

  static String writeYaml(YamlNode root, {int level = 0}) {
    String result = '';
    if (root is YamlScalar) {
      result = root.toString();
    } else if (root is YamlMap) {
      result += '\n';
      String spaces = '  ' * level;
      for (MapEntry entry in root.entries) {
        String key = entry.key;
        YamlNode value = entry.value;
        result += spaces + key + ': ' + writeYaml(value, level: level+1);
      };
    } else if (root is YamlList) {
      result += '\n';
      String spaces = '  ' * level;
      for (YamlNode value in root.value) {
        result += spaces + '- ' + writeYaml(value, level: level+1);
      }
    }
    return result + '\n';
  }

  @override
  Uri getGrpcApiUri(List<String>? arguments) {
    Uri result = Uri.parse('grpc://localhost:9095/');
    if (arguments==null)
      return result;
    for (String arg in arguments) {
      Uri candidate = Uri();
      if (!arg.startsWith('-')) {
        candidate = Uri.parse(arg);
        if (candidate.scheme=='grpc') {
          result = candidate;
          break;
        }
      }
    }
    return result;
  }

  @override
  String? loadSettingsValue(String key) {
    List<String> parts = key.split('/');
    String filePath = userSettingsFilePath('client');
    io.File file = io.File(filePath);
    if (!file.existsSync()) {
      return null;
    }
    dynamic? current = loadYaml(file.readAsStringSync(), sourceUrl: Uri.file(file.path));
    for (String part in parts) {
      if (current is YamlMap && current.containsKey(part)) {
        current = current[part];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) {
      return current.toString();
    } else {
      return null;
    }
  }

  String userSettingsFilePath(String base) {
    return io.Platform.environment['HOME']! + '/.config/yajudge/' + base + '.yaml';
  }

  String cachedCourseFilePath(String base) {
    return io.Platform.environment['HOME']! + '/.cache/yajudge/' + base + '.json';
  }

  String globalSettingsFilePath(String base) {
    String userFile = userSettingsFilePath(base);
    if (!io.File(userFile).existsSync()) {
      return '/etc/yajudge/' + base + '.yaml';
    }
    return userFile;
  }

  @override
  Future<CourseContentResponse?> findCachedCourse(String courseId) {
    if (disableCoursesCache) {
      return Future.value(null);
    }
    String fileName = cachedCourseFilePath(courseId);
    if (!io.File(fileName).existsSync()) {
      return Future.value(null);
    }
    String jsonContents = io.File(fileName).readAsStringSync();
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
    String jsonContents = jsonEncode(courseContent);
    io.File file = io.File(fileName);
    io.Directory parent = file.parent;
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

  @override
  void saveLocalFile(String suggestName, List<int> data) {
    Pointer<Utf8> nameArgument = suggestName.toNativeUtf8();
    DynamicLibrary library = DynamicLibrary.executable();
    _SaveFileNative saveFileFunc =
    library.lookupFunction<_OpenFileNative,_OpenFileNative>('file_picker_save_file');
    _FreeString freeFunc =
    library.lookupFunction<_FreeStringNative,_FreeString>('file_picker_free_string');
    assert (saveFileFunc != null);
    Pointer<Utf8> nativeFilePath = saveFileFunc(nameArgument);
    if (nativeFilePath.address==0) {
      return;
    }
    String filePath = nativeFilePath.toDartString();
    freeFunc(nativeFilePath);
    io.File file = io.File(filePath);
    file.writeAsBytesSync(data);
  }

}

PlatformsUtils getPlatformSettings() {
  if (io.Platform.isMacOS || io.Platform.isLinux) {
    return NativePlatformUtils();
  }
  throw 'This platform is not supported';
}