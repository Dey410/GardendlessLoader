import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/import_service.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('accepts complete indexed payload and derives the raw manifest identity',
      () async {
    final root = await _package();
    final bytes = await File(p.join(root.path, _manifestPath)).readAsBytes();

    final result = await ResourceValidator().validate(root);

    expect(result.isValid, isTrue);
    expect(result.gameVersion, '0.15.0');
    expect(result.packageId, 'sha256:${sha256.convert(bytes)}');
  });

  for (final indexed in [false, true]) {
    test(
        'returns file counts and bytes from one readiness walk, indexed=$indexed',
        () async {
      final root = await _package(indexed: indexed);
      final counted = _CountingDirectory(root);
      final result = await ResourceValidator().validate(counted);
      final payloadBytes = _payload.values
          .fold<int>(0, (bytes, text) => bytes + utf8.encode(text).length);
      var metadataBytes = 0;
      if (indexed) {
        for (final path in [_manifestPath, _indexPath]) {
          metadataBytes +=
              (await File(p.join(root.path, path)).readAsBytes()).length;
        }
      }
      expect(result.isValid, isTrue);
      expect(counted.recursiveLists, 1);
      expect(result.stats.fileCount, _payload.length + (indexed ? 2 : 0));
      expect(result.stats.totalBytes, payloadBytes + metadataBytes);
      expect(identical(result.stats, result.asReady().stats), isTrue);
    });
  }

  for (final failCleanup in [false, true]) {
    test(
        'commits one inspected package with retained old slot, cleanupFailure=$failCleanup',
        () async {
      final appRoot =
          await Directory.systemTemp.createTemp('gl_import_retained_');
      final paths = AppPaths(
          root: appRoot,
          manifestFile: File(p.join(appRoot.path, 'manifest.json')));
      await paths.slotADir.create();
      final candidate = await _package(rootOverride: paths.slotBDir);
      final countedCandidate = _CountingDirectory(candidate);
      final store = ManifestStore(paths.manifestFile);
      await store.write(ResourceManifest.initial().copyWith(
        generation: 1,
        activeSlot: ResourceSlot.slotA,
        transactionSlot: ResourceSlot.slotB,
        transactionState: TransactionState.extracting,
        resourceStatus: ResourceStatus.ready,
        autoCollectSunEnabled: true,
      ));
      final validator = _CountingValidator();
      final service = ImportService(
        validator: validator,
        oldSlotCleaner: (_) async {
          if (failCleanup) throw const FileSystemException('retain fixture');
          // The old fixture is retained; no filesystem deletion is authorized.
        },
      );

      final manifest = await service.completeImport(
        paths: paths,
        manifestStore: store,
        target:
            ImportTarget(slot: ResourceSlot.slotB, directory: countedCandidate),
      );

      expect(validator.inspections, 1);
      expect(countedCandidate.recursiveLists, 1);
      expect(manifest.activeSlot, ResourceSlot.slotB);
      expect(manifest.autoCollectSunEnabled, isFalse);
      expect(manifest.gameVersion, '0.15.0');
      expect(
          manifest.transactionState,
          failCleanup
              ? TransactionState.cleaningOldSlot
              : TransactionState.idle);
      expect(manifest.lastErrorCode,
          failCleanup ? 'old_slot_cleanup_failed' : isNull);
      final record = jsonDecode(
          await File(p.join(appRoot.path, 'slot-b.metadata.json'))
              .readAsString()) as Map;
      expect(record['packageId'], manifest.packageId);
      expect(await File(p.join(candidate.path, '.slot-metadata.json')).exists(),
          isFalse);
      final postActivation = await ResourceValidator().validate(candidate);
      expect(postActivation.isValid, isTrue);
      expect(manifest.fileCount, postActivation.stats.fileCount);
      expect(manifest.totalBytes, postActivation.stats.totalBytes);
      expect((await store.read()).packageId, manifest.packageId);
    });
  }

  for (final change in [
    'hidden',
    'digest',
    'size',
    'indexHash',
    'futureAbi',
    'missingIndex',
    'missingManifest',
    'missingMetadataDirectory',
    'unsafePath',
    'duplicate',
    'unsorted'
  ]) {
    test('rejects indexed package corruption: $change', () async {
      final root = await _package(change: change);

      final result = await ResourceValidator().validate(root);

      expect(result.isValid, isFalse);
      expect(
          result.errorCode,
          change == 'futureAbi'
              ? 'host_abi_unsupported'
              : 'package_metadata_invalid');
    });
  }
}

const _manifestPath = '__gardendless/package/resource-manifest.json';
const _indexPath = '__gardendless/package/file-index.json';

const _payload = <String, String>{
  'index.html': '<title>PvZ2 Gardendless</title>pvzge',
  'src/settings.json': '{"platform":"web-mobile"}',
  'src/import-map.json': '{}',
  'cocos-js/cc.js': 'window.cc = {};',
  'assets/game.js': 'game',
};

// Every fixture is retained; none of these tests execute file deletion.
Future<Directory> _package(
    {String? change, Directory? rootOverride, bool indexed = true}) async {
  final root =
      rootOverride ?? await Directory.systemTemp.createTemp('gl_package_');
  await root.create(recursive: true);
  final entries = <Map<String, Object>>[];
  for (final entry in _payload.entries) {
    final file = File(p.join(root.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
    final bytes = utf8.encode(entry.value);
    entries.add({
      'path': entry.key,
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString()
    });
  }
  if (!indexed) return root;
  entries.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  if (change == 'size') entries.first['sizeBytes'] = 100;
  if (change == 'digest') entries.first['sha256'] = '0' * 64;
  if (change == 'unsafePath') entries.first['path'] = '../escape.js';
  if (change == 'duplicate') entries.add(entries.last);
  if (change == 'unsorted') entries.insert(0, entries.removeLast());
  final indexBytes =
      utf8.encode(jsonEncode({'schemaVersion': 1, 'files': entries}));
  final manifest = <String, Object?>{
    'schemaVersion': 1,
    'gameVersion': '0.15.0',
    'cocosVersion': '3.8.4',
    'hasGpNext': false,
    'gpNextVersion': null,
    'producerCommit': 'a' * 40,
    'minHostAbi': change == 'futureAbi' ? 2 : 1,
    'fileIndexSha256': change == 'indexHash'
        ? '0' * 64
        : sha256.convert(indexBytes).toString(),
  };
  await Directory(p.join(root.path, '__gardendless')).create();
  if (change == 'missingMetadataDirectory') return root;
  await Directory(p.join(root.path, '__gardendless/package'))
      .create(recursive: true);
  if (change != 'missingIndex') {
    await File(p.join(root.path, _indexPath)).writeAsBytes(indexBytes);
  }
  if (change != 'missingManifest') {
    await File(p.join(root.path, _manifestPath))
        .writeAsString(jsonEncode(manifest));
  }
  if (change == 'hidden') {
    await File(p.join(root.path, 'assets/hidden.js')).writeAsString('hidden');
  }
  return root;
}

class _CountingValidator extends ResourceValidator {
  int inspections = 0;

  @override
  Future<ResourceValidationResult> validate(Directory root) {
    inspections++;
    return super.validate(root);
  }
}

class _CountingDirectory implements Directory {
  _CountingDirectory(this.delegate);
  final Directory delegate;
  int recursiveLists = 0;
  @override
  String get path => delegate.path;
  @override
  Directory get absolute => delegate.absolute;
  @override
  Directory get parent => delegate.parent;
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<String> resolveSymbolicLinks() => delegate.resolveSymbolicLinks();
  @override
  Stream<FileSystemEntity> list(
      {bool recursive = false, bool followLinks = true}) {
    if (recursive) recursiveLists++;
    return delegate.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
