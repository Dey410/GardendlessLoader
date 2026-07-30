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
    final gpNext = await _detectGpNext(root, indexHtml);
    final normalizedTitle = detectedTitle?.replaceAll('_', ' ');
    if (normalizedTitle == null ||
        !normalizedTitle.contains('PvZ2 Gardendless')) {
      return ResourceValidationResult.invalid(
        'title_fingerprint_mismatch',
        'index.html title 未包含 PvZ2 Gardendless',
      );
    }

    final lowerIndex = indexHtml.toLowerCase();
    if (!gpNext.detected &&
        !lowerIndex.contains('pvzge') &&
        !lowerIndex.contains('play.pvzge.com')) {
      return ResourceValidationResult.invalid(
        'index_fingerprint_mismatch',
        'index.html 未包含 pvzge 指纹',
      );
    }

    final settingsResult = await _validateSettings(settingsFile);
    if (settingsResult != null) {
      return settingsResult;
    }

    return ResourceValidationResult.valid(
      detectedTitle: detectedTitle,
      buildProfile: gpNext.detected
          ? ResourceBuildProfile.gpNext
          : ResourceBuildProfile.standardWeb,
      gpNextCompatibilityError: gpNext.compatibilityError,
    );
  }

  Future<ResourceStats> scanStats(
    Directory root, {
    String? detectedTitle,
    ResourceBuildProfile buildProfile = ResourceBuildProfile.standardWeb,
    String? gpNextVersion,
    String? gpNextCompatibilityError,
  }) async {
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
      buildProfile: buildProfile,
      gpNextVersion: gpNextVersion,
      gpNextCompatibilityError: gpNextCompatibilityError,
    );
  }

  Future<_GpNextDetection> _detectGpNext(
    Directory root,
    String indexHtml,
  ) async {
    final entryPath = _moduleEntryPath(indexHtml);
    if (entryPath == null) {
      return const _GpNextDetection.notDetected();
    }

    final normalizedPath = p.normalize(
      entryPath.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), ''),
    );
    if (normalizedPath == '.' ||
        normalizedPath.startsWith('..${p.separator}') ||
        p.isAbsolute(normalizedPath)) {
      return const _GpNextDetection.notDetected();
    }
    final entryFile = File(p.join(root.path, normalizedPath));
    if (!await entryFile.exists()) {
      return const _GpNextDetection.notDetected();
    }

    final entry = await entryFile.readAsString();
    final hasMarker = entry.contains('GP-Next loading') &&
        entry.contains('window.gpNext') &&
        entry.contains('loadAllPatches');
    if (!hasMarker) {
      return const _GpNextDetection.notDetected();
    }

    final requiredFingerprints = {
      'patcher module': 'patcher-',
      'file loader module': 'file-loader-',
      'JS mod loader module': 'js-mod-loader-',
    };
    final missing = requiredFingerprints.entries
        .where((entryFingerprint) => !entry.contains(entryFingerprint.value))
        .map((entryFingerprint) => entryFingerprint.key)
        .toList(growable: false);
    final compatibilityError =
        missing.isEmpty ? null : 'GP-Next 缺少兼容模块：${missing.join(', ')}';
    return _GpNextDetection(
      detected: true,
      compatibilityError: compatibilityError,
    );
  }

  String? _moduleEntryPath(String indexHtml) {
    final scripts = RegExp(
      r'<script\b[^>]*>',
      caseSensitive: false,
    ).allMatches(indexHtml);
    for (final script in scripts) {
      final tag = script.group(0)!;
      final type = RegExp(
        r'''\btype\s*=\s*["']module["']''',
        caseSensitive: false,
      ).hasMatch(tag);
      if (!type) {
        continue;
      }
      final source = RegExp(
        r'''\bsrc\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(tag)?.group(1);
      if (source != null && !source.contains('://')) {
        return Uri.tryParse(source)?.path ?? source;
      }
    }
    return null;
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

class _GpNextDetection {
  const _GpNextDetection({
    required this.detected,
    required this.compatibilityError,
  });

  const _GpNextDetection.notDetected()
      : detected = false,
        compatibilityError = null;

  final bool detected;
  final String? compatibilityError;
}
