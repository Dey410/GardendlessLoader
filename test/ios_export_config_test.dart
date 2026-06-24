import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS registers a native game save exporter', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate,
        contains('io.github.dey410.gardendlessloader/game_file_exporter'));
    expect(appDelegate, contains('exportFile'));
    expect(appDelegate, contains('UIDocumentPickerViewController'));
    expect(appDelegate, contains('forExporting: [fileUrl]'));
    expect(appDelegate, contains('asCopy: true'));
    expect(appDelegate, contains('.exportToService'));
    expect(appDelegate, contains('UIDocumentPickerDelegate'));
    expect(appDelegate, contains('pendingExportResult'));
    expect(appDelegate, contains('export_in_progress'));
    expect(appDelegate, contains('popover.sourceRect'));
    expect(appDelegate, contains('documentPickerWasCancelled'));
    expect(appDelegate, contains('export_cancelled'));
    expect(appDelegate, isNot(contains('UIActivityViewController')));
    expect(appDelegate, isNot(contains('shareFile')));
  });
}
