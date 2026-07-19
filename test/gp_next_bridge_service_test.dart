import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/gp_next_bridge_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;
  late GpNextBridgeService service;
  late List<Uri> openedUrls;
  late List<String> exportedNames;
  var openPathCount = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_gp_next_bridge_');
    paths = AppPaths(
      root: temp,
      manifestFile: File(p.join(temp.path, 'manifest.json')),
    );
    openedUrls = <Uri>[];
    exportedNames = <String>[];
    openPathCount = 0;
    service = GpNextBridgeService(
      paths: paths,
      openPath: () async {
        openPathCount += 1;
        return const <String>[];
      },
      openUrl: (uri) async => openedUrls.add(uri),
      exportFile: (file, name) async => exportedNames.add(name),
    );
    await service.initialize();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('reproduces GP-Next AppData file operations', () async {
    expect(
      await service.invoke({
        'command': 'plugin:path|resolve_directory',
        'args': {'directory': 14},
      }),
      temp.path,
    );

    await service.invoke({
      'command': 'plugin:fs|mkdir',
      'args': {
        'path': r'gp-next\packs\sample',
        'options': {'baseDir': 14, 'recursive': true},
      },
    });
    await service.invoke({
      'command': 'plugin:fs|write_text_file',
      'args': {
        '__gardendlessBytes': [104, 105],
      },
      'options': {
        'headers': {
          'path': Uri.encodeComponent(r'gp-next\packs\sample\pack.json'),
          'options': '{"baseDir":14}',
        },
      },
    });

    final bytes = await service.invoke({
      'command': 'plugin:fs|read_text_file',
      'args': {
        'path': r'gp-next\packs\sample\pack.json',
        'options': {'baseDir': 14},
      },
    });
    final entries = await service.invoke({
      'command': 'plugin:fs|read_dir',
      'args': {
        'path': r'gp-next\packs\sample',
        'options': {'baseDir': 14},
      },
    }) as List;

    expect(bytes, [104, 105]);
    expect(entries, hasLength(1));
    expect(entries.single, containsPair('name', 'pack.json'));
    expect(entries.single, containsPair('isFile', true));
    expect(
      await service.invoke({
        'command': 'plugin:fs|exists',
        'args': {
          'path': r'gp-next\packs\sample\pack.json',
          'options': {'baseDir': 14},
        },
      }),
      isTrue,
    );
  });

  test('maps the desktop patch-folder action to the mobile picker', () async {
    final result = await service.invoke({
      'command': 'plugin:opener|open_path',
      'args': {'path': p.join(temp.path, 'gp-next')},
    });

    expect(result, isNull);
    expect(openPathCount, 1);
  });

  test('allows callbacks to enforce the fixed external URL policy', () async {
    await service.invoke({
      'command': 'plugin:opener|open_url',
      'args': {'url': 'https://pvzge.com/guide/mod'},
    });

    expect(openedUrls.single.host, 'pvzge.com');
  });

  test('turns a GP-Next save command into a native export', () async {
    final path = await service.invoke({
      'command': 'plugin:dialog|save',
      'args': {
        'options': {'defaultPath': 'edited.json'},
      },
    }) as String;
    await service.invoke({
      'command': 'plugin:fs|write_text_file',
      'args': {
        '__gardendlessBytes': [123, 125],
      },
      'options': {
        'headers': {'path': Uri.encodeComponent(path), 'options': 'undefined'},
      },
    });

    expect(exportedNames, ['edited.json']);
  });

  test(
    'rejects paths and Tauri directories outside the GP-Next sandbox',
    () async {
      await expectLater(
        service.invoke({
          'command': 'plugin:fs|read_file',
          'args': {
            'path': r'gp-next\..\manifest.json',
            'options': {'baseDir': 14},
          },
        }),
        throwsA(isA<GpNextBridgeFailure>()),
      );
      await expectLater(
        service.invoke({
          'command': 'plugin:path|resolve_directory',
          'args': {'directory': 21},
        }),
        throwsA(isA<GpNextBridgeFailure>()),
      );
    },
  );
}
