import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../l10n/app_strings.dart';
import '../../logging/log_event_catalog.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

/// The minimum levels the timeline filters by; FATAL counts as ERROR.
const _levels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
const _levelRanks = <String, int>{
  'DEBUG': 0,
  'INFO': 1,
  'WARN': 2,
  'ERROR': 3,
  'FATAL': 3,
};

String _levelOf(Map<String, Object?> event) =>
    event['level']?.toString().toUpperCase() ?? 'INFO';

bool _isError(String level) => level == 'ERROR' || level == 'FATAL';

String _levelLabel(AppStrings strings, String level) => switch (level) {
      'DEBUG' => strings.levelDebug,
      'INFO' => strings.levelInfo,
      'WARN' => strings.levelWarn,
      _ => strings.levelError,
    };

Color _levelColor(GardenPalette palette, String level) => switch (level) {
      'WARN' => palette.warning,
      'ERROR' || 'FATAL' => palette.danger,
      'INFO' => palette.inkFaint,
      _ => palette.border,
    };

/// The catalog title of the event's error code, then the event's readable
/// name, then its message, then its raw name.
String _titleOf(AppStrings strings, Map<String, Object?> event) {
  final name = event['event']?.toString() ?? 'unknown_event';
  final message = event['message']?.toString() ?? '';
  return userErrorCatalog[event['code']?.toString()]?.title.of(strings) ??
      logEventTitles[name]?.of(strings) ??
      (message.isEmpty ? name : message);
}

DateTime? _timeOf(Map<String, Object?> event) =>
    DateTime.tryParse(event['timestampUtc']?.toString() ?? '')?.toLocal();

String _clock(DateTime time, {bool seconds = true}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = '${two(time.hour)}:${two(time.minute)}';
  return seconds ? '$minutes:${two(time.second)}' : minutes;
}

String _formatMs(int ms) => ms < 1000
    ? '$ms ms'
    : ms < 60000
        ? '${(ms / 1000).toStringAsFixed(1)} s'
        : formatDuration(Duration(milliseconds: ms));

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
  final _scroll = ScrollController();
  String _minimumLevel = 'INFO';
  String? _operation;

  /// Sequences of the expanded events.
  final _expanded = <Object?>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(Object? sequence) => setState(() {
        if (!_expanded.remove(sequence)) _expanded.add(sequence);
      });

  /// Opens [event] at the top of the errors view.
  void _showError(Map<String, Object?> event) {
    setState(() {
      _minimumLevel = 'ERROR';
      _operation = null;
      _expanded.add(event['sequence']);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final all =
        controller.logSnapshot?.events ?? const <Map<String, Object?>>[];
    final counts = <String, int>{for (final level in _levels) level: 0};
    Map<String, Object?>? latestError;
    for (final event in all) {
      final level = _levelOf(event);
      counts.update(_isError(level) ? 'ERROR' : level, (count) => count + 1,
          ifAbsent: () => 1);
      if (_isError(level)) latestError = event;
    }
    final minimumRank = _levelRanks[_minimumLevel]!;
    final events = [
      for (final event in all.reversed)
        if ((_levelRanks[_levelOf(event)] ?? 1) >= minimumRank &&
            (_operation == null || event['operationId'] == _operation))
          event,
    ];
    final status = _StatusPanel(
      controller: controller,
      actions: widget.actions,
      counts: counts,
      latestError: latestError,
      minimumLevel: _minimumLevel,
      onShowError: _showError,
    );
    final timeline = _Timeline(
      controller: controller,
      counts: counts,
      events: events,
      minimumLevel: _minimumLevel,
      operation: _operation,
      expanded: _expanded,
      scroll: _scroll,
      onLevel: (value) => setState(() => _minimumLevel = value),
      onOperation: (value) => setState(() => _operation = value),
      onToggle: _toggle,
      onCopy: widget.actions.copyLogEvent,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: status),
              const SizedBox(height: 16),
              Expanded(flex: 3, child: timeline),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: widget.compact ? 260 : 300, child: status),
            const SizedBox(width: 16),
            Expanded(child: timeline),
          ],
        );
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.controller,
    required this.actions,
    required this.counts,
    required this.latestError,
    required this.minimumLevel,
    required this.onShowError,
  });

  final AppController controller;
  final LauncherActions actions;
  final Map<String, int> counts;
  final Map<String, Object?>? latestError;
  final String minimumLevel;
  final ValueChanged<Map<String, Object?>> onShowError;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final snapshot = controller.logSnapshot;
    final errors = counts['ERROR']!;
    final warnings = counts['WARN']!;
    final (String headline, Color dot) = snapshot == null
        ? (
            controller.logSnapshotLoading
                ? strings.readingLogs
                : strings.logsNotLoaded,
            palette.inkFaint,
          )
        : errors > 0
            ? (strings.runErrors(errors), palette.danger)
            : warnings > 0
                ? (strings.runWarnings(warnings), palette.warning)
                : (strings.runHealthy, palette.accent);
    final dropped =
        snapshot?.droppedByLevel.values.fold(0, (sum, count) => sum + count) ??
            0;
    final latestError = this.latestError;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ListView(
        key: const ValueKey('log-status'),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: GardenType.title(15, color: palette.ink),
                ),
              ),
            ],
          ),
          if (snapshot != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                snapshot.persisting
                    ? strings.logsSavedOnDevice(
                        formatBytes(snapshot.totalBytes),
                      )
                    : strings.logsMemoryOnly,
                if (snapshot.writeFailureCount > 0)
                  strings.logWriteFailures(snapshot.writeFailureCount),
                if (dropped > 0) strings.logsDropped(dropped),
              ].join(' · '),
              style: TextStyle(
                color: snapshot.persisting ? palette.inkMuted : palette.warning,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (latestError != null) ...[
            const SizedBox(height: 14),
            _LatestError(
              event: latestError,
              onTap: () => onShowError(latestError),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: GardenButton(
              key: const ValueKey('export-logs-button'),
              label: strings.exportLogs,
              icon: Icons.ios_share_rounded,
              tone: GardenButtonTone.primary,
              onPressed: actions.exportLogs,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: GardenButton(
              key: const ValueKey('copy-summary-button'),
              label: strings.copySummary,
              icon: Icons.copy_rounded,
              compact: true,
              onPressed: actions.copySummary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GardenButton(
                  key: const ValueKey('refresh-logs-button'),
                  label: strings.refreshLogs,
                  icon: Icons.refresh_rounded,
                  compact: true,
                  busy: controller.logSnapshotLoading,
                  onPressed: controller.refreshLogs,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GardenButton(
                  key: const ValueKey('delete-log-history-button'),
                  label: strings.deleteHistory,
                  tone: GardenButtonTone.danger,
                  compact: true,
                  onPressed: actions.deleteLogHistory,
                ),
              ),
            ],
          ),
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
                  child: ExcludeFocusTraversal(
                    child: SelectableText(
                      controller.buildLogText(minimumLevel: minimumLevel),
                      style: GardenType.mono(10.5, color: palette.ink),
                    ),
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

class _LatestError extends StatelessWidget {
  const _LatestError({required this.event, required this.onTap});

  final Map<String, Object?> event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final info = userErrorCatalog[event['code']?.toString()];
    final time = _timeOf(event);
    return Pressable(
      key: const ValueKey('log-latest-error'),
      onTap: onTap,
      semanticLabel: '${strings.recentError}: ${_titleOf(strings, event)}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.recentError,
              style: TextStyle(
                color: palette.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _titleOf(strings, event),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (info != null) ...[
              const SizedBox(height: 4),
              Text(
                info.action.of(strings),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (time != null)
                  Text(
                    _clock(time),
                    style: GardenType.mono(11, color: palette.inkMuted),
                  ),
                const Spacer(),
                Text(
                  strings.showEvent,
                  style: TextStyle(
                    color: palette.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.danger,
                ),
              ],
            ),
          ],
        ),
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
                child: ExcludeFocusTraversal(
                  child: SelectableText(
                    controller.toolShedSnapshot(),
                    style: GardenType.mono(10.5, color: palette.ink),
                  ),
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

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.controller,
    required this.counts,
    required this.events,
    required this.minimumLevel,
    required this.operation,
    required this.expanded,
    required this.scroll,
    required this.onLevel,
    required this.onOperation,
    required this.onToggle,
    required this.onCopy,
  });

  final AppController controller;
  final Map<String, int> counts;

  /// The filtered events, newest first.
  final List<Map<String, Object?>> events;
  final String minimumLevel;
  final String? operation;
  final Set<Object?> expanded;
  final ScrollController scroll;
  final ValueChanged<String> onLevel;
  final ValueChanged<String?> onOperation;
  final ValueChanged<Object?> onToggle;
  final Future<void> Function(Map<String, Object?> event) onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final snapshot = controller.logSnapshot;
    final String? placeholder = snapshot == null
        ? (controller.logSnapshotLoading
            ? strings.readingLogs
            : strings.logsNotLoaded)
        : events.isEmpty
            ? strings.noMatchingEvents
            : null;
    // A game's time span covers all of its events, whatever the filter.
    final spans = <Object, (DateTime, DateTime)>{};
    for (final event in snapshot?.events ?? const <Map<String, Object?>>[]) {
      final id = event['gameSessionId'];
      final time = _timeOf(event);
      if (id == null || time == null) continue;
      spans[id] = (spans[id]?.$1 ?? time, time);
    }
    String groupOf(Object? gameSessionId) {
      if (gameSessionId == null) return strings.launcherEvents;
      final span = spans[gameSessionId];
      return strings.gameEvents(
        span == null
            ? '--'
            : '${_clock(span.$1, seconds: false)}–'
                '${_clock(span.$2, seconds: false)}',
      );
    }

    // Group labels and events, with a label wherever the game changes.
    final items = <Object>[];
    for (var i = 0; i < events.length; i++) {
      final gameSessionId = events[i]['gameSessionId'];
      if (i == 0 || events[i - 1]['gameSessionId'] != gameSessionId) {
        items.add(groupOf(gameSessionId));
      }
      items.add(events[i]);
    }
    final operation = this.operation;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: GardenSegmented<String>(
                    key: const ValueKey('log-minimum-level-filter'),
                    values: _levels,
                    selected: minimumLevel,
                    labelOf: (level) =>
                        '${_levelLabel(strings, level)} ${counts[level]}',
                    keyOf: (level) => ValueKey('log-level-$level'),
                    onChanged: onLevel,
                  ),
                ),
                if (operation != null)
                  _OperationChip(
                    operation: operation,
                    onClear: () => onOperation(null),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: placeholder != null
                ? Center(
                    child: Text(
                      placeholder,
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(15),
                    ),
                    child: ListView.builder(
                      key: const ValueKey('structured-log-events'),
                      controller: scroll,
                      padding: const EdgeInsets.only(bottom: 6),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        if (item is String) return _GroupLabel(label: item);
                        final event = item as Map<String, Object?>;
                        final sequence = event['sequence'];
                        final eventOperation = event['operationId']?.toString();
                        return _EventRow(
                          key: ValueKey('log-event-$sequence'),
                          event: event,
                          expanded: expanded.contains(sequence),
                          onToggle: () => onToggle(sequence),
                          onCopy: () => onCopy(event),
                          onOperation:
                              operation == null && eventOperation != null
                                  ? () => onOperation(eventOperation)
                                  : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OperationChip extends StatelessWidget {
  const _OperationChip({required this.operation, required this.onClear});

  final String operation;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    return Pressable(
      key: const ValueKey('log-operation-filter'),
      onTap: onClear,
      semanticLabel: strings.showAllOperations,
      tooltip: strings.showAllOperations,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                strings.operationFilter(operation),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.close_rounded, size: 16, color: palette.accent),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Container(
      color: palette.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Text(
        label,
        style: TextStyle(
          color: palette.inkMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    super.key,
    required this.event,
    required this.expanded,
    required this.onToggle,
    required this.onCopy,
    required this.onOperation,
  });

  final Map<String, Object?> event;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  /// Filters the timeline to this event's operation; null when the event has
  /// none or the timeline already shows one operation.
  final VoidCallback? onOperation;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final level = _levelOf(event);
    final time = _timeOf(event);
    final title = _titleOf(strings, event);
    final message = event['message']?.toString() ?? '';
    final durationMs = (event['durationMs'] as num?)?.toInt();
    final Widget? trailing = switch (event['outcome']) {
      'failed' => Text(
          strings.eventFailed,
          style: TextStyle(
            color: palette.danger,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      'cancelled' => Text(
          strings.eventCancelled,
          style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
        ),
      _ when durationMs != null => Text(
          _formatMs(durationMs),
          style: GardenType.mono(11, color: palette.inkFaint),
        ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: onToggle,
          scale: 1,
          semanticLabel: title,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _levelColor(palette, level),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      time == null ? '' : _clock(time),
                      style: GardenType.mono(11, color: palette.inkFaint),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: expanded ? 4 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isError(level) ? palette.danger : palette.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (message.isNotEmpty && message != title)
                        Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: palette.inkMuted, fontSize: 12),
                        )
                      else
                        Text(
                          '${event['category'] ?? ''} · '
                          '${event['event'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GardenType.mono(10.5, color: palette.inkFaint),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: trailing,
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(31, 0, 16, 12),
            child: _EventDetail(
              event: event,
              onCopy: onCopy,
              onOperation: onOperation,
            ),
          ),
      ],
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({
    required this.event,
    required this.onCopy,
    required this.onOperation,
  });

  final Map<String, Object?> event;
  final VoidCallback onCopy;
  final VoidCallback? onOperation;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final info = userErrorCatalog[event['code']?.toString()];
    final message = event['message']?.toString() ?? '';
    final eventContext = event['context'];
    final error = event['error'];
    final facts = [
      'event: ${event['event']}',
      'category: ${event['category']}',
      'level: ${event['level']} · outcome: ${event['outcome']} · '
          'source: ${event['source']}',
      if (event['code'] != null) 'code: ${event['code']}',
      if (eventContext is Map)
        for (final entry in eventContext.entries)
          '${entry.key}: ${entry.value}',
      if (event['durationMs'] != null) 'durationMs: ${event['durationMs']}',
      if (event['operationId'] != null) 'operation: ${event['operationId']}',
      if (event['gameSessionId'] != null)
        'gameSession: ${event['gameSessionId']}',
    ];
    final errorText = error is Map
        ? [
            error['type'],
            if (error['message'] != message) error['message'],
            error['stackTrace'],
          ]
            .map((part) => part?.toString() ?? '')
            .where((part) => part.isNotEmpty)
            .join('\n')
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info != null) ...[
            Text(
              info.action.of(strings),
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (message.isNotEmpty) ...[
            ExcludeFocusTraversal(
              child: SelectableText(
                message,
                style:
                    TextStyle(color: palette.ink, fontSize: 12.5, height: 1.45),
              ),
            ),
            const SizedBox(height: 8),
          ],
          ExcludeFocusTraversal(
            child: SelectableText(
              facts.join('\n'),
              style: GardenType.mono(11, color: palette.inkMuted),
            ),
          ),
          if (errorText.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: ExcludeFocusTraversal(
                  child: SelectableText(
                    errorText,
                    style: GardenType.mono(10.5, color: palette.ink),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GardenButton(
                label: strings.copyEventJson,
                icon: Icons.copy_rounded,
                compact: true,
                onPressed: onCopy,
              ),
              if (onOperation != null)
                GardenButton(
                  label: strings.onlyThisOperation,
                  icon: Icons.filter_list_rounded,
                  tone: GardenButtonTone.ghost,
                  compact: true,
                  onPressed: onOperation,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
