import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models.dart';

typedef _PackageScan = ({
  String? packageId,
  String? gameVersion,
  bool? hasGpNext,
  String? gpNextVersion,
  ResourceStats stats,
});

class ResourceValidator {
  /// Validates the resource tree at [root].
  ///
  /// With [verifyContents] every file is also opened and every indexed file
  /// hashed, which reads the whole package; imports and recovery need that.
  /// Startup and launch pass false and still re-check the layout, links,
  /// metadata and indexed file sizes, so they stay fast on large packages.
  Future<ResourceValidationResult> validate(
    Directory root, {
    bool verifyContents = true,
  }) async {
    try {
      return await _validate(root, verifyContents: verifyContents);
    } on UnsupportedError catch (error) {
      return ResourceValidationResult.invalid(
          'host_abi_unsupported', error.message?.toString() ?? '资源包需要新版宿主');
    } on FormatException catch (error) {
      return ResourceValidationResult.invalid(
          'package_metadata_invalid', error.message);
    } on FileSystemException catch (error) {
      return ResourceValidationResult.invalid(
          'resource_path_unsafe', error.message);
    }
  }

  Future<ResourceValidationResult> _validate(
    Directory root, {
    required bool verifyContents,
  }) async {
    if (!await root.exists()) {
      return ResourceValidationResult.missing('${root.path} 不存在');
    }

    await _requireSafePath(root, root.path, FileSystemEntityType.directory);

    final requiredDirectories = [
      Directory(p.join(root.path, 'assets')),
      Directory(p.join(root.path, 'cocos-js')),
      Directory(p.join(root.path, 'src')),
    ];
    for (final directory in requiredDirectories) {
      await _requireSafePath(
          root, directory.path, FileSystemEntityType.directory,
          allowMissing: true);
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

    for (final file in [
      indexFile,
      settingsFile,
      importMapFile,
      File(p.join(root.path, 'cocos-js', 'cc.js'))
    ]) {
      await _requireSafePath(root, file.path, FileSystemEntityType.file,
          allowMissing: true);
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

    final package = await _validatePackageInBackground(
      root.path,
      verifyContents: verifyContents,
    );
    if (package.hasGpNext != null && package.hasGpNext != gpNext.detected) {
      throw const FormatException('资源包 GP-Next 标记与内容不一致');
    }
    return ResourceValidationResult.valid(
      stats: package.stats,
      detectedTitle: detectedTitle,
      packageId: package.packageId,
      gameVersion: package.gameVersion ??
          _titleVersion(detectedTitle) ??
          gpNext.gameVersion,
      gpNextVersion: package.gpNextVersion,
      buildProfile: gpNext.detected
          ? ResourceBuildProfile.gpNext
          : ResourceBuildProfile.standardWeb,
      gpNextCompatibilityError: gpNext.compatibilityError,
    );
  }

  static const hostAbi = 1;
  static const _manifestPath = '__gardendless/package/resource-manifest.json';
  static const _indexPath = '__gardendless/package/file-index.json';
  static const _maxManifestBytes = 64 * 1024;
  static const _maxIndexBytes = 32 * 1024 * 1024;

  // Thousands of per-file calls run synchronously on a background isolate:
  // far cheaper than awaiting each one, and the UI stays smooth. Static, so
  // the closure sends only the path and the flag to the isolate.
  static Future<_PackageScan> _validatePackageInBackground(
    String rootPath, {
    required bool verifyContents,
  }) =>
      Isolate.run(
        () => ResourceValidator()._validatePackage(
          Directory(rootPath),
          verifyContents: verifyContents,
        ),
      );

  Future<_PackageScan> _validatePackage(
    Directory root, {
    required bool verifyContents,
  }) async {
    final marker = Directory(p.join(root.path, '__gardendless'));
    final indexed =
        await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.notFound;
    final payload = <String, ({File file, int sizeBytes})>{};
    var fileCount = 0;
    var totalBytes = 0;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      final relative =
          p.posix.joinAll(p.split(p.relative(entity.path, from: root.path)));
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.file) {
        if (indexed) throw const FormatException('资源包含链接或非普通文件');
        throw const FileSystemException('资源包含链接或非普通文件');
      }
      if (type != FileSystemEntityType.file) continue;
      if (relative.startsWith('__gardendless/package/') &&
          relative != _manifestPath &&
          relative != _indexPath) {
        throw const FormatException('资源包保留目录含额外文件');
      }
      final file = File(entity.path);
      final sizeBytes = file.lengthSync();
      fileCount++;
      totalBytes += sizeBytes;
      if (indexed) {
        payload[relative] = (file: file, sizeBytes: sizeBytes);
      } else if (verifyContents) {
        file.openSync(mode: FileMode.read).closeSync();
      }
    }
    final stats = ResourceStats(fileCount: fileCount, totalBytes: totalBytes);
    if (!indexed) {
      return (
        packageId: null,
        gameVersion: null,
        hasGpNext: null,
        gpNextVersion: null,
        stats: stats
      );
    }
    await _requireSafePath(root, marker.path, FileSystemEntityType.directory);
    final reserved = Directory(p.join(marker.path, 'package'));
    if (!await reserved.exists()) {
      throw const FormatException('资源包元数据目录缺失');
    }
    await _requireSafePath(root, reserved.path, FileSystemEntityType.directory);
    Future<List<int>> metadataBytes(String relative, int maxBytes) async {
      final entry = payload.remove(relative);
      if (entry == null) throw const FormatException('资源包元数据缺失');
      await _requireSafePath(root, entry.file.path, FileSystemEntityType.file);
      if (entry.sizeBytes > maxBytes) {
        throw const FormatException('资源包元数据过大');
      }
      final bytes = await entry.file.readAsBytes();
      if (bytes.length != entry.sizeBytes) {
        throw const FormatException('资源包元数据在校验期间发生变化');
      }
      return bytes;
    }

    final manifestBytes = await metadataBytes(_manifestPath, _maxManifestBytes);
    final indexBytes = await metadataBytes(_indexPath, _maxIndexBytes);
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    final hexDigest = RegExp(r'^[a-f0-9]{64}$');
    final version = RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$');
    const manifestFields = {
      'schemaVersion',
      'gameVersion',
      'cocosVersion',
      'hasGpNext',
      'gpNextVersion',
      'producerCommit',
      'minHostAbi',
      'fileIndexSha256'
    };
    if (manifest is! Map<String, dynamic> ||
        manifest.length != manifestFields.length ||
        !manifest.keys.toSet().containsAll(manifestFields) ||
        manifest['schemaVersion'] != 1 ||
        manifest['gameVersion'] is! String ||
        !version.hasMatch(manifest['gameVersion'] as String) ||
        manifest['cocosVersion'] is! String ||
        !version.hasMatch(manifest['cocosVersion'] as String) ||
        manifest['hasGpNext'] is! bool ||
        (manifest['gpNextVersion'] != null &&
            (manifest['gpNextVersion'] is! String ||
                !version.hasMatch(manifest['gpNextVersion'] as String))) ||
        (manifest['hasGpNext'] == false && manifest['gpNextVersion'] != null) ||
        manifest['producerCommit'] is! String ||
        !RegExp(r'^[a-f0-9]{40}$')
            .hasMatch(manifest['producerCommit'] as String) ||
        manifest['minHostAbi'] is! int ||
        (manifest['minHostAbi'] as int) < 1 ||
        manifest['fileIndexSha256'] is! String ||
        !hexDigest.hasMatch(manifest['fileIndexSha256'] as String)) {
      throw const FormatException('资源包 manifest 格式无效');
    }
    if ((manifest['minHostAbi'] as int) > hostAbi) {
      throw UnsupportedError('资源包需要宿主 ABI ${manifest['minHostAbi']}，请升级加载器');
    }
    if (sha256.convert(indexBytes).toString() != manifest['fileIndexSha256']) {
      throw const FormatException('资源包索引摘要不匹配');
    }
    final index = jsonDecode(utf8.decode(indexBytes));
    if (index is! Map<String, dynamic> ||
        index.length != 2 ||
        index['schemaVersion'] != 1 ||
        index['files'] is! List) {
      throw const FormatException('资源包索引格式无效');
    }
    String? previous;
    for (final entry in index['files'] as List) {
      if (entry is! Map<String, dynamic> ||
          entry.length != 3 ||
          entry['path'] is! String ||
          entry['sizeBytes'] is! int ||
          (entry['sizeBytes'] as int) < 0 ||
          entry['sha256'] is! String ||
          !hexDigest.hasMatch(entry['sha256'] as String)) {
        throw const FormatException('资源包索引条目无效');
      }
      final path = entry['path'] as String;
      final uri = Uri.tryParse(path);
      if (path.isEmpty ||
          path.contains('\\') ||
          path.contains('\u0000') ||
          p.posix.isAbsolute(path) ||
          p.posix.normalize(path) != path ||
          path
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          uri == null ||
          uri.hasScheme ||
          uri.hasAuthority ||
          (previous != null && previous.compareTo(path) >= 0)) {
        throw const FormatException('资源包索引路径不安全、重复或未排序');
      }
      previous = path;
      final file = payload.remove(path);
      if (file == null ||
          file.sizeBytes != entry['sizeBytes'] ||
          (verifyContents &&
              (await sha256.bind(file.file.openRead()).first).toString() !=
                  entry['sha256'])) {
        throw const FormatException('资源文件大小或摘要不匹配');
      }
    }
    if (payload.isNotEmpty) {
      throw const FormatException('资源包含未索引文件');
    }
    return (
      packageId: 'sha256:${sha256.convert(manifestBytes)}',
      gameVersion: manifest['gameVersion'] as String,
      hasGpNext: manifest['hasGpNext'] as bool,
      gpNextVersion: manifest['gpNextVersion'] as String?,
      stats: stats,
    );
  }

  Future<void> _requireSafePath(
    Directory root,
    String path,
    FileSystemEntityType expected, {
    bool allowMissing = false,
  }) async {
    final absoluteRoot = p.normalize(root.absolute.path);
    final absolutePath = p.normalize(p.absolute(path));
    if (absoluteRoot != absolutePath &&
        !p.isWithin(absoluteRoot, absolutePath)) {
      throw const FileSystemException('文件越出资源根目录');
    }
    var current = absoluteRoot;
    final components = p.equals(absoluteRoot, absolutePath)
        ? const <String>[]
        : p.split(p.relative(absolutePath, from: absoluteRoot));
    for (final component in <String>['', ...components]) {
      if (component.isNotEmpty) current = p.join(current, component);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('资源路径不能包含符号链接');
      }
    }
    final type = await FileSystemEntity.type(absolutePath, followLinks: false);
    if (type == FileSystemEntityType.notFound && allowMissing) return;
    if (type != expected) {
      throw const FileSystemException('资源类型无效');
    }
    final canonicalRoot = p.normalize(await root.resolveSymbolicLinks());
    final resolved = p.normalize(await (expected == FileSystemEntityType.file
        ? File(absolutePath).resolveSymbolicLinks()
        : Directory(absolutePath).resolveSymbolicLinks()));
    if (resolved != canonicalRoot && !p.isWithin(canonicalRoot, resolved)) {
      throw const FileSystemException('文件越出资源根目录');
    }
    if (expected == FileSystemEntityType.file) {
      final handle = await File(resolved).open(mode: FileMode.read);
      await handle.close();
    }
  }

  String? _titleVersion(String? title) => title == null
      ? null
      : RegExp(
          r'(?:^|[^0-9A-Za-z])v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?![0-9A-Za-z.-])',
          caseSensitive: false,
        ).firstMatch(title)?.group(1);

  String? _embeddedVersion(String source) => RegExp(
        r'(?:Playing version|Game Version:)\s*v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)',
        caseSensitive: false,
      ).firstMatch(source)?.group(1);

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

    await _requireSafePath(root, entryFile.path, FileSystemEntityType.file);
    final entry = await entryFile.readAsString();
    final fingerprints = StringBuffer(entry);
    for (final modulePath in _gpNextModulePaths(entry, normalizedPath)) {
      final moduleFile = File(
        p.joinAll([root.path, ...p.posix.split(modulePath)]),
      );
      if (await moduleFile.exists()) {
        await _requireSafePath(
            root, moduleFile.path, FileSystemEntityType.file);
        fingerprints
          ..writeln()
          ..write(await moduleFile.readAsString());
      }
    }

    final source = fingerprints.toString();
    final hasMarker = source.contains('GP-Next loading') &&
        source.contains('window.gpNext') &&
        source.contains('loadAllPatches');
    if (!hasMarker) {
      return _GpNextDetection.notDetected(
          gameVersion: _embeddedVersion(source));
    }

    final requiredFingerprints = {
      'patcher module': 'patcher-',
      'file loader module': 'file-loader-',
    };
    final missing = requiredFingerprints.entries
        .where((entryFingerprint) => !source.contains(entryFingerprint.value))
        .map((entryFingerprint) => entryFingerprint.key)
        .toList(growable: false);
    final compatibilityError =
        missing.isEmpty ? null : 'GP-Next 缺少兼容模块：${missing.join(', ')}';
    return _GpNextDetection(
      detected: true,
      gameVersion: _embeddedVersion(source),
      compatibilityError: compatibilityError,
    );
  }

  Iterable<String> _gpNextModulePaths(
    String entrySource,
    String entryPath,
  ) sync* {
    final matches = RegExp(
      r'''["'`]([^"'`]*gp-next-[^"'`]*\.js)["'`]''',
      caseSensitive: false,
    ).allMatches(entrySource);
    final yielded = <String>{};
    for (final match in matches) {
      final reference = match.group(1)?.replaceAll('\\', '/');
      final uri = reference == null ? null : Uri.tryParse(reference);
      if (uri == null || uri.hasScheme || uri.hasAuthority) {
        continue;
      }
      final referencePath = uri.path;
      final candidate = p.posix.normalize(
        referencePath.startsWith('/')
            ? referencePath.substring(1)
            : referencePath.startsWith('assets/')
                ? referencePath
                : p.posix.join(p.posix.dirname(entryPath), referencePath),
      );
      final basename = p.posix.basename(candidate);
      if (candidate == '.' ||
          candidate == '..' ||
          candidate.startsWith('../') ||
          p.posix.isAbsolute(candidate) ||
          !RegExp(
            r'^gp-next-[A-Za-z0-9_-]+\.js$',
            caseSensitive: false,
          ).hasMatch(basename)) {
        continue;
      }
      if (yielded.add(candidate)) {
        yield candidate;
      }
    }
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
        r'''\s(?:data-gardendless-src|src)\s*=\s*["']([^"']+)["']''',
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
    this.gameVersion,
  });

  const _GpNextDetection.notDetected({this.gameVersion})
      : detected = false,
        compatibilityError = null;

  final String? gameVersion;
  final bool detected;
  final String? compatibilityError;
}
