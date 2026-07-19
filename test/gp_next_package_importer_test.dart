import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/models.dart';
import 'package:gardendless_loader/src/services/gp_next_package_importer.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppPaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gl_gp_next_import_');
    paths = AppPaths(
      root: temp,
      manifestFile: File(p.join(temp.path, 'manifest.json')),
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'imports ZIP packs and JSON patches into persistent directories',
    () async {
      final importer = GpNextPackageImporter(
        paths: paths,
        confirmReplace: (_) async => true,
        nativeFilePicker: (staging) async {
          final json = File(p.join(staging, 'single.json'));
          final json5 = File(p.join(staging, 'single.json5'));
          final zip = File(p.join(staging, 'mod.ZIP'));
          await json.writeAsString('{"objects":[]}');
          await json5.writeAsString('{objects: [],}');
          await zip.writeAsBytes(_zipWithRootPackJson());
          return [json.path, json5.path, zip.path];
        },
      );

      final imported = await importer.pickAndImport();

      expect(imported, ['single.json', 'single.json5', 'mod.zip']);
      expect(
        await File(p.join(paths.gpNextPatchesDir.path, 'single.json')).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(paths.gpNextPatchesDir.path, 'single.json5'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(paths.gpNextPacksDir.path, 'mod.zip')).exists(),
        isTrue,
      );
    },
  );

  test('requires pack.json at the ZIP root', () async {
    final importer = GpNextPackageImporter(
      paths: paths,
      confirmReplace: (_) async => true,
      nativeFilePicker: (staging) async {
        final zip = File(p.join(staging, 'nested.zip'));
        await zip.writeAsBytes(_zipWithRootPackJson(name: 'folder/pack.json'));
        return [zip.path];
      },
    );

    await expectLater(
      importer.pickAndImport(),
      throwsA(isA<GpNextPackageImportFailure>()),
    );
  });

  test(
    'does not overwrite a duplicate when confirmation is declined',
    () async {
      await paths.gpNextPatchesDir.create(recursive: true);
      final existing = File(p.join(paths.gpNextPatchesDir.path, 'single.json'));
      await existing.writeAsString('{"old":true}');
      final importer = GpNextPackageImporter(
        paths: paths,
        confirmReplace: (name) async {
          expect(name, 'single.json');
          return false;
        },
        nativeFilePicker: (staging) async {
          final selected = File(p.join(staging, 'single.json'));
          await selected.writeAsString('{"new":true}');
          return [selected.path];
        },
      );

      final imported = await importer.pickAndImport();

      expect(imported, isEmpty);
      expect(await existing.readAsString(), '{"old":true}');
    },
  );

  test('rejects naked JavaScript files', () async {
    final importer = GpNextPackageImporter(
      paths: paths,
      confirmReplace: (_) async => true,
      nativeFilePicker: (staging) async {
        final selected = File(p.join(staging, 'unsafe.js'));
        await selected.writeAsString('export function setup() {}');
        return [selected.path];
      },
    );

    await expectLater(
      importer.pickAndImport(),
      throwsA(isA<GpNextPackageImportFailure>()),
    );
  });
}

Uint8List _zipWithRootPackJson({String name = 'pack.json'}) {
  final nameBytes = utf8.encode(name);
  final content = utf8.encode('{"name":"test"}');
  final localLength = 30 + nameBytes.length + content.length;
  final centralLength = 46 + nameBytes.length;
  final bytes = Uint8List(localLength + centralLength + 22);
  final data = ByteData.sublistView(bytes);

  data.setUint32(0, 0x04034b50, Endian.little);
  data.setUint16(4, 20, Endian.little);
  data.setUint32(18, content.length, Endian.little);
  data.setUint32(22, content.length, Endian.little);
  data.setUint16(26, nameBytes.length, Endian.little);
  bytes.setRange(30, 30 + nameBytes.length, nameBytes);
  bytes.setRange(30 + nameBytes.length, localLength, content);

  final central = localLength;
  data.setUint32(central, 0x02014b50, Endian.little);
  data.setUint16(central + 4, 20, Endian.little);
  data.setUint16(central + 6, 20, Endian.little);
  data.setUint32(central + 20, content.length, Endian.little);
  data.setUint32(central + 24, content.length, Endian.little);
  data.setUint16(central + 28, nameBytes.length, Endian.little);
  bytes.setRange(central + 46, central + centralLength, nameBytes);

  final end = central + centralLength;
  data.setUint32(end, 0x06054b50, Endian.little);
  data.setUint16(end + 8, 1, Endian.little);
  data.setUint16(end + 10, 1, Endian.little);
  data.setUint32(end + 12, centralLength, Endian.little);
  data.setUint32(end + 16, central, Endian.little);
  return bytes;
}
