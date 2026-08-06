import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS native game host owns chunked save export', () {
    final controller =
        File('ios/Runner/GameHostController.swift').readAsStringSync();
    final coordinator = File(
      'ios/GardendlessKit/Sources/GardendlessBridge/ExportCoordinator.swift',
    ).readAsStringSync();
    final combined = '$controller\n$coordinator';

    expect(combined, contains('BridgeCommand.exportBegin.rawValue'));
    expect(combined, contains('BridgeCommand.exportChunk.rawValue'));
    expect(combined, contains('BridgeCommand.exportCommit.rawValue'));
    expect(combined, contains('UIDocumentPickerViewController'));
    expect(combined, contains('forExporting: [file]'));
    expect(combined, contains('asCopy: true'));
    expect(combined, contains('documentPickerWasCancelled'));
    expect(combined, contains('export_cancelled'));
    expect(combined, isNot(contains('UIActivityViewController')));
  });
}
