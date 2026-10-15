# Verdant Observatory / 深夜温室

Original Flutter UI for GardendlessLoader. This is an active native implementation, not a web page embedded in the launcher.

## Visual system
Ink-green foundations, acid-lime primary actions, warm ivory typography and restrained coral alerts. Oversized editorial type is balanced by an original procedural botanical sculpture. Artwork is drawn with CustomPainter and isolated in a RepaintBoundary. The one-shot entrance respects system reduced-motion settings and stops repainting at rest. No additional dependencies, game assets, downloaded artwork or font binaries are included.

## Information architecture
- Garden: start/import as the primary action, truthful resource summary, announcement reader.
- Resources: native ZIP picker, validation, resource manifest, directory copying and GP Next compatibility.
- Journal: real structured events, severity and keyword filters, complete diagnostic copying, confirmed history deletion. Rendering is limited to the latest 200 matching events; diagnostic exports remain complete.
- Preferences: persisted sun collection, watermark and audio diagnostics, session-only scene motion, about, community links and independent loader/game update controls.

Narrow views use a bottom navigation bar; landscape/tablet uses a rail. The existing landscape orientation preference in main.dart is unchanged. Content scrolls in short windows instead of shrinking into unreadable controls. Large text switches the hero and summary cards to stacked layouts. Import progress is available on every page, keeps indeterminate states truthful, shows failure/retry and only permits dismissal after completion/failure.

## Integration boundaries
`lib/main.dart` selects `ui/verdant/verdant_home_page.dart`. AppController, native GameHost, active-slot handling, path confinement, remote-host restrictions and game scripts are unchanged. The former home_page.dart stays as unreferenced legacy presentation code so its existing historical widget tests can remain intact; it is not a user-facing alternate mode.

All production statistics originate in AppController. Screenshot values and announcements are isolated to `test/verdant_fixtures.dart` and are not user data. Settings changes use existing controller methods; no new storage format is introduced. Native launch/import actions are guarded against duplicate taps and report failures. External links require HTTPS and use the existing platform channel. History deletion requires confirmation.

## Verification
```
flutter pub get
flutter analyze --no-fatal-infos lib/src/ui/verdant test/verdant_fixtures.dart test/verdant_home_page_test.dart tool/capture_verdant.dart
flutter test test/verdant_home_page_test.dart
flutter test
```
`Verdant UI validation` additionally loads fonts from its Linux runner and captures real Flutter PNGs with explicit test data. No font files are uploaded. The screenshot job saves a formatter patch alongside PNGs. Native ZIP picking, Android/iOS/OHOS host launch, performance and filesystem behavior still require device testing; widget captures do not substitute for that.
