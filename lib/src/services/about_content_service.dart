import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../constants.dart';
import '../models.dart';

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
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? _loadWithHttpClient,
        _bundledJsonLoader = bundledJsonLoader ??
            (() => rootBundle.loadString('about_content.json')),
        _fallbackContent = fallbackContent;

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AboutContentHttpLoader _loader;
  final AboutContentJsonLoader _bundledJsonLoader;
  final AboutContent _fallbackContent;

  Future<AboutContent> refreshContent({required File cacheFile}) async {
    final currentContent = await _loadLocalContent(cacheFile);
    final remoteContent = await _loadRemoteContent();
    if (remoteContent == null ||
        remoteContent.contentVersion <= currentContent.contentVersion) {
      return currentContent;
    }

    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(jsonEncode(remoteContent.toJson()));
    return remoteContent;
  }

  Future<AboutContent> loadLocalContent({required File cacheFile}) {
    return _loadLocalContent(cacheFile);
  }

  Future<AboutContent> _loadLocalContent(File cacheFile) async {
    final cachedContent = await _tryLoadFile(cacheFile);
    if (cachedContent != null) {
      return cachedContent;
    }

    try {
      return AboutContent.fromJson(jsonDecode(await _bundledJsonLoader()));
    } catch (_) {
      return _fallbackContent;
    }
  }

  Future<AboutContent?> _tryLoadFile(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      return AboutContent.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<AboutContent?> _loadRemoteContent() async {
    try {
      final response =
          await _loader(_remoteUri, _timeout, _maxBytes).timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return AboutContent.fromJson(jsonDecode(response.body));
    } catch (_) {
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
