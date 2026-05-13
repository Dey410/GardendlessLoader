import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

class ResourceValidator {
  Future<ResourceValidationResult> validate(Directory root) async {
    if (!await root.exists()) {
      return ResourceValidationResult.missing('${root.path} 不存在');
    }

    final requiredDirectories = [
      Directory(p.join(root.path, 'assets')),
      Directory(p.join(root.path, 'cocos-js')),
      Directory(p.join(root.path, 'src')),
    ];
    for (final directory in requiredDirectories) {
      if (!await directory.exists()) {
        return ResourceValidationResult.invalid(
          'missing_required_directory',
          '缺少目录 ${p.basename(directory.path)}',
        );
      }
    }

    final indexFile = File(p.join(root.path, 'index.html'));
    final settingsFile = File(p.join(root.path, 'src', 'settings.json'));
    final importMapFile = File(p.join(root.path, 'src', 'import-map.json'));

    for (final file in [indexFile, settingsFile, importMapFile]) {
      if (!await file.exists()) {
        return ResourceValidationResult.invalid(
          'missing_required_file',
          '缺少文件 ${p.relative(file.path, from: root.path)}',
        );
      }
    }

    final indexHtml = await indexFile.readAsString();
    final detectedTitle = _extractTitle(indexHtml);
    if (detectedTitle == null || !detectedTitle.contains('PvZ2 Gardendless')) {
      return ResourceValidationResult.invalid(
        'title_fingerprint_mismatch',
        'index.html title 未包含 PvZ2 Gardendless',
      );
    }

    final lowerIndex = indexHtml.toLowerCase();
    if (!lowerIndex.contains('pvzge') && !lowerIndex.contains('play.pvzge.com')) {
      return ResourceValidationResult.invalid(
        'index_fingerprint_mismatch',
        'index.html 未包含 pvzge 指纹',
      );
    }

    final settingsResult = await _validateSettings(settingsFile);
    if (settingsResult != null) {
      return settingsResult;
    }

    return ResourceValidationResult.valid(detectedTitle: detectedTitle);
  }

  Future<ResourceStats> scanStats(Directory root, {String? detectedTitle}) async {
    var fileCount = 0;
    var totalBytes = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        fileCount++;
        totalBytes += await entity.length();
      }
    }

    return ResourceStats(
      fileCount: fileCount,
      totalBytes: totalBytes,
      detectedTitle: detectedTitle,
    );
  }

  String? _extractTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<ResourceValidationResult?> _validateSettings(File file) async {
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return ResourceValidationResult.invalid(
        'settings_json_invalid',
        'src/settings.json 不是有效 JSON',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return ResourceValidationResult.invalid(
        'settings_cocos_config_missing',
        'src/settings.json 不包含 Cocos 配置对象',
      );
    }

    final hasCocosConfig = _hasCocosSettingsShape(decoded);
    if (!hasCocosConfig) {
      return ResourceValidationResult.invalid(
        'settings_cocos_config_missing',
        'src/settings.json 未检测到 Cocos 配置',
      );
    }

    return null;
  }

  bool _hasCocosSettingsShape(Map<String, dynamic> settings) {
    if (settings['CocosEngine'] is String &&
        settings['engine'] is Map &&
        settings['assets'] is Map &&
        settings['launch'] is Map) {
      return true;
    }

    const legacyTopLevelKeys = {
      'platform',
      'groupList',
      'collisionMatrix',
      'launchScene',
      'bundleVers',
      'remoteBundles',
      'hasResourcesBundle',
      'hasStartSceneBundle',
      'subpackages',
    };
    if (settings.keys.any(legacyTopLevelKeys.contains)) {
      return true;
    }

    final engine = settings['engine'];
    final assets = settings['assets'];
    final launch = settings['launch'];
    if (engine is Map && assets is Map && launch is Map) {
      return engine.containsKey('platform') &&
          (assets.containsKey('bundleVers') ||
              assets.containsKey('preloadBundles') ||
              assets.containsKey('projectBundles')) &&
          launch.containsKey('launchScene');
    }

    return false;
  }
}
