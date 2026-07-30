import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('does not persist legacy announcement dismissal fields', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    final manifestFile = File(p.join(temp.path, 'manifest.json'));
    final store = ManifestStore(manifestFile);

    await manifestFile.writeAsString('''
{
  "schemaVersion": 1,
  "announcement": {
    "dismissedId": "notice-1",
    "dismissedLocalDate": "2026-05-17"
  }
}
''');

    final manifest = await store.read();
    await store.write(manifest);

    expect(await manifestFile.readAsString(), isNot(contains('announcement')));
    expect(await manifestFile.readAsString(), isNot(contains('dismissedId')));
  });

  test('persists the imported game version', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ManifestStore(File(p.join(temp.path, 'manifest.json')));

    await store.write(
      ResourceManifest.initial().copyWith(gameVersion: '0.12.0-next'),
    );

    final restored = await store.read();
    expect(restored.gameVersion, '0.12.0-next');
  });

  test('persists automatic sun collection for the active resource', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ManifestStore(File(p.join(temp.path, 'manifest.json')));

    await store.write(
      ResourceManifest.initial().copyWith(autoCollectSunEnabled: true),
    );

    final restored = await store.read();
    expect(restored.autoCollectSunEnabled, isTrue);
  });

  test('persists GP-Next compatibility metadata', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ManifestStore(File(p.join(temp.path, 'manifest.json')));

    await store.write(
      ResourceManifest.initial().copyWith(
        buildProfile: ResourceBuildProfile.gpNext,
        gpNextVersion: '1.4.2',
      ),
    );

    final restored = await store.read();
    expect(restored.buildProfile, ResourceBuildProfile.gpNext);
    expect(restored.gpNextVersion, '1.4.2');
    expect(restored.gpNextCompatible, isTrue);
  });

  test('old manifests default to a standard Web build', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    addTearDown(() => temp.delete(recursive: true));
    final manifestFile = File(p.join(temp.path, 'manifest.json'));
    await manifestFile.writeAsString('{"schemaVersion":3}');

    final restored = await ManifestStore(manifestFile).read();

    expect(restored.buildProfile, ResourceBuildProfile.standardWeb);
    expect(restored.hasGpNext, isFalse);
  });

  test('can clear stale GP-Next metadata when activating a standard build', () {
    final gpNext = ResourceManifest.initial().copyWith(
      buildProfile: ResourceBuildProfile.gpNext,
      gpNextVersion: '1.4.2',
      gpNextCompatibilityError: 'old error',
    );

    final standard = gpNext.copyWith(
      buildProfile: ResourceBuildProfile.standardWeb,
      clearGpNextVersion: true,
      clearGpNextCompatibilityError: true,
    );

    expect(standard.buildProfile, ResourceBuildProfile.standardWeb);
    expect(standard.gpNextVersion, isNull);
    expect(standard.gpNextCompatibilityError, isNull);
  });

  test('persists active slot and resumable import transaction', () async {
    final temp = await Directory.systemTemp.createTemp('gl_manifest_');
    addTearDown(() => temp.delete(recursive: true));
    final store = ManifestStore(File(p.join(temp.path, 'manifest.json')));

    await store.write(
      ResourceManifest.initial().copyWith(
        generation: 7,
        activeSlot: ResourceSlot.slotA,
        transactionSlot: ResourceSlot.slotB,
        transactionState: TransactionState.readyToActivate,
      ),
    );

    final restored = await store.read();
    expect(restored.generation, 7);
    expect(restored.activeSlot, ResourceSlot.slotA);
    expect(restored.transactionSlot, ResourceSlot.slotB);
    expect(restored.transactionState, TransactionState.readyToActivate);
  });

  test(
    'recovers the newest complete manifest after an interrupted commit',
    () async {
      final temp = await Directory.systemTemp.createTemp('gl_manifest_');
      addTearDown(() => temp.delete(recursive: true));
      final manifestFile = File(p.join(temp.path, 'manifest.json'));
      final store = ManifestStore(manifestFile);

      await store.write(ResourceManifest.initial().copyWith(generation: 1));
      await File('${manifestFile.path}.tmp').writeAsString(
        '${jsonEncode(ResourceManifest.initial().copyWith(generation: 2, activeSlot: ResourceSlot.slotB).toJson())}\n',
        flush: true,
      );

      final restored = await store.read();
      expect(restored.generation, 2);
      expect(restored.activeSlot, ResourceSlot.slotB);
      expect(await File('${manifestFile.path}.tmp').exists(), isFalse);
      expect(jsonDecode(await manifestFile.readAsString())['generation'], 2);
    },
  );

  test(
    'ignores a corrupt temporary manifest and keeps the complete main file',
    () async {
      final temp = await Directory.systemTemp.createTemp('gl_manifest_');
      addTearDown(() => temp.delete(recursive: true));
      final manifestFile = File(p.join(temp.path, 'manifest.json'));
      final store = ManifestStore(manifestFile);
      await store.write(
        ResourceManifest.initial().copyWith(
          generation: 4,
          activeSlot: ResourceSlot.slotA,
        ),
      );
      await File(
        '${manifestFile.path}.tmp',
      ).writeAsString('{broken', flush: true);

      final restored = await store.read();

      expect(restored.generation, 4);
      expect(restored.activeSlot, ResourceSlot.slotA);
      expect(await File('${manifestFile.path}.tmp').exists(), isFalse);
    },
  );
}
