import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../l10n/app_strings.dart';
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
    final strings = context.strings;
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
          label: strings.errorsOnly,
          selected: errorsOnly,
          onChanged: onErrorsOnly,
        ),
        if (operations.isNotEmpty)
          PopupMenuButton<String>(
            key: const ValueKey('log-operation-filter'),
            tooltip: strings.filterByOperation,
            initialValue: operationFilter,
            onSelected: onOperation,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'all', child: Text(strings.allOperations)),
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
                          ? strings.allOperations
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
          label: strings.clearFilters,
          tone: GardenButtonTone.ghost,
          compact: true,
          onPressed: onReset,
        ),
        GardenIconButton(
          key: const ValueKey('refresh-logs-button'),
          icon: Icons.refresh_rounded,
          tooltip: strings.refreshLogs,
          onPressed:
              controller.logSnapshotLoading ? null : controller.refreshLogs,
        ),
        GardenButton(
          key: const ValueKey('copy-diagnostics-button'),
          label: strings.copyDiagnostics,
          tone: GardenButtonTone.primary,
          compact: true,
          onPressed: actions.copyDiagnostics,
        ),
        GardenButton(
          key: const ValueKey('delete-log-history-button'),
          label: strings.deleteHistory,
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
    final strings = context.strings;
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
        ? (strings.logStatusUnknown, null)
        : snapshot!.persisting
            ? (strings.logPersisting, palette.accent)
            : (strings.logDegraded, palette.warning);
    final label = TextStyle(color: palette.inkMuted, fontSize: 12);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ListView(
        key: const ValueKey('log-overview'),
        padding: const EdgeInsets.all(18),
        children: [
          PanelHeader(
            title: strings.overview,
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 14),
          Text(strings.appSession, style: label),
          const SizedBox(height: 2),
          SelectableText(
            snapshot?.appSessionId ?? '--',
            style: GardenType.mono(11.5, color: palette.ink),
          ),
          const SizedBox(height: 10),
          Text(strings.gameSession, style: label),
          const SizedBox(height: 2),
          SelectableText(
            gameSessionId ?? strings.none,
            style: GardenType.mono(11.5, color: palette.ink),
          ),
          const SizedBox(height: 14),
          MetricRow(
            metrics: [
              Metric(
                label: strings.logSize,
                value: formatBytes(snapshot?.totalBytes ?? 0),
              ),
              Metric(
                label: strings.writeFailures,
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
            strings.dropped(jsonEncode(snapshot?.droppedByLevel ?? const {})),
            style: GardenType.mono(11, color: palette.inkMuted),
          ),
          const SizedBox(height: 16),
          Text(strings.recentError, style: label),
          const SizedBox(height: 4),
          Text(
            recentError == null
                ? strings.none
                : errorInfo?.title.of(strings) ??
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
              errorInfo.action.of(strings),
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
            title: strings.detailedAudioDiagnostics,
            subtitle: strings.detailedAudioDiagnosticsSubtitle,
            value: controller.detailedAudioDiagnosticsEnabled,
            onChanged: controller.initialized
                ? controller.setDetailedAudioDiagnosticsEnabled
                : null,
          ),
          if (controller.toolShedUnlocked) ...[
            Divider(color: palette.border),
            _ToolShed(controller: controller),
          ],
          Divider(color: palette.border),
          Disclosure(
            key: const ValueKey('log-technical-details'),
            title: strings.technicalDetails,
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

/// Maintenance tools found by tapping the launcher icon seven times.
class _ToolShed extends StatelessWidget {
  const _ToolShed({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    return Column(
      key: const ValueKey('tool-shed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          '🪴 ${strings.toolShed}',
          style: TextStyle(
            color: palette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          strings.toolShedIntro,
          style:
              TextStyle(color: palette.inkMuted, fontSize: 12.5, height: 1.4),
        ),
        SwitchRow(
          key: const ValueKey('touch-trace'),
          switchKey: const ValueKey('touch-trace-switch'),
          title: strings.touchTrace,
          subtitle: strings.touchTraceSubtitle,
          value: controller.touchDiagnosticsEnabled,
          onChanged: controller.setTouchDiagnosticsEnabled,
        ),
        Disclosure(
          key: const ValueKey('tool-shed-local-data'),
          title: strings.localData,
          child: CodeBlock(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  controller.toolShedSnapshot(),
                  style: GardenType.mono(10.5, color: palette.ink),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: GardenButton(
            key: const ValueKey('hide-tool-shed'),
            label: strings.hideToolShed,
            tone: GardenButtonTone.ghost,
            compact: true,
            onPressed: () => controller.setToolShedUnlocked(false),
          ),
        ),
      ],
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
    final strings = context.strings;
    final String? placeholder = snapshot == null
        ? (loading ? strings.readingLogs : strings.logsNotLoaded)
        : events.isEmpty
            ? strings.noMatchingEvents
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
                  tooltip: context.strings.copyEventJson,
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
