import 'dart:typed_data';

import 'package:archive/archive.dart'
  if (dart.library.io) 'package:archive/archive_io.dart'
  if (dart.librart.html) 'package:archive/archive.dart';

import 'package:protobuf/protobuf.dart';

import '../../yajudge_common.dart';
import 'dart:io' as io;
import 'package:path/path.dart' as path;

extension FileExtension on File {
  void save(io.Directory targetDirectory) {
    if (name.isEmpty) {
      return;
    }
    targetDirectory.createSync(recursive: true);
    final fullPath = '${targetDirectory.path}/$name';
    io.File(fullPath).createSync(recursive: true);
    io.File(fullPath).writeAsBytesSync(data);
  }

  static File fromFile(io.File sourceFile, {
    String name = '',
    String description = '',
    int? permissions,
  }) {
    name = name.isEmpty? sourceFile.path : name;
    final data = sourceFile.readAsBytesSync();
    final permissionsMask = int.parse('777', radix: 8);
    int resolvedPermissions;
    if (permissions != null) {
      resolvedPermissions = permissions & permissionsMask;
    }
    else {
      final mode = sourceFile.statSync().mode;
      resolvedPermissions = mode & permissionsMask;
    }
    return File(
      name: name,
      data: data,
      permissions: resolvedPermissions,
      description: description,
    );
  }

}

extension FileSetExtension on FileSet {
  void saveAll(io.Directory targetDirectory) {
    for (final file in files) {
      file.save(targetDirectory);
    }
  }

  static const String permissionsFileName = '.permissions';

  static FileSet fromDirectory(io.Directory sourceDirectory, {
    bool recursive = false, String namePrefix = '',
  }) {
    final entries = sourceDirectory.listSync(recursive: recursive);
    final directoryPath = sourceDirectory.path;
    List<File> files = [];
    final permissions = readPermissionsFile(
        '${sourceDirectory.path}/$permissionsFileName'
    );
    for (final entry in entries) {
      if (entry is io.File) {
        final fullPath = entry.path;
        String relativePath = fullPath.substring(directoryPath.length);
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        final fileName = path.normalize('$namePrefix$relativePath');
        int? filePermissions;
        if (permissions.containsKey(relativePath)) {
          filePermissions = permissions[relativePath]!;
        }
        files.add(FileExtension.fromFile(entry, name: fileName, permissions: filePermissions));
      }
    }
    return FileSet(files: files).deepCopy();
  }

  static Map<String,int> readPermissionsFile(String permissionsPath) {
    Map<String,int> result = {};
    final permissionsMask = int.parse('777', radix: 8);
    final permissionsFile = io.File(permissionsPath);
    if (permissionsFile.existsSync()) {
      final lines = permissionsFile.readAsLinesSync();
      for (final line in lines) {
        if (line.trim().startsWith('#') || line.trim().isEmpty) {
          continue;
        }
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) {
          continue;
        }
        final fileName = parts[0];
        int? mode = int.tryParse(parts[1], radix: 8);
        if (mode != null) {
          result[fileName] = mode & permissionsMask;
        }
      }
    }
    return result;
  }

  File toTarGzBundle(String fileName) {
    final archive = Archive();
    for (final file in files) {
      final fileData = Uint8List.fromList(file.data);
      final archiveFile = ArchiveFile(file.name, file.data.length, fileData);
      archiveFile.mode = file.permissions;
      archive.addFile(archiveFile);
    }
    final tarData = TarEncoder().encode(archive);
    final gzData = GZipEncoder().encode(tarData)!.toList();
    return File(
      name: fileName,
      data: gzData,
    ).deepCopy();
  }

}