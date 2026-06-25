import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Actions does not export unmaintained desktop artifacts', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, isNot(contains('Build macOS DMG')));
    expect(workflow, isNot(contains('flutter build macos --release')));
    expect(workflow, isNot(contains('hdiutil create')));
    expect(workflow, isNot(contains('GardendlessLoader-unsigned.dmg')));

    expect(workflow, isNot(contains('Build Windows ZIP')));
    expect(workflow, isNot(contains('flutter build windows --release')));
    expect(workflow, isNot(contains('Compress-Archive')));
    expect(workflow, isNot(contains('build/windows/x64/runner/Release')));
    expect(workflow, isNot(contains('GardendlessLoader-windows.zip')));

    expect(workflow, isNot(contains('Build Linux DEB')));
    expect(workflow, isNot(contains('flutter build linux --release')));
    expect(workflow, isNot(contains('dpkg-deb --build')));
    expect(workflow, isNot(contains('GardendlessLoader-linux.deb')));
  });

  test('GitHub Actions exports a web release artifact', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, contains('Build Web Bundle'));
    expect(workflow, contains('flutter build web --release'));
    expect(workflow, contains('gardendless-loader-web'));
    expect(workflow, contains('path: build/web'));
  });
}
