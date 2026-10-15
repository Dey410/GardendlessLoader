import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../logging/app_logger.dart';
import '../../logging/log_event_catalog.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

const _levels = ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'];
const _levelRanks = <String, int>{
  'DEBUG': 0,
  'INFO': 1,
  'WARN': 2,
  'ERROR': 3,
  'FATAL': 4,
};

Color _levelColor(GardenPalette palette, String level) => switch (level) {
      'WARN' => palette.warning,
      'ERROR' || 'FATAL' => palette.danger,
      'INFO' => palette.inkMuted,
      _ => palette.inkFaint,
    };

class LogsPage extends StatefulWidget {
  const LogsPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _minimumLevel = 'INFO';
  bool _errorsOnly = false;
  String _operationFilter = 'all';

  List<Map<String, Object?>> _visibleEvents(AppLogSnapshot snapshot) {
    final minimumRank = _levelRanks[_minimumLevel] ?? 1;
    return snapshot.events.where((event) {
      final level = event['level']?.toString().toUpperCase() ?? 'INFO';
      if ((_levelRanks[level] ?? 1) < minimumRank) return false;
      if (_errorsOnly && level != 'ERROR' && level != 'FATAL') return false;
      return _operationFilter == 'all' ||
          event['operationId']?.toString() == _operationFilter;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final snapshot = controller.logSnapshot;
    final operations = (snapshot?.events
                .map((event) => event['operationId']?.toString())
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .toSet() ??
            <String>{})
        .toList(growable: false)
      ..sort();
    if (_operationFilter != 'all' && !operations.contains(_operationFilter)) {
      _operationFilter = 'all';
    }
    final events = snapshot == null
        ? const <Map<String, Object?>>[]
        : _visibleEvents(snapshot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          controller: controller,
          actions: widget.actions,
          minimumLevel: _minimumLevel,
          errorsOnly: _errorsOnly,
          operationFilter: _operationFilter,
          operations: operations,
          onLevel: (value) => setState(() => _minimumLevel = value),
          onErrorsOnly: (value) => setState(() => _errorsOnly = value),
          onOperation: (value) => setState(() => _operationFilter = value),
          onReset: () => setState(() {
            _minimumLevel = 'INFO';
            _errorsOnly = false;
            _operationFilter = 'all';
          }),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final overview = _Overview(
                controller: controller,
                snapshot: snapshot,
                minimumLevel: _minimumLevel,
                errorsOnly: _errorsOnly,
              );
              final list = _EventList(
                snapshot: snapshot,
                loading: controller.logSnapshotLoading,
                events: events,
                onCopy: widget.actions.copyLogEvent,
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: overview),
                    const SizedBox(height: 16),
                    Expanded(flex: 3, child: list),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: widget.compact ? 260 : 300, child: overview),
                  const SizedBox(width: 16),
                  Expanded(child: list),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.actions,
    required this.minimumLevel,
    required this.errorsOnly,
    required this.operationFilter,
    required this.operations,
    required this.onLevel,
    required this.onErrorsOnly,
    required this.onOperation,
    required this.onReset,
  });

  final AppController controller;
  final LauncherActions actions;
  final String minimumLevel;
  final bool errorsOnly;
  final String operationFilter;
  final List<String> operations;
  final ValueChanged<String> onLevel;
  final ValueChanged<bool> onErrorsOnly;
  final ValueChanged<String> onOperation;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: GardenSegmented<String>(
            key: const ValueKey('log-minimum-level-filter'),
            values: _levels,
            selected: minimumLevel,
            labelOf: (value) => value,
            keyOf: (value) => ValueKey('log-level-$value'),
            onChanged: onLevel,
          ),
        ),
        _ToggleChip(
          key: const ValueKey('log-errors-only-filter'),
          label: '只看错误',
          selected: errorsOnly,
          onChanged: onErrorsOnly,
        ),
        if (operations.isNotEmpty)
          PopupMenuButton<String>(
            key: const ValueKey('log-operation-filter'),
            tooltip: '按 Operation 筛选',
            initialValue: operationFilter,
            onSelected: onOperation,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('全部 Operation')),
              for (final operation in operations)
                PopupMenuItem(
                  value: operation,
                  child: Text(
                    operation,
                    overflow: TextOverflow.ellipsis,
                    style: GardenType.mono(12),
                  ),
                ),
            ],
            child: Container(
              height: 36,
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      operationFilter == 'all'
                          ? '全部 Operation'
                          : operationFilter,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.ink, fontSize: 12.5),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: palette.inkMuted),
                ],
              ),
            ),
          ),
        GardenButton(
          key: const ValueKey('clear-log-view-filter'),
          label: '清空筛选',
          tone: GardenButtonTone.ghost,
          compact: true,
          onPressed: onReset,
        ),
        GardenIconButton(
          key: const ValueKey('refresh-logs-button'),
          icon: Icons.refresh_rounded,
          tooltip: '刷新日志',
          onPressed:
              controller.logSnapshotLoading ? null : controller.refreshLogs,
        ),
        GardenButton(
          key: const ValueKey('copy-diagnostics-button'),
          label: '复制诊断',
          tone: GardenButtonTone.primary,
          compact: true,
          onPressed: actions.copyDiagnostics,
        ),
        GardenButton(
          key: const ValueKey('delete-log-history-button'),
          label: '删除历史',
          tone: GardenButtonTone.danger,
          compact: true,
          onPressed: actions.deleteLogHistory,
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Semantics(
      toggled: selected,
      child: Pressable(
        onTap: () => onChanged(!selected),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: GardenMotion.quick,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? palette.ink : palette.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? palette.background : palette.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.controller,
    required this.snapshot,
    required this.minimumLevel,
    required this.errorsOnly,
  });

  final AppController controller;
  final AppLogSnapshot? snapshot;
  final String minimumLevel;
  final bool errorsOnly;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final counts = <String, int>{for (final level in _levels) level: 0};
    String? gameSessionId;
    Map<String, Object?>? recentError;
    for (final event in snapshot?.events ?? const <Map<String, Object?>>[]) {
      final level = event['level']?.toString().toUpperCase() ?? 'INFO';
      counts[level] = (counts[level] ?? 0) + 1;
      gameSessionId = event['gameSessionId']?.toString() ?? gameSessionId;
      if (level == 'ERROR' || level == 'FATAL') recentError = event;
    }
    final errorInfo = recentError == null
        ? null
        : userErrorCatalog[recentError['code']?.toString()];
    final (String status, Color? statusColor) = snapshot == null
        ? ('日志状态未知', null)
        : snapshot!.persisting
            ? ('持久化正常', palette.accent)
            : ('内存降级', palette.warning);
    final label = TextStyle(color: palette.inkMuted, fontSize: 12);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ListView(
        key: const ValueKey('log-overview'),
        padding: const EdgeInsets.all(18),
        children: [
          PanelHeader(
            title: '概览',
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 14),
          Text('当前会话', style: label),
          const SizedBox(height: 2),
          SelectableText(
            snapshot?.appSessionId ?? '--',
            style: GardenType.mono(11.5, color: palette.ink),
          ),
          const SizedBox(height: 10),
          Text('游戏会话', style: label),
          const SizedBox(height: 2),
          SelectableText(
            gameSessionId ?? '无',
            style: GardenType.mono(11.5, color: palette.ink),
          ),
          const SizedBox(height: 14),
          MetricRow(
            metrics: [
              Metric(
                label: '日志占用',
                value: formatBytes(snapshot?.totalBytes ?? 0),
              ),
              Metric(
                label: '写入失败',
                value: '${snapshot?.writeFailureCount ?? 0}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'v${controller.currentAppVersion} · '
            '${controller.gameHostPlatform.wireName}',
            style: label,
          ),
          const SizedBox(height: 6),
          Text(
            [for (final level in _levels) '$level ${counts[level]}']
                .join(' · '),
            style: GardenType.mono(11, color: palette.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(
            '丢弃 ${jsonEncode(snapshot?.droppedByLevel ?? const {})}',
            style: GardenType.mono(11, color: palette.inkMuted),
          ),
          const SizedBox(height: 16),
          Text('最近错误', style: label),
          const SizedBox(height: 4),
          Text(
            recentError == null
                ? '无'
                : errorInfo?.title ??
                    '${recentError['code'] ?? recentError['event']}: '
                        '${recentError['message'] ?? ''}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: recentError == null ? palette.ink : palette.danger,
              fontSize: 13,
            ),
          ),
          if (errorInfo != null) ...[
            const SizedBox(height: 4),
            Text(
              errorInfo.action,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 8),
          Divider(color: palette.border),
          SwitchRow(
            key: const ValueKey('detailed-audio-diagnostics'),
            switchKey: const ValueKey('detailed-audio-diagnostics-switch'),
            title: '详细音频诊断',
            subtitle: '下一次启动游戏时采集音频加载与播放事件',
            value: controller.detailedAudioDiagnosticsEnabled,
            onChanged: controller.initialized
                ? controller.setDetailedAudioDiagnosticsEnabled
                : null,
          ),
          Divider(color: palette.border),
          Disclosure(
            key: const ValueKey('log-technical-details'),
            title: '技术详情',
            child: CodeBlock(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: SelectableText(
                    controller.buildLogText(
                      minimumLevel: minimumLevel,
                      errorsOnly: errorsOnly,
                    ),
                    style: GardenType.mono(10.5, color: palette.ink),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({
    required this.snapshot,
    required this.loading,
    required this.events,
    required this.onCopy,
  });

  final AppLogSnapshot? snapshot;
  final bool loading;
  final List<Map<String, Object?>> events;
  final Future<void> Function(Map<String, Object?> event) onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final String? placeholder = snapshot == null
        ? (loading ? '正在读取日志…' : '日志尚未加载')
        : events.isEmpty
            ? '当前筛选条件下没有事件'
            : null;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: placeholder != null
          ? Center(
              child:
                  Text(placeholder, style: TextStyle(color: palette.inkMuted)),
            )
          : ListView.separated(
              key: const ValueKey('structured-log-events'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: events.length,
              separatorBuilder: (context, index) => Divider(
                color: palette.border,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) {
                final event = events[events.length - index - 1];
                return _EventRow(
                  key: ValueKey('log-event-${event['sequence'] ?? index}'),
                  event: event,
                  onCopy: () => onCopy(event),
                );
              },
            ),
    );
  }
}

class _EventRow extends StatefulWidget {
  const _EventRow({super.key, required this.event, required this.onCopy});

  final Map<String, Object?> event;
  final VoidCallback onCopy;

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final event = widget.event;
    final level = event['level']?.toString().toUpperCase() ?? 'INFO';
    final timestamp = event['timestampUtc']?.toString() ?? '';
    final time = timestamp.length >= 19 ? timestamp.substring(11, 19) : '';
    final subtitle = [
      if (event['code'] != null) event['code'],
      if (event['operationId'] != null) 'op=${event['operationId']}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: () => setState(() => _expanded = !_expanded),
          scale: 1,
          semanticLabel: event['event']?.toString(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    level,
                    style: GardenType.mono(
                      11,
                      weight: FontWeight.w600,
                      color: _levelColor(palette, level),
                    ),
                  ),
                ),
                if (time.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      time,
                      style: GardenType.mono(11, color: palette.inkFaint),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['event']?.toString() ?? 'unknown_event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GardenType.mono(12.5, color: palette.ink),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GardenType.mono(10.5, color: palette.inkMuted),
                        ),
                    ],
                  ),
                ),
                GardenIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: '复制单条事件 JSON',
                  onPressed: widget.onCopy,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: CodeBlock(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(event),
                style: GardenType.mono(11.5, color: palette.ink),
              ),
            ),
          ),
      ],
    );
  }
}
