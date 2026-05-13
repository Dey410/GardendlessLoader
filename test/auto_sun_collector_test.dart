import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/services/auto_sun_collector.dart';

void main() {
  testWidgets('presses the collect key every 1.5 seconds while enabled',
      (tester) async {
    var pressCount = 0;
    final collector = AutoSunCollector(onPressCollectKey: () => pressCount++);
    addTearDown(collector.dispose);

    collector.setEnabled(true);

    await tester.pump(const Duration(milliseconds: 1499));
    expect(pressCount, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(pressCount, 1);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(pressCount, 2);

    collector.setEnabled(false);
    await tester.pump(const Duration(seconds: 3));
    expect(pressCount, 2);
  });
}
