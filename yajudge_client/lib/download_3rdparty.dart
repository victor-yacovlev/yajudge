/* Script to make local copy of dependencies */

import 'dart:io' as io;

const mainDartJs = 'build/web/main.dart.js';
const outDir = 'build/web/cached';
const localPrefix = '/cached';

String normalizeFileName(String source) {
  String result = source;
  result = result.replaceAll('=', '/');
  result = result.replaceAll('?', '/');
  List<String> parts = result.split('/');
  result = parts.last;
  return result;
}

Future<bool> downloadFile(Uri src, String targetName) async {
  final httpClient = io.HttpClient();
  final request = await httpClient.getUrl(src);
  final response = await request.close();
  final outFile = io.File('$outDir/$targetName');
  final status = response.statusCode;
  if (status == 200) {
    await response.pipe(outFile.openWrite());
    return true;
  }
  else {
    return false;
  }
}

String cleanLink(String src) {
  String result = '';
  for (int i=1; i<src.length; i++) {
    if (src[i] == '"') {
      break;
    }
    result += src[i];
  }
  return result;
}

Future processFile(io.File file) async {
  if (!io.Directory(outDir).existsSync()) {
    io.Directory(outDir).create(recursive: true);
  }
  final sourceContent = file.readAsStringSync();
  String newContent = sourceContent;
  final rxLinkConstant = RegExp(r'"(http|https)://(.+)/(.+)"');
  final matches = rxLinkConstant.allMatches(sourceContent);
  for (final match in matches) {
    String src = cleanLink(match.group(0)!);
    Uri sourceUri = Uri.parse(src);
    String fileName = normalizeFileName(src);
    if (src.contains('yajudge')) {
      continue;
    }
    if (sourceUri.path.startsWith('/canvaskit-wasm@')) {
      fileName = 'canvaskit.wasm';
    }
    else if (sourceUri.host.isEmpty || sourceUri.host == 'www.w3.org') {
      continue;
    }
    if (fileName.isEmpty) {
      continue;
    }
    if (await downloadFile(sourceUri, fileName)) {
      print('Saved $sourceUri to $outDir/$fileName');
      newContent = newContent.replaceAll(src, '"$localPrefix/$fileName"');
    }
  }
  file.writeAsStringSync(newContent);
}

void main() async {
  print('Downloading third-party hosted files to local cache...');
  await processFile(io.File(mainDartJs));
  print('Download done');
}