import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../constants.dart';
import '../models.dart';
import '../services/game_update_check_service.dart';
import '../services/update_check_service.dart';

enum LauncherDestination {
  game('游戏', Icons.sports_esports_outlined, Icons.sports_esports),
  resources('资源', Icons.inventory_2_outlined, Icons.inventory_2),
  logs('日志', Icons.receipt_long_outlined, Icons.receipt_long),
  settings('设置', Icons.settings_outlined, Icons.settings);

  const LauncherDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Side effects the pages can trigger. HomePage owns the implementations
/// (platform channels, clipboard, dialogs) so pages stay presentational.
class LauncherActions {
  const LauncherActions({
    required this.navigate,
    required this.startGame,
    required this.importResources,
    required this.openUrl,
    required this.openRelease,
    required this.deferUpdate,
    required this.deferGameUpdate,
    required this.copyResourceRoot,
    required this.copyDiagnostics,
    required this.copyLogEvent,
    required this.deleteLogHistory,
    required this.toggleImportDetails,
  });

  final ValueChanged<LauncherDestination> navigate;
  final Future<void> Function() startGame;
  final Future<void> Function() importResources;
  final Future<void> Function(String url) openUrl;
  final Future<void> Function(UpdateInfo update) openRelease;
  final void Function(UpdateInfo update) deferUpdate;
  final void Function(GameUpdateInfo update) deferGameUpdate;
  final Future<void> Function() copyResourceRoot;
  final Future<void> Function() copyDiagnostics;
  final Future<void> Function(Map<String, Object?> event) copyLogEvent;
  final Future<void> Function() deleteLogHistory;
  final VoidCallback toggleImportDetails;
}

const socialLinks = <AnnouncementLink>[
  AnnouncementLink(label: 'B站主页', url: bilibiliHomeUrl),
  AnnouncementLink(label: 'GitHub', url: appGithubUrl),
];

Widget linkIcon(AnnouncementLink link, {double size = 16, Color? color}) {
  final host = Uri.tryParse(link.url)?.host.toLowerCase() ?? '';
  if (link.url == bilibiliHomeUrl || host.contains('bilibili.com')) {
    return FaIcon(FontAwesomeIcons.bilibili, size: size, color: color);
  }
  if (host == 'github.com' || host.endsWith('.github.com')) {
    return FaIcon(FontAwesomeIcons.github, size: size, color: color);
  }
  return Icon(Icons.open_in_new_rounded, size: size, color: color);
}

/// Turns an HTML title such as `Cocos Creator | PvZ2_Gardendless` into the
/// name a player recognises: the `|` segment naming the game, `_` as spaces.
String displayGameTitle(String raw) {
  final segments = raw
      .split('|')
      .map((segment) => segment.replaceAll('_', ' ').trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) return raw.trim();
  return segments.firstWhere(
    (segment) => segment.toLowerCase().contains('gardendless'),
    orElse: () => segments.last,
  );
}

String importPhaseMessage(ImportPhase phase) => switch (phase) {
      ImportPhase.receiving => '正在读取 ZIP',
      ImportPhase.extracting => '正在解压资源',
      ImportPhase.validating => '正在校验资源',
      ImportPhase.scanning => '正在统计资源',
      ImportPhase.selfChecking => '正在本地自检',
      ImportPhase.completed => '导入完成',
      ImportPhase.failed => '导入失败',
      ImportPhase.idle => '等待导入',
    };

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = unitIndex == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  return '${two(minutes)}:${two(seconds)}';
}

String formatDateTime(DateTime? value) {
  if (value == null) return '--';
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
