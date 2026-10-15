import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/src/ui/launcher_actions.dart';

void main() {
  test('displayGameTitle keeps the segment that names the game', () {
    expect(displayGameTitle('Cocos Creator | PvZ2_Gardendless'),
        'PvZ2 Gardendless');
    expect(displayGameTitle('PvZ2 Gardendless Online | 0.10.0'),
        'PvZ2 Gardendless Online');
    expect(displayGameTitle('PvZ2 Gardendless'), 'PvZ2 Gardendless');
    expect(displayGameTitle('Some Game | Build'), 'Build');
    expect(displayGameTitle('  '), '');
  });
}
