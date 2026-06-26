import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:gardendless_loader/src/app_controller.dart';
import 'package:gardendless_loader/src/ui/game_page.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

void main() {
  testWidgets(
    'game page keeps immersive system UI while active and after exit',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final previousWebViewPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
      if (previousWebViewPlatform != null) {
        addTearDown(() {
          InAppWebViewPlatform.instance = previousWebViewPlatform;
        });
      }

      final previousWakelockPlatform = WakelockPlusPlatformInterface.instance;
      WakelockPlusPlatformInterface.instance = _FakeWakelockPlusPlatform();
      addTearDown(() {
        WakelockPlusPlatformInterface.instance = previousWakelockPlatform;
      });

      final platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(home: GamePage(controller: AppController())),
      );
      await tester.pump();

      final hideCalls = platformCalls
          .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
          .toList();

      expect(hideCalls, isNotEmpty);
      expect(hideCalls.last.arguments, 'SystemUiMode.immersiveSticky');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      final allHideCalls = platformCalls
          .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
          .toList();
      final overlayCalls = platformCalls
          .where((call) =>
              call.method == 'SystemChrome.setEnabledSystemUIOverlays')
          .toList();

      expect(allHideCalls.length, greaterThanOrEqualTo(2));
      expect(allHideCalls.last.arguments, 'SystemUiMode.immersiveSticky');
      expect(overlayCalls, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}

class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _FakeInAppWebViewWidget(params);
  }
}

class _FakeInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakeInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    return params.controllerFromPlatform!(controller) as T;
  }

  @override
  void dispose() {}
}

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<bool> get enabled async => false;

  @override
  Future<void> toggle({required bool enable}) async {}
}
