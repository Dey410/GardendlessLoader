import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS sideloaded game host disables the WebKit 60 FPS preference', () {
    final controller =
        File('ios/Runner/GameViewController.swift').readAsStringSync();
    final highRefresh =
        File('ios/Runner/WebKitHighRefreshRate.h').readAsStringSync();
    final bridgingHeader =
        File('ios/Runner/Runner-Bridging-Header.h').readAsStringSync();
    final swiftPackage = File('ios/Package.swift').readAsStringSync();

    expect(
      bridgingHeader,
      contains('#import "WebKitHighRefreshRate.h"'),
    );
    expect(
      highRefresh,
      contains('PreferPageRenderingUpdatesNear60FPSEnabled'),
    );
    expect(highRefresh, contains('_features'));
    expect(highRefresh, contains('_setEnabled:forFeature:'));
    expect(highRefresh, contains('_isEnabledForFeature:'));
    expect(
      highRefresh,
      contains('setEnabledSelector,\n        NO,\n        feature'),
    );
    expect(
      controller.indexOf('GDLDisableWebKit60FPSPreference(configuration)'),
      lessThan(controller.indexOf('WKWebView(frame: .zero')),
    );
    expect(swiftPackage, contains('"WebKitHighRefreshRate.h"'));
  });

  test('iOS retains the system high-refresh opt-in', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('CADisableMinimumFrameDurationOnPhone'));
    expect(
      infoPlist,
      matches(
        RegExp(
          r'<key>CADisableMinimumFrameDurationOnPhone</key>\s*<true\s*/>',
        ),
      ),
    );
  });
}
