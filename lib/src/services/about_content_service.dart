import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../constants.dart';
import '../models.dart';
import 'app_logger.dart';

typedef AboutContentHttpLoader = Future<AboutContentHttpResponse> Function(
  Uri uri,
  Duration timeout,
  int maxBytes,
);

typedef AboutContentJsonLoader = Future<String> Function();

class AboutContentHttpResponse {
  const AboutContentHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class AboutContentService {
  AboutContentService({
    String remoteUrl = remoteAboutContentUrl,
    Duration timeout = aboutContentTimeout,
    int maxBytes = aboutContentMaxBytes,
    AboutContentHttpLoader? loader,
    AboutContentJsonLoader? bundledJsonLoader,
    AboutContent fallbackContent = localFallbackAboutContent,
    AppLogger? logger,
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _bundledJsonLoader = bundledJsonLoader ??
            (() => rootBundle.loadString('about_content.json')),
        _fallbackContent = fallbackContent,
        _logger = logger ?? AppLogger.instance;

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AboutContentHttpLoader _loader;
  final AboutContentJsonLoader _bundledJsonLoader;
  final AboutContent _fallbackContent;
  final AppLogger _logger;

  Future<AboutContent> refreshContent({required File cacheFile}) async {
    final operation = _logger.beginOperation(
      'content.about',
      'About content synchronization',
      data: <String, Object?>{
        'cacheFile': cacheFile.path,
        'remoteUri': _remoteUri,
        'timeoutMs': _timeout.inMilliseconds,
        'maxBytes': _maxBytes,
      },
    );
    try {
      final currentContent = await _loadLocalContent(cacheFile);
      operation.step(
        'Local about content resolved',
        data: <String, Object?>{
          'currentVersion': currentContent.contentVersion,
        },
      );
      final remoteContent = await _loadRemoteContent(
        operationId: operation.operationId,
      );
      if (remoteContent == null) {
        operation.complete(
          message: 'About content synchronization used local content',
          data: <String, Object?>{
            'selectedVersion': currentContent.contentVersion,
            'remoteAvailable': false,
          },
        );
        return currentContent;
      }
      if (remoteContent.contentVersion <= currentContent.contentVersion) {
        operation.complete(
          message: 'About content is already current',
          data: <String, Object?>{
            'selectedVersion': currentContent.contentVersion,
            'remoteVersion': remoteContent.contentVersion,
            'cacheUpdated': false,
          },
        );
        return currentContent;
      }

      try {
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(
          jsonEncode(remoteContent.toJson()),
          flush: true,
        );
      } catch (error, stackTrace) {
        operation.fail(
          error,
          stackTrace,
          message: 'About content cache write failed',
          code: 'about_cache_write_failed',
          data: <String, Object?>{
            'remoteVersion': remoteContent.contentVersion,
            'cacheFile': cacheFile.path,
          },
        );
        rethrow;
      }
      operation.complete(
        message: 'About content cache updated',
        data: <String, Object?>{
          'previousVersion': currentContent.contentVersion,
          'selectedVersion': remoteContent.contentVersion,
          'cacheUpdated': true,
        },
      );
      return remoteContent;
    } catch (error, stackTrace) {
      operation.fail(
        error,
        stackTrace,
        code: 'about_content_sync_failed',
      );
      rethrow;
    }
  }

  Future<AboutContent> loadLocalContent({required File cacheFile}) {
    return _loadLocalContent(cacheFile);
  }

  Future<AboutContent> _loadLocalContent(File cacheFile) async {
    final cachedContent = await _tryLoadFile(cacheFile);
    if (cachedContent != null) {
      _logger.debug(
        'content.about.cache',
        'About content loaded from cache',
        data: <String, Object?>{
          'path': cacheFile.path,
          'contentVersion': cachedContent.contentVersion,
        },
      );
      return cachedContent;
    }

    try {
      final bundled = AboutContent.fromJson(
        jsonDecode(await _bundledJsonLoader()),
      );
      _logger.debug(
        'content.about.bundle',
        'About content loaded from bundled asset',
        data: <String, Object?>{
          'contentVersion': bundled.contentVersion,
        },
      );
      return bundled;
    } catch (error, stackTrace) {
      _logger.warning(
        'content.about.bundle',
        'Bundled about content was unavailable; fallback selected',
        code: 'about_bundle_invalid',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{
          'fallbackVersion': _fallbackContent.contentVersion,
        },
      );
      return _fallbackContent;
    }
  }

  Future<AboutContent?> _tryLoadFile(File file) async {
    try {
      if (!await file.exists()) {
        _logger.traceLog(
          'content.about.cache',
          'About content cache does not exist',
          data: <String, Object?>{'path': file.path},
        );
        return null;
      }
      return AboutContent.fromJson(jsonDecode(await file.readAsString()));
    } catch (error, stackTrace) {
      _logger.warning(
        'content.about.cache',
        'About content cache was unreadable',
        code: 'about_cache_invalid',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'path': file.path},
      );
      return null;
    }
  }

  Future<AboutContent?> _loadRemoteContent({String? operationId}) async {
    try {
      final response =
          await _loader(_remoteUri, _timeout, _maxBytes).timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        _logger.warning(
          'network.about',
          'About content endpoint returned a non-success status',
          operationId: operationId,
          code: 'about_http_status',
          data: <String, Object?>{
            'statusCode': response.statusCode,
            'uri': _remoteUri,
          },
        );
        return null;
      }
      final content = AboutContent.fromJson(jsonDecode(response.body));
      _logger.debug(
        'network.about',
        'Remote about content parsed',
        operationId: operationId,
        data: <String, Object?>{
          'contentVersion': content.contentVersion,
          'bodyBytes': utf8.encode(response.body).length,
        },
      );
      return content;
    } catch (error, stackTrace) {
      _logger.warning(
        'network.about',
        'Remote about content was unavailable',
        operationId: operationId,
        code: 'about_remote_unavailable',
        error: error,
        stackTrace: stackTrace,
        data: <String, Object?>{'uri': _remoteUri},
      );
      return null;
    }
  }

  static Future<AboutContentHttpResponse> _loadWithHttpClient(
    Uri uri,
    Duration timeout,
    int maxBytes,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final contentLength = response.contentLength;
      if (contentLength > maxBytes) {
        throw const FormatException('about content response is too large');
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) {
          final nextLength = buffer.length + chunk.length;
          if (nextLength > maxBytes) {
            throw const FormatException('about content response is too large');
          }
          buffer.addAll(chunk);
          return buffer;
        },
      ).timeout(timeout);

      return AboutContentHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }
}

const localFallbackAboutContent = AboutContent(
  contentVersion: 1,
  content: 'GardendlessLoader 本地资源加载器',
);
