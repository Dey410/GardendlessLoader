import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository exposes only maintained platform projects', () {
    for (final platform in const <String>['android', 'ios', 'ohos']) {
      expect(
        Directory(platform).existsSync(),
        isTrue,
        reason: '$platform is a maintained platform project',
      );
    }

    for (final platform in const <String>['linux', 'macos', 'web', 'windows']) {
      expect(
        Directory(platform).existsSync(),
        isFalse,
        reason: '$platform is not a maintained platform project',
      );
    }
  });

  test('Android has one Gradle DSL and one application namespace', () {
    for (final buildFile in const <String>[
      'android/settings.gradle',
      'android/build.gradle',
      'android/app/build.gradle',
    ]) {
      expect(File(buildFile).existsSync(), isTrue);
    }

    for (final retiredFile in const <String>[
      'android/settings.gradle.kts',
      'android/build.gradle.kts',
      'android/app/build.gradle.kts',
      'android/app/src/main/kotlin/io/github/dey410/'
          'gardendless_loader/MainActivity.kt',
    ]) {
      expect(File(retiredFile).existsSync(), isFalse);
    }
  });

  test('iOS exposes only the active native package and host sources', () {
    expect(File('ios/GardendlessKit/Package.swift').existsSync(), isTrue);

    for (final retiredFile in const <String>[
      'ios/Package.swift',
      'ios/Sources/GardendlessLegacy/Placeholder.swift',
      'ios/Runner/SceneDelegate.swift',
      'ios/RunnerTests/RunnerTests.swift',
      'tool/update_ios_project.rb',
    ]) {
      expect(File(retiredFile).existsSync(), isFalse);
    }
  });
}
