import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../models.dart';
import '../../services/app_settings_store.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TwoColumn(
      gap: compact ? 16 : 24,
      left: [
        _LoaderPanel(controller: controller, actions: actions),
        const SizedBox(height: 16),
        _LaunchPreferences(controller: controller),
        const SizedBox(height: 16),
        _AppearancePanel(controller: controller),
      ],
      right: [
        _AboutPanel(controller: controller, actions: actions),
        const SizedBox(height: 16),
        const _GuidePanel(),
      ],
    );
  }
}

class _LoaderPanel extends StatelessWidget {
  const _LoaderPanel({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final update = controller.availableUpdate;
    final (String status, Color? statusColor) = update != null
        ? ('有新版本', palette.accent)
        : controller.updateCheckInProgress
            ? ('检查中', null)
            : ('无可用更新', null);
    return SurfaceCard(
      key: update == null ? null : const ValueKey('app-update-entry'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: appDisplayName,
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(label: '当前版本', value: 'v${controller.currentAppVersion}'),
              Metric(
                label: '最新版本',
                value: controller.latestAppVersion == null
                    ? '--'
                    : 'v${controller.latestAppVersion}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (update == null)
            Text(
              '进入启动器时会自动检查，也可以点右上角的刷新图标手动检查。',
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            )
          else ...[
            Text(
              '${update.currentVersion} → ${update.latestVersion}',
              style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
            ),
            if (update.releaseName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                update.releaseName,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                update.releaseNotes,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GardenButton(
                  label: '网盘更新',
                  icon: Icons.download_rounded,
                  tone: GardenButtonTone.primary,
                  compact: true,
                  onPressed: () => actions.openUrl(appCloudDriveUpdateUrl),
                ),
                GardenButton(
                  label: '查看 GitHub Release',
                  compact: true,
                  onPressed: () => actions.openRelease(update),
                ),
                GardenButton(
                  label: '稍后提醒',
                  tone: GardenButtonTone.ghost,
                  compact: true,
                  onPressed: () => actions.deferUpdate(update),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LaunchPreferences extends StatelessWidget {
  const _LaunchPreferences({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return SurfaceCard(
      key: const ValueKey('launch-preferences'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: '启动偏好',
            trailing: Text(
              '下次启动生效',
              style: TextStyle(color: palette.inkFaint, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          SwitchRow(
            key: const ValueKey('home-quick-launch'),
            switchKey: const ValueKey('home-quick-launch-switch'),
            title: '快速启动',
            subtitle: '打开应用时直接进入游戏，点击游戏左下角 X 返回加载器',
            value: controller.quickLaunchEnabled,
            onChanged: controller.initialized
                ? controller.setQuickLaunchEnabled
                : null,
          ),
          Divider(color: palette.border),
          SwitchRow(
            key: const ValueKey('home-auto-collect-sun'),
            switchKey: const ValueKey('home-auto-collect-sun-switch'),
            title: '自动收集',
            subtitle: '游戏中约每 3 秒模拟一次 A 键，暂停、后台或输入时不触发',
            value: controller.autoCollectSunEnabled,
            onChanged: controller.hasCurrentResource
                ? controller.setAutoCollectSunEnabled
                : null,
          ),
          Divider(color: palette.border),
          SwitchRow(
            key: const ValueKey('home-watermark'),
            switchKey: const ValueKey('home-watermark-switch'),
            title: '游戏水印',
            subtitle: '在游戏画面角落显示加载器标识',
            value: controller.watermarkEnabled,
            onChanged:
                controller.initialized ? controller.setWatermarkEnabled : null,
          ),
        ],
      ),
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader(
            title: '外观',
          ),
          const SizedBox(height: 14),
          Text(
            '主题',
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          GardenSegmented<ThemePreference>(
            values: ThemePreference.values,
            selected: controller.themePreference,
            keyOf: (value) => ValueKey('theme-preference-${value.name}'),
            labelOf: (value) => switch (value) {
              ThemePreference.system => '跟随系统',
              ThemePreference.light => '浅色',
              ThemePreference.dark => '深色',
            },
            onChanged:
                controller.initialized ? controller.setThemePreference : (_) {},
          ),
          const SizedBox(height: 8),
          SwitchRow(
            key: const ValueKey('reduce-motion'),
            switchKey: const ValueKey('reduce-motion-switch'),
            title: '减少动效',
            subtitle: '关闭按压缩放与切换过渡；系统的减少动态效果设置同样生效',
            value: controller.reduceMotion,
            onChanged:
                controller.initialized ? controller.setReduceMotion : null,
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    const links = <AnnouncementLink>[
      AnnouncementLink(label: '加载器 GitHub', url: appGithubUrl),
      AnnouncementLink(label: '上游游戏 GitHub', url: githubUrl),
      AnnouncementLink(label: 'B站主页', url: bilibiliHomeUrl),
    ];
    return SurfaceCard(
      key: const ValueKey('about-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: '关于 GardendlessLoader',
          ),
          const SizedBox(height: 12),
          SelectableText(
            controller.aboutContent.content,
            style: TextStyle(color: palette.ink, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final link in links)
                GardenButton(
                  label: link.label,
                  compact: true,
                  onPressed: () => actions.openUrl(link.url),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel();

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    const gestures = <(IconData, String, String)>[
      (Icons.touch_app_rounded, '单指轻点或拖动', '鼠标左键点击或拖动'),
      (Icons.ads_click_rounded, '双指轻点', '双指中心执行右键点击'),
      (Icons.swipe_vertical_rounded, '双指滑动', '模拟鼠标滚轮'),
      (Icons.do_not_touch_rounded, '三指及以上', '取消当前触摸映射'),
      (Icons.keyboard_rounded, '实体鼠标和键盘', '交由系统 WebView 原生处理'),
    ];
    final tips = <String>[
      '返回启动器：Android / 鸿蒙使用系统返回，iOS 从屏幕左边缘右滑。',
      '存档导入导出、GP-Next 补丁与 Mod 安装都在游戏内完成，使用系统文件选择器。',
      'JS Modding 由游戏内 GP-Next 管理；Mod 会在游戏中执行代码，请只安装可信来源的 Mod。',
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: '使用说明',
          ),
          const SizedBox(height: 10),
          for (final (icon, gesture, mapping) in gestures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: palette.inkMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      gesture,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      mapping,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: palette.border, height: 20),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        color: palette.inkMuted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
