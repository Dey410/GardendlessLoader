# Repository Guidelines

## Project Structure & Module Organization

- `lib/main.dart` starts the app.
- `lib/src/app_controller.dart` coordinates state, imports, server lifecycle, announcements, and update checks.
- `lib/src/services/` holds resource validation, ZIP import, manifest storage, diagnostics, and the local HTTP server.
- `lib/src/ui/` contains screens: `home_page.dart` and `game_page.dart`.
- `lib/src/web/` contains web-only support code.
- `test/` contains unit and widget tests named `*_test.dart`.
- Platform folders (`android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`, `ohos/`) hold generated and native integration files.
- `announcements.json` is the remote announcement payload; `docs/acceptance-checklist.md` records manual release checks.

## Build, Test, and Development Commands

- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter analyze` runs static analysis with the repository lint rules.
- `flutter test` runs the full test suite.
- `flutter test test/resource_validator_test.dart` runs one focused test file.
- `flutter run` starts the app on a connected device or selected desktop target.
- `flutter build apk --release` builds Android.
- `flutter build ios --release --no-codesign` builds unsigned iOS artifacts.
- `flutter build macos --release`, `flutter build windows --release`, or `flutter build linux --release` builds desktop targets.

For HarmonyOS/OpenHarmony, copy `pubspec_overrides.ohos.yaml` to `pubspec_overrides.yaml`, use the OpenHarmony Flutter SDK, and follow `README.en.md`.

## Coding Style & Naming Conventions

This project uses `package:flutter_lints/flutter.yaml` plus `prefer_single_quotes`. Use two-space Dart indentation, `UpperCamelCase` for classes/widgets, `lowerCamelCase` for methods and variables, and `snake_case.dart` filenames. Keep service logic in `lib/src/services/` and UI code in `lib/src/ui/`. Run `dart format lib test` before submitting.

## Testing Guidelines

Use `flutter_test`. Add or update tests for resource import, validation, manifest state, local server behavior, update checks, and UI workflows when touched. Keep files in `test/` with the `*_test.dart` suffix. Prefer service tests for domain logic and widget tests for visible UI behavior.

## Commit & Pull Request Guidelines

Recent history uses short prefixes such as `Fix:`, `Update:`, and `Modify:`. Follow `Type: concise imperative summary`, for example `Fix: handle nested docs imports`. PRs should describe the change, list tested commands, link issues when applicable, and include screenshots or recordings for UI changes.

## Security & Configuration Tips

Do not commit bundled game resources, signing files, generated archives, or `.DS_Store` files. Keep Android signing values in CI secrets. Preserve local-only serving and non-local WebView request blocking.
