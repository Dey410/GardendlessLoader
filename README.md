# GardendlessLoader

`GardendlessLoader` is a Flutter Android/iOS local loader for user-supplied `PvZ2 Gardendless` web resources.

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
