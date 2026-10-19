import 'dart:io';

import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

enum LauncherShortcut {
  startGame,
  importResources;

  static LauncherShortcut? fromName(Object? value) {
    for (final shortcut in values) {
      if (shortcut.name == value) return shortcut;
    }
    return null;
  }
}

/// Home-screen shortcuts that open the launcher at a task.
class ShortcutService {
  ShortcutService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'perform') return;
      final shortcut = LauncherShortcut.fromName(call.arguments);
      if (shortcut != null) onShortcut?.call(shortcut);
    });
  }

  static const MethodChannel _channel = MethodChannel(
    'io.github.dey410.gardendlessloader/shortcuts',
  );

  /// Called when a shortcut is used while the launcher is running.
  void Function(LauncherShortcut shortcut)? onShortcut;

  /// The shortcut that started the launcher, if any; it is reported once.
  Future<LauncherShortcut?> take() async =>
      LauncherShortcut.fromName(await _channel.invokeMethod<String>('take'));

  /// Titles the shortcuts in the launcher language. HarmonyOS has no dynamic
  /// shortcuts for apps; its shortcuts_config.json follows the system
  /// language instead.
  Future<void> publish(AppStrings strings) async {
    if (Platform.operatingSystem == 'ohos') return;
    await _channel.invokeMethod<void>('setItems', <String, String>{
      LauncherShortcut.startGame.name: strings.startGame,
      LauncherShortcut.importResources.name: strings.importResources,
    });
  }
}
