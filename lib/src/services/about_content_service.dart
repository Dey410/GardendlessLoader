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
    // An equal version still replaces the cache: a launcher too old to
    // know `authors` may have written that version without them.
    if (remoteContent == null ||
        remoteContent.contentVersion < currentContent.contentVersion) {
      return currentContent;
    }

    await _writeIfChanged(cacheFile, from: currentContent, to: remoteContent);
    return remoteContent;
  }

  /// The cache, unless the copy bundled with this release is at least as
  /// new: after an update the bundled authors show before the first fetch.
  Future<AboutContent> _loadLocalContent(File cacheFile) async {
    final cachedContent = await _tryLoadFile(cacheFile);
    final bundledContent = AboutContent.fromJson(
        jsonDecode(await rootBundle.loadString('about_content.json')));
    if (cachedContent != null &&
        cachedContent.contentVersion > bundledContent.contentVersion) {
      return cachedContent;
    }

    await _writeIfChanged(cacheFile, from: cachedContent, to: bundledContent);
    return bundledContent;
  }

  Future<void> _writeIfChanged(
    File cacheFile, {
    required AboutContent? from,
    required AboutContent to,
  }) async {
    final json = jsonEncode(to.toJson());
    if (from != null && jsonEncode(from.toJson()) == json) return;
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(json);
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
  contentEn: 'GardendlessLoader local resource loader',
);

/// Who made the loader, as this release knows it. The remote `authors.loader`
/// entry overrides any field.
const builtInLoaderAuthor = AboutAuthor(
  name: '你好我是小朱',
  bio: 'GardendlessLoader 的作者，把 PvZ2 Gardendless 带到手机和平板上。',
  bioEn: 'Author of GardendlessLoader, which brings PvZ2 Gardendless to '
      'phones and tablets.',
  bilibili: bilibiliHomeUrl,
  github: loaderAuthorGithubUrl,
);

/// Who made the game, as this release knows it. The remote `authors.game`
/// entry overrides any field.
const builtInGameAuthor = AboutAuthor(
  name: '南Garden',
  bio: 'PvZ2 Gardendless 的作者，用 Web 技术重写了《植物大战僵尸 2》。',
  bioEn: 'Author of PvZ2 Gardendless, a rewrite of Plants vs. Zombies 2 '
      'built with web technologies.',
  bilibili: gameAuthorBilibiliUrl,
  github: gameAuthorGithubUrl,
);
