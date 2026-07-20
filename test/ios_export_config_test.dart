import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS native game host owns chunked save export', () {
    final controller =
        File('ios/Runner/GameViewController.swift').readAsStringSync();

    expect(controller, contains('host:exportBegin'));
    expect(controller, contains('host:exportChunk'));
    expect(controller, contains('host:exportCommit'));
    expect(controller, contains('UIDocumentPickerViewController'));
    expect(controller, contains('forExporting: [export.file]'));
    expect(controller, contains('asCopy: true'));
    expect(controller, contains('documentPickerWasCancelled'));
    expect(controller, contains('export_cancelled'));
    expect(controller, isNot(contains('UIActivityViewController')));
  });
}
