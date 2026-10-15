import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS locks iPhone and iPad to landscape', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('UIInterfaceOrientationPortrait')));
    expect(plist, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(plist, contains('UIInterfaceOrientationLandscapeRight'));
    // iPadOS ignores the orientation lock unless the app opts out of
    // multitasking.
    expect(
      RegExp(r'<key>UIRequiresFullScreen</key>\s*<true/>').hasMatch(plist),
      isTrue,
    );
  });

  test('Android launcher and game activities are landscape only', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      'android:screenOrientation="sensorLandscape"'.allMatches(manifest).length,
      2,
    );
  });

  test('HarmonyOS entry ability is landscape only', () {
    final module = File('ohos/entry/src/main/module.json5').readAsStringSync();
    expect(module, contains('"orientation": "landscape"'));
  });

  test('iOS tells Flutter which long edge holds the sensor housing', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('io.github.dey410.gardendlessloader/display'));
    expect(delegate, contains('"sensorHousingEdge"'));
    expect(delegate, contains('"sensorHousingEdgeChanged"'));
    expect(delegate, contains('UIDevice.orientationDidChangeNotification'));
  });
}
