# Repository Guidelines

## Project Structure & Module Organization

- `lib/main.dart` starts the app.
- `lib/src/app_controller.dart` coordinates state, imports, native GameHost launch, announcements, and update checks.
- `lib/src/services/` holds resource validation, ZIP import, manifest storage, diagnostics, and filesystem self-checks.
- `lib/src/game_host/` defines the durable native GameSession and platform-channel launch contract.
- `lib/src/ui/` contains the Flutter launcher screen in `home_page.dart`.
- `assets/game_bridge/` contains the shared document-start scripts injected by every native GameHost.
- `test/` contains unit and widget tests named `*_test.dart`.
- Maintained platform folders are `android/`, `ios/`, and `ohos/`.
- `announcements.json` is the remote announcement payload; `docs/acceptance-checklist.md` records manual release checks.
- `docs/research/native_gamehost_local_resource_loading.md` records the native GameHost security constraints and device-validation limits.

## Build, Test, and Development Commands

- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter analyze` runs static analysis with the repository lint rules.
- `flutter test` runs the full test suite.
- `flutter test test/resource_validator_test.dart` runs one focused test file.
- `flutter run` starts the app on a connected supported device.
- `flutter build apk --release` builds Android.
- `flutter build ios --release --no-codesign` builds unsigned iOS artifacts.

For HarmonyOS/OpenHarmony, copy `pubspec_overrides.ohos.yaml` to `pubspec_overrides.yaml`, use the OpenHarmony Flutter SDK, and follow `README.md`.

## Coding Style & Naming Conventions

This project uses `package:flutter_lints/flutter.yaml` plus `prefer_single_quotes`. Use two-space Dart indentation, `UpperCamelCase` for classes/widgets, `lowerCamelCase` for methods and variables, and `snake_case.dart` filenames. Keep service logic in `lib/src/services/` and UI code in `lib/src/ui/`. Run `dart format lib test` before submitting.

## Testing Guidelines

Use `flutter_test`. Add or update tests for resource import, validation, manifest state, native resource-handler contracts, update checks, and UI workflows when touched. Keep files in `test/` with the `*_test.dart` suffix. Prefer service tests for domain logic and widget tests for visible UI behavior.

## Commit & Pull Request Guidelines

Recent history uses short prefixes such as `Fix:`, `Update:`, and `Modify:`. Follow `Type: concise imperative summary`, for example `Fix: handle nested docs imports`. PRs should describe the change, list tested commands, link issues when applicable, and include screenshots or recordings for UI changes.

## Security & Configuration Tips

Do not commit bundled game resources, signing files, generated archives, or `.DS_Store` files. Keep Android signing values in CI secrets. Preserve active-slot path confinement and non-allowlisted WebView request blocking.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Domain docs

This repository uses a single-context domain documentation layout. See `docs/agents/domain.md`.
