import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

typedef BlobDownloadResolver = Future<GameDownloadPayload> Function(String url);
typedef DirectoryProvider = Future<Directory> Function();
typedef FileSharer = Future<void> Function(
  GameDownloadFile file,
  Rect sharePositionOrigin,
);
typedef HttpClientFactory = HttpClient Function();
typedef UriPredicate = bool Function(Uri uri);

class GameDownloadService {
  GameDownloadService({
    DirectoryProvider? temporaryDirectoryProvider,
    FileSharer? fileSharer,
    HttpClientFactory? httpClientFactory,
    UriPredicate? isAllowedHttpUri,
  })  : _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _fileSharer = fileSharer ?? _shareFile,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _isAllowedHttpUri = isAllowedHttpUri ?? _isLocalHttpUri;

  final DirectoryProvider _temporaryDirectoryProvider;
  final FileSharer _fileSharer;
  final HttpClientFactory _httpClientFactory;
  final UriPredicate _isAllowedHttpUri;

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
    );
  }

  Future<GameDownloadFile> exportDownload({
    required GameDownloadRequest request,
    required Rect sharePositionOrigin,
    BlobDownloadResolver? blobResolver,
  }) async {
    final file = await prepareDownload(
      request: request,
      blobResolver: blobResolver,
    );
    await _fileSharer(file, sharePositionOrigin);
    return file;
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

class GameDownloadFileSharer {
  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/game_file_exporter',
  );

  static Future<void> share(
    GameDownloadFile file,
    Rect sharePositionOrigin,
  ) async {
    await _channel.invokeMethod<void>('shareFile', {
      'path': file.path,
      'name': file.name,
      'mimeType': file.mimeType,
      'originX': sharePositionOrigin.left,
      'originY': sharePositionOrigin.top,
      'originWidth': sharePositionOrigin.width,
      'originHeight': sharePositionOrigin.height,
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
    required this.path,
    required this.name,
    required this.byteLength,
    this.mimeType,
  });

  final String path;
  final String name;
  final String? mimeType;
  final int byteLength;
}

class GameDownloadFailure implements Exception {
  const GameDownloadFailure(this.message);

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
  return switch (mimeType?.split(';').first.trim().toLowerCase()) {
    'application/json' => '.json',
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

Future<void> _shareFile(
  GameDownloadFile file,
  Rect sharePositionOrigin,
) async {
  await GameDownloadFileSharer.share(file, sharePositionOrigin);
}
