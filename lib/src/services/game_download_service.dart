import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

typedef BlobDownloadResolver = Future<GameDownloadPayload> Function(String url);
typedef DirectoryProvider = Future<Directory> Function();
typedef FileExporter = Future<void> Function(
  GameDownloadFile file,
  Rect presentationOrigin,
);
typedef SaveLocationPicker = Future<file_selector.FileSaveLocation?> Function({
  required List<file_selector.XTypeGroup> acceptedTypeGroups,
  String? suggestedName,
  String? confirmButtonText,
});
typedef FileSaver = Future<void> Function(GameDownloadFile file, String path);
typedef HttpClientFactory = HttpClient Function();
typedef WebHttpDownload = Future<GameDownloadPayload> Function(
  GameDownloadRequest request,
);
typedef PlatformNameProvider = String Function();
typedef UriPredicate = bool Function(Uri uri);

class GameDownloadService {
  GameDownloadService({
    DirectoryProvider? temporaryDirectoryProvider,
    FileExporter? fileExporter,
    SaveLocationPicker? saveLocationPicker,
    FileSaver? fileSaver,
    HttpClientFactory? httpClientFactory,
    WebHttpDownload? webHttpDownload,
    PlatformNameProvider? platformNameProvider,
    UriPredicate? isAllowedHttpUri,
    bool? isWeb,
  })  : _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _platformNameProvider =
            platformNameProvider ?? (() => Platform.operatingSystem),
        _saveLocationPicker = saveLocationPicker ?? _pickSaveLocation,
        _fileSaver = fileSaver ?? _saveFileToPath,
        _fileExporter = fileExporter,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _webHttpDownload = webHttpDownload ?? _downloadWebHttp,
        _isAllowedHttpUri = isAllowedHttpUri ?? _isLocalHttpUri,
        _isWeb = isWeb ?? kIsWeb;

  final DirectoryProvider _temporaryDirectoryProvider;
  final PlatformNameProvider _platformNameProvider;
  final SaveLocationPicker _saveLocationPicker;
  final FileSaver _fileSaver;
  final FileExporter? _fileExporter;
  final HttpClientFactory _httpClientFactory;
  final WebHttpDownload _webHttpDownload;
  final UriPredicate _isAllowedHttpUri;
  final bool _isWeb;

  Future<GameDownloadFile> prepareDownload({
    required GameDownloadRequest request,
    BlobDownloadResolver? blobResolver,
  }) async {
    final payload = switch (request.uri.scheme) {
      'blob' => await _resolveBlob(request.uri, blobResolver),
      'data' => GameDownloadPayload.fromDataUri(request.uri.toString()),
      'http' || 'https' => await _downloadHttp(request),
      _ => throw GameDownloadFailure('不支持的导出地址：${request.uri.scheme}'),
    };
    final mimeType = _effectiveMimeType(
      requestMimeType: request.mimeType,
      payloadMimeType: payload.mimeType,
      bytes: payload.bytes,
    );
    final fileName = downloadFileName(
      suggestedFilename: request.suggestedFilename,
      contentDisposition: request.contentDisposition,
      mimeType: mimeType,
      preferJsonExtension: _isJsonMimeType(mimeType),
    );

    if (_isWeb) {
      return GameDownloadFile(
        name: fileName,
        mimeType: mimeType,
        byteLength: payload.bytes.length,
        bytes: payload.bytes,
      );
    }

    final directory = await _temporaryDirectoryProvider();
    final exportDirectory = Directory(p.join(directory.path, 'game_exports'));
    await exportDirectory.create(recursive: true);
    final file = File(p.join(exportDirectory.path, fileName));
    await file.writeAsBytes(payload.bytes, flush: true);
    return GameDownloadFile(
      path: file.path,
      name: fileName,
      mimeType: mimeType,
      byteLength: payload.bytes.length,
      bytes: payload.bytes,
    );
  }

  Future<GameDownloadFile> exportDownload({
    required GameDownloadRequest request,
    required Rect presentationOrigin,
    BlobDownloadResolver? blobResolver,
  }) async {
    final file = await prepareDownload(
      request: request,
      blobResolver: blobResolver,
    );
    final exporter = _fileExporter ?? _defaultExportFile;
    await exporter(file, presentationOrigin);
    return file;
  }

  Future<void> _defaultExportFile(
    GameDownloadFile file,
    Rect presentationOrigin,
  ) async {
    if (!_isWeb) {
      final platformName = _platformNameProvider();
      if (_usesNativeFileExporter(platformName)) {
        await GameDownloadFileExporter.export(file, presentationOrigin);
        return;
      }
    }

    final location = await _saveLocationPicker(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'JSON save file',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
          webWildCards: ['application/json'],
        ),
      ],
      suggestedName: file.name,
      confirmButtonText: '保存',
    );
    if (location == null) {
      throw const GameDownloadFailure.cancelled();
    }
    await _fileSaver(file, location.path);
  }

  Future<GameDownloadPayload> _resolveBlob(
    Uri uri,
    BlobDownloadResolver? resolver,
  ) {
    if (resolver == null) {
      throw GameDownloadFailure('当前 WebView 无法读取 Blob 导出内容');
    }
    return resolver(uri.toString());
  }

  Future<GameDownloadPayload> _downloadHttp(GameDownloadRequest request) async {
    if (!_isAllowedHttpUri(request.uri)) {
      throw GameDownloadFailure('已拦截非本地导出地址');
    }
    if (_isWeb) {
      return _webHttpDownload(request);
    }

    final client = _httpClientFactory();
    try {
      final httpRequest = await client.getUrl(request.uri);
      final userAgent = request.userAgent;
      if (userAgent != null && userAgent.trim().isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      final response = await httpRequest.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw GameDownloadFailure('导出下载失败：HTTP ${response.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return GameDownloadPayload(
        bytes: bytes,
        mimeType: response.headers.contentType?.mimeType ?? request.mimeType,
      );
    } finally {
      client.close(force: true);
    }
  }
}

Future<GameDownloadPayload> _downloadWebHttp(
    GameDownloadRequest request) async {
  final response = await http.get(request.uri);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw GameDownloadFailure('导出下载失败：HTTP ${response.statusCode}');
  }
  return GameDownloadPayload(
    bytes: response.bodyBytes,
    mimeType: response.headers['content-type']?.split(';').first.trim() ??
        request.mimeType,
  );
}

class GameDownloadFileExporter {
  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/game_file_exporter',
  );

  static Future<void> export(
    GameDownloadFile file,
    Rect presentationOrigin,
  ) async {
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const GameDownloadFailure('当前平台缺少导出临时文件路径');
    }

    await _channel.invokeMethod<void>('exportFile', {
      'path': path,
      'name': file.name,
      'mimeType': file.mimeType,
      'originX': presentationOrigin.left,
      'originY': presentationOrigin.top,
      'originWidth': presentationOrigin.width,
      'originHeight': presentationOrigin.height,
    });
  }
}

class GameDownloadRequest {
  const GameDownloadRequest({
    required this.uri,
    this.suggestedFilename,
    this.contentDisposition,
    this.mimeType,
    this.userAgent,
  });

  final Uri uri;
  final String? suggestedFilename;
  final String? contentDisposition;
  final String? mimeType;
  final String? userAgent;
}

class GameDownloadPayload {
  const GameDownloadPayload({
    required this.bytes,
    this.mimeType,
  });

  factory GameDownloadPayload.fromDataUri(
    String dataUri, {
    String? mimeTypeOverride,
  }) {
    final commaIndex = dataUri.indexOf(',');
    if (!dataUri.startsWith('data:') || commaIndex < 0) {
      throw GameDownloadFailure('导出 data URL 无效');
    }

    final metadata = dataUri.substring(5, commaIndex);
    final encodedData = dataUri.substring(commaIndex + 1);
    final parts = metadata
        .split(';')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    final mimeType = mimeTypeOverride ??
        parts.firstWhere(
          (part) => part.contains('/') && !part.contains('='),
          orElse: () => 'text/plain',
        );
    final isBase64 = parts.any((part) => part.toLowerCase() == 'base64');

    return GameDownloadPayload(
      bytes: isBase64
          ? base64Decode(encodedData)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(encodedData))),
      mimeType: mimeType,
    );
  }

  final Uint8List bytes;
  final String? mimeType;
}

class GameDownloadFile {
  const GameDownloadFile({
    required this.name,
    required this.byteLength,
    required this.bytes,
    this.path,
    this.mimeType,
  });

  final String? path;
  final String name;
  final String? mimeType;
  final int byteLength;
  final Uint8List bytes;
}

class GameDownloadFailure implements Exception {
  const GameDownloadFailure(this.message);
  const GameDownloadFailure.cancelled() : message = '已取消导出';

  final String message;

  @override
  String toString() => message;
}

String downloadFileName({
  String? suggestedFilename,
  String? contentDisposition,
  String? mimeType,
  bool preferJsonExtension = false,
}) {
  final candidates = [
    suggestedFilename,
    _fileNameFromContentDisposition(contentDisposition),
  ];
  for (final candidate in candidates) {
    final sanitized = _sanitizeFileName(candidate);
    if (sanitized != null) {
      return preferJsonExtension ? _withJsonExtension(sanitized) : sanitized;
    }
  }
  return 'gardendless-export${_extensionForMimeType(mimeType)}';
}

String? _effectiveMimeType({
  required String? requestMimeType,
  required String? payloadMimeType,
  required Uint8List bytes,
}) {
  final explicitMimeType =
      _normalMimeType(requestMimeType) ?? _normalMimeType(payloadMimeType);
  if (_isGenericMimeType(explicitMimeType) && _looksLikeJson(bytes)) {
    return 'application/json';
  }
  return explicitMimeType;
}

String? _normalMimeType(String? value) {
  final mimeType = value?.split(';').first.trim();
  return mimeType == null || mimeType.isEmpty ? null : mimeType;
}

bool _isGenericMimeType(String? mimeType) {
  return mimeType == null ||
      mimeType == 'application/octet-stream' ||
      mimeType == 'text/plain';
}

bool _isJsonMimeType(String? mimeType) {
  return mimeType?.toLowerCase() == 'application/json' ||
      mimeType?.toLowerCase().endsWith('+json') == true;
}

bool _looksLikeJson(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes).trim();
    if (text.isEmpty) {
      return false;
    }
    final decoded = jsonDecode(text);
    return decoded is Map || decoded is List;
  } catch (_) {
    return false;
  }
}

String? _fileNameFromContentDisposition(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final starMatch = RegExp(
    r'''filename\*\s*=\s*(?:UTF-8''|utf-8'')?([^;]+)''',
  ).firstMatch(value);
  if (starMatch != null) {
    return Uri.decodeComponent(_trimQuotes(starMatch.group(1)!));
  }

  final filenameMatch = RegExp(
    r'''filename\s*=\s*("([^"]+)"|[^;]+)''',
  ).firstMatch(value);
  if (filenameMatch != null) {
    return _trimQuotes(filenameMatch.group(2) ?? filenameMatch.group(1)!);
  }

  return null;
}

String? _sanitizeFileName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final basename = p.basename(trimmed.replaceAll('\\', '/')).trim();
  final cleaned = basename
      .replaceAll(RegExp(r'[\x00-\x1f]'), '')
      .replaceAll(RegExp(r'[:*?"<>|]'), '_')
      .trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    return null;
  }
  return cleaned;
}

String _withJsonExtension(String fileName) {
  return p.extension(fileName).toLowerCase() == '.json'
      ? fileName
      : '${p.withoutExtension(fileName)}.json';
}

String _trimQuotes(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _extensionForMimeType(String? mimeType) {
  final normalized = mimeType?.split(';').first.trim().toLowerCase();
  if (_isJsonMimeType(normalized)) {
    return '.json';
  }
  return switch (normalized) {
    'text/plain' => '.txt',
    'text/csv' => '.csv',
    'application/zip' => '.zip',
    _ => '.bin',
  };
}

bool _isLocalHttpUri(Uri uri) {
  return uri.scheme == 'http' &&
      uri.host == localServerHost &&
      uri.port == localServerPort;
}

bool _usesNativeFileExporter(String platformName) {
  return platformName == 'android' ||
      platformName == 'ios' ||
      platformName == 'ohos';
}

Future<file_selector.FileSaveLocation?> _pickSaveLocation({
  required List<file_selector.XTypeGroup> acceptedTypeGroups,
  String? suggestedName,
  String? confirmButtonText,
}) {
  return file_selector.getSaveLocation(
    acceptedTypeGroups: acceptedTypeGroups,
    suggestedName: suggestedName,
    confirmButtonText: confirmButtonText,
  );
}

Future<void> _saveFileToPath(
  GameDownloadFile file,
  String destinationPath,
) async {
  final sourcePath = file.path;
  final exportFile = sourcePath == null || sourcePath.isEmpty
      ? file_selector.XFile.fromData(
          file.bytes,
          name: file.name,
          mimeType: file.mimeType,
        )
      : file_selector.XFile(
          sourcePath,
          name: file.name,
          mimeType: file.mimeType,
        );
  await exportFile.saveTo(destinationPath);
}
