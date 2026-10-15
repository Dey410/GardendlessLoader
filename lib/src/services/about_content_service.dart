import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

typedef AboutContentHttpLoader = HttpTextLoader;

typedef AboutContentJsonLoader = Future<String> Function();

typedef AboutContentHttpResponse = HttpTextResponse;

class AboutContentService {
  AboutContentService({
    String remoteUrl = remoteAboutContentUrl,
    Duration timeout = aboutContentTimeout,
    int maxBytes = aboutContentMaxBytes,
    AboutContentHttpLoader? loader,
    AboutContentJsonLoader? bundledJsonLoader,
  })  : _remoteUri = Uri.parse(remoteUrl),
        _timeout = timeout,
        _maxBytes = maxBytes,
        _loader = loader ?? loadHttpText,
        _bundledJsonLoader = bundledJsonLoader ??
            (() => rootBundle.loadString('about_content.json'));

  final Uri _remoteUri;
  final Duration _timeout;
  final int _maxBytes;
  final AboutContentHttpLoader _loader;
  final AboutContentJsonLoader _bundledJsonLoader;

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

  Future<AboutContent> _loadLocalContent(File cacheFile) async {
    final cachedContent = await _tryLoadFile(cacheFile);
    if (cachedContent != null) {
      return cachedContent;
    }

    final content =
        AboutContent.fromJson(jsonDecode(await _bundledJsonLoader()));
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(jsonEncode(content.toJson()));
    return content;
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
}

const localFallbackAboutContent = AboutContent(
  contentVersion: 1,
  content: 'GardendlessLoader 本地资源加载器',
);
