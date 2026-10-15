import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../constants.dart';
import 'http_text.dart';
import '../models.dart';

class AboutContentService {
  static final Uri _remoteUri = Uri.parse(remoteAboutContentUrl);

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

    final content = AboutContent.fromJson(
        jsonDecode(await rootBundle.loadString('about_content.json')));
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
      final response = await loadHttpText(
        _remoteUri,
        aboutContentTimeout,
        aboutContentMaxBytes,
      ).timeout(aboutContentTimeout);
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
