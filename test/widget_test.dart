import 'package:flutter_test/flutter_test.dart';
import 'package:gardendless_loader/main.dart';

void main() {
  test('app widget type is available', () {
    expect(const GardendlessLoaderApp(), isA<GardendlessLoaderApp>());
  });
}
