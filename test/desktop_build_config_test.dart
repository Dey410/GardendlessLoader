import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub Actions exports desktop release artifacts', () {
    final workflow =
        File('.github/workflows/build-mobile.yml').readAsStringSync();

    expect(workflow, contains('Build macOS DMG'));
    expect(workflow, contains('flutter build macos --release'));
    expect(workflow, contains('hdiutil create'));
    expect(
      workflow,
      contains(
          'DMG_STAGING="\$RUNNER_TEMP/gardendless-loader-dmg-\${GITHUB_RUN_ID}-\${GITHUB_RUN_ATTEMPT}"'),
    );
    expect(
      workflow,
      contains(
          'ditto build/macos/Build/Products/Release/gardendless_loader.app "\$DMG_STAGING/GardendlessLoader.app"'),
    );
    expect(workflow, contains('GardendlessLoader-unsigned.dmg'));
    expect(workflow, contains('gardendless-loader-mac-dmg'));

    expect(workflow, contains('Build Windows ZIP'));
    expect(workflow, contains('flutter build windows --release'));
    expect(workflow, contains('Compress-Archive'));
    expect(workflow, contains('build/windows/x64/runner/Release'));
    expect(workflow, contains('GardendlessLoader-windows.zip'));
    expect(workflow, contains('gardendless-loader-win-exe'));

    expect(workflow, contains('Build Linux DEB'));
    expect(workflow, contains('flutter build linux --release'));
    expect(workflow, contains('dpkg-deb --build'));
    expect(workflow, contains('GardendlessLoader-linux.deb'));
    expect(workflow, contains('gardendless-loader-linux-deb'));
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
