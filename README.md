# GardendlessLoader

`GardendlessLoader` is a Flutter Android/iOS/HarmonyOS local loader for user-supplied `PvZ2 Gardendless` web resources.

The app does not bundle, download, update, delete, back up, or restore game resources. Users manually copy the extracted `docs` directory into:

```text
GardendlessLoader/import/docs/index.html
```

The app serves the imported `current` resource directory from:

```text
http://127.0.0.1:26410
```

## Development

This repository expects Flutter 3.24+ / Dart 3.5+.

```powershell
flutter pub get
flutter test
flutter run
```

## HarmonyOS / OpenHarmony HAP

HAP builds require the OpenHarmony-compatible Flutter SDK plus DevEco Studio or command-line tools with `ohpm`, `hvigor`, `node`, and JDK 17 configured. The stock Flutter stable SDK does not expose `flutter build hap`.

After configuring that toolchain:

```powershell
Copy-Item pubspec_overrides.ohos.yaml pubspec_overrides.yaml
flutter doctor -v
flutter pub get
flutter test
flutter build hap --release --target-platform ohos-arm64
```

`pubspec_overrides.ohos.yaml` switches the HAP build to the OpenHarmony-compatible plugin forks while leaving the normal Android/iOS development dependencies on pub.dev.

The expected HAP artifact is:

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

GitHub Actions builds the same artifact when the `OHOS_COMMANDLINE_TOOLS_URL` secret points to a DevEco/OpenHarmony command-line tools archive. If that secret is missing, the HarmonyOS job emits a notice and skips the HAP steps so the Android/iOS artifacts can still build.
