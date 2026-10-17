import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../logging/log_event_catalog.dart';
import '../../models.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
    required this.detailsExpanded,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;
  final bool detailsExpanded;

  @override
  Widget build(BuildContext context) {
    return TwoColumn(
      gap: compact ? 16 : 24,
      left: [_CurrentResourceCard(controller: controller, actions: actions)],
      right: [
        _GameVersionCard(controller: controller, actions: actions),
        const SizedBox(height: 16),
        _ImportCard(
          controller: controller,
          actions: actions,
          detailsExpanded: detailsExpanded,
        ),
      ],
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.controller,
    required this.actions,
    required this.detailsExpanded,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool detailsExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final progress = controller.importProgress;
    final hasResource = controller.hasCurrentResource;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: hasResource ? '更新资源' : '导入资源'),
          const SizedBox(height: 8),
          Text(
            '选择 Gardendless Web 资源 ZIP，支持标准 Cocos 构建、GP-Next 构建与移动端优化包。'
            '新资源写入空闲槽，校验和自检通过后才会切换；失败或取消不影响当前资源。',
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          AnimatedSize(
            duration: GardenMotionScope.reduced(context)
                ? Duration.zero
                : GardenMotion.panel,
            curve: GardenMotion.easeOut,
            alignment: Alignment.topCenter,
            child: progress.phase == ImportPhase.idle
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _ImportProgressView(
                      key: const ValueKey('resource-progress-region'),
                      progress: progress,
                      expanded: detailsExpanded,
                      onToggle: actions.toggleImportDetails,
                      onDismiss: controller.dismissImportProgress,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: GardenButton(
              key: const ValueKey('import-zip-button'),
              label: controller.isImporting
                  ? '导入中…'
                  : hasResource
                      ? '选择 ZIP 更新'
                      : '选择 ZIP 导入',
              icon: Icons.folder_open_rounded,
              tone: GardenButtonTone.primary,
              onPressed: controller.busy || controller.isImporting
                  ? null
                  : actions.importResources,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressView extends StatelessWidget {
  const _ImportProgressView({
    super.key,
    required this.progress,
    required this.expanded,
    required this.onToggle,
    required this.onDismiss,
  });

  final ImportProgress progress;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  static const _steps = ['读取', '解压', '校验', '自检'];

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final failed = progress.phase == ImportPhase.failed;
    final completed = progress.phase == ImportPhase.completed;
    final message = progress.message ?? importPhaseMessage(progress.phase);
    final hint = failed ? userErrorCatalog[progress.errorCode]?.action : null;
    final title = failed
        ? '导入失败 · $message'
        : completed
            ? '导入完成 100%'
            : '步骤 ${progress.stepIndex}/${progress.stepCount} · $message';
    final color = failed ? palette.danger : palette.accent;
    final value = failed || completed ? 1.0 : progress.value;
    final step = completed ? 5 : progress.stepIndex;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProgressRing(
                value: value,
                size: 44,
                color: color,
                child: failed || completed
                    ? Icon(
                        failed ? Icons.close_rounded : Icons.check_rounded,
                        size: 20,
                        color: color,
                      )
                    : value == null
                        ? null
                        : Text(
                            '${(value * 100).round()}%',
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: failed ? palette.danger : palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Wrap between steps, never inside a two-character label.
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Text(
                            i == 0 ? _steps[i] : '›  ${_steps[i]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: i + 1 <= step && !failed
                                  ? palette.ink
                                  : palette.inkFaint,
                              fontWeight: i + 1 == step
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        style:
                            TextStyle(color: palette.inkMuted, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              GardenIconButton(
                key: const ValueKey('resource-progress-toggle'),
                icon: expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                tooltip: expanded ? '收起进度详情' : '展开进度详情',
                onPressed: onToggle,
              ),
              if (failed || completed)
                GardenIconButton(
                  key: const ValueKey('dismiss-import-progress'),
                  icon: Icons.close_rounded,
                  tooltip: failed ? '关闭失败提示' : '关闭完成提示',
                  onPressed: onDismiss,
                ),
            ],
          ),
          if (expanded)
            Padding(
              key: const ValueKey('resource-progress-details'),
              padding: const EdgeInsets.only(top: 16),
              child: MetricRow(
                metrics: [
                  Metric(
                    label: '文件',
                    value: progress.totalFiles > 0
                        ? '${progress.copiedFiles}/${progress.totalFiles}'
                        : '${progress.copiedFiles}',
                  ),
                  Metric(
                    label: '数据量',
                    value: progress.totalBytes > 0
                        ? '${formatBytes(progress.copiedBytes)} / '
                            '${formatBytes(progress.totalBytes)}'
                        : formatBytes(progress.copiedBytes),
                  ),
                  Metric(
                    label: '速度',
                    value: progress.bytesPerSecond > 0
                        ? '${formatBytes(progress.bytesPerSecond.round())}/s'
                        : '--',
                  ),
                  Metric(
                    label: '已用时间',
                    value: formatDuration(progress.elapsed),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GameVersionCard extends StatelessWidget {
  const _GameVersionCard({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final update = controller.availableGameUpdate;
    final current = controller.hasCurrentResource
        ? (controller.currentGameVersion ?? '未知')
        : '--';
    final latest =
        update?.latestVersion ?? controller.latestGameVersion ?? '--';
    final (String status, Color? statusColor) = update != null
        ? ('有新版本', palette.accent)
        : controller.updateCheckInProgress
            ? ('检查中', null)
            : controller.latestGameVersion == null
                ? ('尚未获取最新版本', null)
                : !controller.hasCurrentResource
                    ? ('可获取稳定版', null)
                    : ('已是最新', palette.accent);
    return SurfaceCard(
      key: update == null ? null : const ValueKey('game-update-entry'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: '游戏版本',
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(label: '当前', value: current),
              Metric(label: '最新稳定版', value: latest),
            ],
          ),
          if (update != null) ...[
            const SizedBox(height: 8),
            Text(
              '${update.currentVersion} → ${update.latestVersion}',
              style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (update != null)
                GardenButton(
                  label: '获取游戏资源',
                  icon: Icons.download_rounded,
                  tone: GardenButtonTone.primary,
                  compact: true,
                  onPressed: () => actions.openUrl(appCloudDriveUpdateUrl),
                ),
              GardenButton(
                label: '查看游戏 GitHub',
                compact: true,
                onPressed: () => actions.openUrl(githubUrl),
              ),
              if (update != null)
                GardenButton(
                  label: '稍后提醒',
                  tone: GardenButtonTone.ghost,
                  compact: true,
                  onPressed: () => actions.deferGameUpdate(update),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentResourceCard extends StatelessWidget {
  const _CurrentResourceCard({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final manifest = controller.manifest;
    final hasResource = controller.hasCurrentResource;
    final slot = switch (manifest.activeSlot) {
      ResourceSlot.slotA => '槽 A',
      ResourceSlot.slotB => '槽 B',
      null => '无激活槽',
    };
    final selfCheck = manifest.lastSelfCheckAt == null
        ? (hasResource ? '未执行' : '等待导入')
        : '已通过 · ${formatDateTime(manifest.lastSelfCheckAt)}';
    final lastError = manifest.lastErrorMessage;
    final gpNext = !controller.hasGpNext
        ? '未检测到（标准 Web 构建）'
        : controller.gpNextCompatible
            ? '兼容 ${controller.gpNextVersion ?? ''}'.trim()
            : '不兼容：${controller.gpNextCompatibilityError ?? '未知原因'}';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: '当前资源',
            trailing: StatusLabel(
              label: slot,
              color: hasResource ? palette.accent : null,
            ),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(
                label: '文件数',
                value: hasResource ? '${manifest.fileCount}' : '--',
              ),
              Metric(
                label: '体积',
                value: hasResource ? formatBytes(manifest.totalBytes) : '--',
              ),
              Metric(
                label: '导入时间',
                value: formatDateTime(manifest.lastImportAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: palette.border),
          InfoRow(
            label: '标题',
            value: hasResource ? controller.detectedTitle : '尚未导入',
          ),
          InfoRow(
            label: '资源校验',
            value: hasResource ? '校验通过' : '等待导入',
            color: hasResource ? null : palette.warning,
          ),
          InfoRow(
            label: '游戏宿主',
            value:
                '${controller.gameHostPlatform.nativeHostName} · 无 HTTP Server',
          ),
          InfoRow(label: '上次自检', value: selfCheck),
          InfoRow(
            label: '最近错误',
            value: lastError ?? '无',
            color: lastError == null ? null : palette.danger,
            maxLines: 3,
            hint: lastError == null
                ? null
                : userErrorCatalog[manifest.lastErrorCode]?.action,
          ),
          InfoRow(
            label: 'GP-Next',
            value: gpNext,
            color: controller.hasGpNext && !controller.gpNextCompatible
                ? palette.danger
                : null,
            hint: controller.hasGpNext && !controller.gpNextCompatible
                ? userErrorCatalog['gp_next_incompatible']?.action
                : null,
          ),
          InfoRow(
            label: '资源根目录',
            value: controller.userVisibleRoot,
            mono: true,
            trailing: GardenButton(
              key: const ValueKey('copy-resource-root-button'),
              label: '复制',
              compact: true,
              onPressed: actions.copyResourceRoot,
            ),
          ),
          Divider(color: palette.border),
          Disclosure(
            key: const ValueKey('resource-technical-details'),
            title: '技术详情',
            child: _TechnicalDetails(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final manifest = controller.manifest;
    final rows = <(String, String)>[
      ('activeSlot', manifest.activeSlot?.name ?? 'none'),
      ('generation', '${manifest.generation}'),
      ('transaction', manifest.transactionState.name),
      ('transactionSlot', manifest.transactionSlot?.name ?? 'none'),
      ('buildProfile', manifest.buildProfile.name),
      ('gpNextVersion', controller.gpNextVersion ?? 'none'),
      ('gpNextError', controller.gpNextCompatibilityError ?? 'none'),
      ('origin', controller.gameHostPlatform.origin),
      ('lastErrorCode', manifest.lastErrorCode ?? 'none'),
    ];
    return CodeBlock(
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        key,
                        style: GardenType.mono(11.5, color: palette.inkMuted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: GardenType.mono(11.5, color: palette.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
