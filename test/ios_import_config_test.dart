import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS registers a streaming zip importer', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate,
        contains('io.github.dey410.gardendlessloader/resource_zip_importer'));
    expect(appDelegate, contains('pickAndExtractDocsZip'));
    expect(appDelegate, contains('UIDocumentPickerViewController'));
    expect(appDelegate, contains('UTType.zip'));
    expect(appDelegate, contains('startAccessingSecurityScopedResource'));
    expect(appDelegate, contains('FileHandle(forReadingFrom:'));
    expect(appDelegate, contains('readData(ofLength:'));
    expect(appDelegate, contains('OutputStream'));
    expect(appDelegate, contains('zip_import_busy'));
    expect(appDelegate, contains('src/settings.json'));
    expect(appDelegate, contains('src/import-map.json'));
  });

  test('iOS streams ZIP import progress to Flutter', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('resourceZipImporterChannel'));
    expect(appDelegate, contains('invokeMethod("progress"'));
    expect(appDelegate, contains('phase: "receiving"'));
    expect(appDelegate, contains('phase: "extracting"'));
    expect(appDelegate, contains('"processedBytes"'));
    expect(appDelegate, contains('"totalBytes"'));
    expect(appDelegate, contains('"processedFiles"'));
    expect(appDelegate, contains('"totalFiles"'));
    expect(appDelegate, contains('onBytesWritten'));
  });

  test('iOS zip picker imports a copied file so tapping a zip completes', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final pickerFactory = RegExp(
      r'private func makeZipDocumentPicker\(\) -> UIDocumentPickerViewController \{[\s\S]*?'
      r'\n  private func finishPickedZipImport',
    ).firstMatch(appDelegate)?.group(0);

    expect(pickerFactory, isNotNull);
    expect(pickerFactory, contains('forOpeningContentTypes: [UTType.zip]'));
    expect(pickerFactory, contains('asCopy: true'));
    expect(pickerFactory, contains('in: .import'));
  });
}
