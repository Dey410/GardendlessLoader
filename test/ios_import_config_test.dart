import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS registers a streaming zip importer', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final importer = File(
      'ios/GardendlessKit/Sources/GardendlessImport/ZipImportSession.swift',
    ).readAsStringSync();
    final finder = File(
      'ios/GardendlessKit/Sources/GardendlessImport/DocsDirectoryFinder.swift',
    ).readAsStringSync();
    final importSources = '$importer\n$finder';

    expect(
      appDelegate,
      contains('io.github.dey410.gardendlessloader/resource_zip_importer'),
    );
    expect(appDelegate, contains('pickAndExtractDocsZip'));
    expect(appDelegate, contains('UIDocumentPickerViewController'));
    expect(appDelegate, contains('UTType.zip'));
    expect(appDelegate, contains('startAccessingSecurityScopedResource'));
    expect(appDelegate, contains('ZipImportSession('));
    expect(appDelegate, contains('zip_import_busy'));
    expect(importSources, contains('DocsDirectoryFinder.find'));
    expect(importSources, contains('src/settings.json'));
    expect(importSources, contains('src/import-map.json'));
  });

  test('iOS streams ZIP import progress to Flutter', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final importer = File(
      'ios/GardendlessKit/Sources/GardendlessImport/ZipImportSession.swift',
    ).readAsStringSync();

    expect(appDelegate, contains('resourceZipImporterChannel'));
    expect(appDelegate, contains('invokeMethod('));
    expect(appDelegate, contains('"progress"'));
    expect(appDelegate, contains('"processedBytes"'));
    expect(appDelegate, contains('"totalBytes"'));
    expect(appDelegate, contains('"processedFiles"'));
    expect(appDelegate, contains('"totalFiles"'));
    expect(importer, contains('"receiving"'));
    expect(importer, contains('"extracting"'));
  });

  test('iOS zip picker imports a copied file so tapping a zip completes', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final pickerFactory = RegExp(
      r'UIDocumentPickerViewController\(\s*forOpeningContentTypes: \[UTType\.zip\],\s*asCopy: true\s*\)',
    ).firstMatch(appDelegate);

    expect(pickerFactory, isNotNull);
  });
}
