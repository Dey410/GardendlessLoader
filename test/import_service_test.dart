import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/import_service.dart';
import 'package:gardendless_loader/src/services/local_game_server.dart';
import 'package:gardendless_loader/src/services/manifest_store.dart';
import 'package:gardendless_loader/src/services/resource_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late LocalGameServer server;
  late ImportService importService;
  late ManifestStore manifestStore;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_import_');
    paths = AppPaths(
      root: temp,
      manifestFile: File(p.join(temp.path, 'manifest.json')),
      importDir: Directory(p.join(temp.path, 'import')),
      importDocsDir: Directory(p.join(temp.path, 'import', 'docs')),
      currentDir: Directory(p.join(temp.path, 'current')),
      previousDir: Directory(p.join(temp.path, 'previous')),
      stagingDir: Directory(p.join(temp.path, 'staging')),
    );
    for (final directory in [
      paths.importDir,
      paths.currentDir,
      paths.previousDir,
      paths.stagingDir,
    ]) {
      await directory.create(recursive: true);
    }
    server = LocalGameServer();
    importService = ImportService(validator: ResourceValidator(), server: server);
    manifestStore = ManifestStore(paths.manifestFile);
  });

  tearDown(() async {
    await server.stop();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('imports valid docs into current and writes ready manifest', () async {
    await _writeValidResource(paths.importDocsDir);

    final manifest = await importService.importResources(
      paths: paths,
      manifestStore: manifestStore,
    );

    expect(await File(p.join(paths.currentDir.path, 'index.html')).exists(), isTrue);
    expect(await File(p.join(paths.importDocsDir.path, 'index.html')).exists(), isTrue);
    expect(manifest.resourceStatus, ResourceStatus.ready);
    expect(manifest.transactionState, TransactionState.idle);
    expect(manifest.fileCount, greaterThan(0));
  });

  test('rolls back to previous current when selfCheck fails', () async {
    await _writeValidResource(paths.currentDir, title: 'PvZ2 Gardendless Previous');
    await _writeValidResource(paths.importDocsDir, includeCcJs: false);

    await expectLater(
      importService.importResources(paths: paths, manifestStore: manifestStore),
      throwsA(isA<ImportFailure>()),
    );

    final index = await File(p.join(paths.currentDir.path, 'index.html')).readAsString();
    expect(index, contains('PvZ2 Gardendless Previous'));
  });

  test('recovers switching transaction by promoting valid previous if current is bad', () async {
    await _writeValidResource(paths.previousDir, title: 'PvZ2 Gardendless Previous');
    await File(p.join(paths.currentDir.path, 'broken.txt')).writeAsString('bad');
    await manifestStore.write(
      ResourceManifest.initial().copyWith(transactionState: TransactionState.switching),
    );

    final manifest = await importService.recoverStartupTransaction(
      paths: paths,
      manifestStore: manifestStore,
    );

    final index = await File(p.join(paths.currentDir.path, 'index.html')).readAsString();
    expect(index, contains('PvZ2 Gardendless Previous'));
    expect(manifest.transactionState, TransactionState.idle);
    expect(manifest.resourceStatus, ResourceStatus.ready);
  });
}

Future<void> _writeValidResource(
  Directory root, {
  String title = 'PvZ2 Gardendless',
  bool includeCcJs = true,
}) async {
  await Directory(p.join(root.path, 'assets')).create(recursive: true);
  await Directory(p.join(root.path, 'cocos-js')).create(recursive: true);
  await Directory(p.join(root.path, 'src')).create(recursive: true);
  await File(p.join(root.path, 'index.html')).writeAsString(
    '<html><head><title>$title</title></head><body>play.pvzge.com</body></html>',
  );
  await File(p.join(root.path, 'src', 'settings.json')).writeAsString('{"platform":"web-mobile"}');
  await File(p.join(root.path, 'src', 'import-map.json')).writeAsString('{}');
  if (includeCcJs) {
    await File(p.join(root.path, 'cocos-js', 'cc.js')).writeAsString('console.log("cc");');
  }
}
