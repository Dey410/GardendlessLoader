import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_controller.dart';
import '../../constants.dart';
import '../../models.dart';
import 'garden_scene.dart';
import 'garden_theme.dart';

/// The launcher presentation layer. Resource transactions and native game-host
/// security remain exclusively owned by AppController and the existing services.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _page = 0;
  bool _working = false;
  bool _launching = false;
  bool _motion = true;
  bool _progressExpanded = true;
  String? _lastMessage;
  ImportPhase _lastPhase = ImportPhase.idle;
  String _logLevel = 'ALL';
  String _logQuery = '';
  AppController get c => widget.controller;
  bool get _locked => _working || c.busy || !c.initialized;
  bool get _shortLandscape {
    final size = MediaQuery.sizeOf(context);
    return size.height < 520 && size.width > size.height;
  }
  static const _names = ['花园', '资源', '日志', '设置'];
  static const _icons = [Icons.spa_outlined, Icons.inventory_2_outlined,
    Icons.terminal_rounded, Icons.tune_rounded];

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_guard(() => c.checkForUpdates(silent: true)));
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
      _lastMessage = null;
      _lastPhase = ImportPhase.idle;
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final phase = c.importProgress.phase;
    if (_lastPhase != phase && c.isImporting &&
        (_lastPhase == ImportPhase.idle || _lastPhase == ImportPhase.failed ||
         _lastPhase == ImportPhase.completed)) {
      _progressExpanded = true;
    }
    _lastPhase = phase;
    final message = c.message;
    if (message == _lastMessage) return;
    _lastMessage = message;
    if (message != null && phase != ImportPhase.completed && phase != ImportPhase.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast(message);
      });
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _toast('操作未完成：$error');
    }
  }

  Future<void> _operate(Future<void> Function() action, {bool launch = false}) async {
    if (_locked) return;
    setState(() { _working = true; _launching = launch; });
    try {
      await _guard(action);
    } finally {
      if (mounted) {
        setState(() { _working = false; _launching = false; });
      }
    }
  }

  void _navigate(int page) {
    setState(() => _page = page);
    if (page == 2) unawaited(_guard(c.refreshLogs));
  }

  Future<void> _open(String url) => _guard(() async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('仅支持有效的 HTTPS 链接');
    }
    await const MethodChannel('io.github.dey410.gardendlessloader/external_browser')
      .invokeMethod<void>('open', <String, Object?>{'url': url});
  });

  Future<void> _copy(String text, String confirmation) => _guard(() async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(confirmation);
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: GardenTheme.dark,
    child: AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final rail = constraints.maxWidth >= 760 ||
              (_shortLandscape && constraints.maxWidth >= 600);
            final content = Expanded(child: Column(children: [
              _header(constraints.maxWidth < 540 || _shortLandscape),
              const Divider(),
              Expanded(child: _content()),
            ]));
            return Column(children: [
              Expanded(child: Row(children: [
                if (rail) _rail(),
                content,
              ])),
              if (!rail) NavigationBar(
                key: const ValueKey('garden-bottom-nav'),
                selectedIndex: _page,
                onDestinationSelected: _navigate,
                backgroundColor: GardenTheme.panel,
                indicatorColor: GardenTheme.acid,
                destinations: List.generate(4, (i) => NavigationDestination(
                  key: ValueKey('garden-nav-$i'),
                  icon: Icon(_icons[i]),
                  selectedIcon: Icon(_icons[i], color: GardenTheme.background),
                  label: _names[i],
                )),
              ),
            ]);
          }),
        ),
      ),
    ),
  );

  Widget _rail() => Container(
    width: 88,
    decoration: const BoxDecoration(border: Border(right: BorderSide(color: GardenTheme.line))),
    child: Column(children: [
      SizedBox(height: _shortLandscape ? 10 : 20),
      Container(width: _shortLandscape ? 36 : 46, height: _shortLandscape ? 36 : 46,
        decoration: BoxDecoration(color: GardenTheme.acid, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.spa_rounded, color: GardenTheme.background, size: 27)),
      SizedBox(height: _shortLandscape ? 10 : 30),
      Expanded(child: ListView(key: const ValueKey('garden-rail-scroll'), children: List.generate(4, (i) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: _shortLandscape ? 3 : 5),
        child: Semantics(selected: _page == i, button: true, label: '${_names[i]}页面',
          child: Tooltip(message: _names[i], child: Material(
            color: _page == i ? GardenTheme.elevated : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(key: ValueKey('garden-nav-$i'),
              borderRadius: BorderRadius.circular(16), onTap: () => _navigate(i),
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48),
                child: Padding(padding: EdgeInsets.symmetric(vertical: _shortLandscape ? 8 : 13),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_icons[i], color: _page == i ? GardenTheme.acid : GardenTheme.muted, size: 23),
                  if (!_shortLandscape) const SizedBox(height: 5),
                  if (!_shortLandscape) Text(_names[i], maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: _page == i ? GardenTheme.acid : GardenTheme.muted)),
                ]))),
            ),
          )),
        ),
      )))),
      IconButton(tooltip: '项目 GitHub', onPressed: () => _open(appGithubUrl), icon: const Icon(Icons.code_rounded)),
      SizedBox(height: _shortLandscape ? 4 : 14),
    ]),
  );

  Widget _header(bool compact) => Padding(
    padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 28, vertical: _shortLandscape ? 8 : 16),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GARDENDLESS', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: compact ? 15 : 18, fontWeight: FontWeight.w900, letterSpacing: 3)),
        if (!compact) _text('L O C A L   G A R D E N   L A U N C H E R', size: 9, color: GardenTheme.muted),
      ])),
      const SizedBox(width: 12),
      Tooltip(message: '版本与更新', child: OutlinedButton(
        key: const ValueKey('garden-updates'), onPressed: _showUpdates,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 42), padding: const EdgeInsets.symmetric(horizontal: 12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (c.updateCheckInProgress) ...[
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
          ] else if (c.availableUpdate != null || c.availableGameUpdate != null) ...[
            const Icon(Icons.circle, size: 7, color: GardenTheme.acid), const SizedBox(width: 8),
          ],
          Text('v${c.currentAppVersion}', style: const TextStyle(fontSize: 12)),
        ]),
      )),
      IconButton(tooltip: '关于', onPressed: _showAbout, icon: const Icon(Icons.info_outline_rounded, size: 21)),
    ]),
  );

  Widget _content() => LayoutBuilder(builder: (context, constraints) {
    final padding = constraints.maxWidth < 600 || _shortLandscape ? 18.0 : 28.0;
    return SingleChildScrollView(
      key: PageStorageKey('garden-page-$_page'),
      padding: EdgeInsets.all(padding),
      child: Align(alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!c.initialized) ...[_initialization(), const SizedBox(height: 16)],
            if (c.availableUpdate != null || c.availableGameUpdate != null) ...[
              _updateNotice(), const SizedBox(height: 16),
            ],
            switch (_page) { 0 => _dashboard(), 1 => _resources(), 2 => _logs(), _ => _settings() },
            if (c.importProgress.phase != ImportPhase.idle) ...[
              const SizedBox(height: 18), _progress(),
            ],
            const SizedBox(height: 24),
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 20, runSpacing: 8, children: [
              _text('GARDENDLESS / 为每一次生长，留一片天地。', size: 10, color: GardenTheme.muted),
              _text('LOCAL FIRST  ·  INFINITE POSSIBILITIES', size: 9, color: GardenTheme.muted),
            ]),
          ]),
        ),
      ),
    );
  });

  Widget _initialization() => _panel(Row(children: [
    if (c.busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
    else const Icon(Icons.warning_amber_rounded, color: GardenTheme.coral),
    const SizedBox(width: 14),
    Expanded(child: _text(c.busy ? '正在准备你的花园…' : (c.message ?? '初始化未完成，请重试。'))),
    if (!c.busy) TextButton(onPressed: () => _guard(c.initialize), child: const Text('重试初始化')),
  ]));

  Widget _updateNotice() => Material(
    color: GardenTheme.elevated, borderRadius: BorderRadius.circular(14),
    child: InkWell(onTap: _showUpdates, borderRadius: BorderRadius.circular(14),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(children: [
          const Icon(Icons.auto_awesome_outlined, size: 18, color: GardenTheme.acid),
          const SizedBox(width: 12),
          Expanded(child: _text('有新的版本可以探索', size: 13)),
          const Icon(Icons.arrow_forward_rounded, size: 18),
        ])),
    ),
  );

  Widget _dashboard() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _hero(),
    const SizedBox(height: 18),
    LayoutBuilder(builder: (context, box) {
      final cards = [
        _summary(), _announcementCard(),
      ];
      if (box.maxWidth < 720 || MediaQuery.textScalerOf(context).scale(14) > 21) {
        return Column(children: [cards[0], const SizedBox(height: 14), cards[1]]);
      }
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 6, child: cards[0]), const SizedBox(width: 18), Expanded(flex: 5, child: cards[1]),
      ]));
    }),
  ]);

  Widget _hero() => Container(
    key: const ValueKey('garden-hero'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: GardenTheme.line),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xff1b2a20), Color(0xff101a14), Color(0xff15291b)]),
    ),
    child: LayoutBuilder(builder: (context, box) {
      final short = _shortLandscape;
      final stacked = box.maxWidth < (short ? 520 : 640) || MediaQuery.textScalerOf(context).scale(14) > 21;
      final inset = short ? 18.0 : box.maxWidth < 720 ? 24.0 : 38.0;
      final titleSize = short ? 34.0 : box.maxWidth > 1060 ? 66.0 : 46.0;
      final copy = Padding(padding: EdgeInsets.all(inset),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          _eyebrow('01 / THE VERDANT OBSERVATORY'),
          SizedBox(height: short ? 10 : 22),
          Text('让花园', style: TextStyle(fontSize: titleSize,
            fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -2)),
          Text('永不落幕。', style: TextStyle(fontSize: titleSize,
            fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -2, color: GardenTheme.acid)),
          if (!short) ...[
            const SizedBox(height: 18),
            _text(c.hasCurrentResource ? '你的世界，已经准备好继续生长。' : '带上你的游戏资源，种下无限可能。',
              color: GardenTheme.muted, size: 14),
          ],
          SizedBox(height: short ? 16 : 25),
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              key: const ValueKey('garden-launch'),
              onPressed: _locked ? null : () => _operate(
                c.canStartGame ? c.startGame : c.importResources, launch: c.canStartGame),
              icon: _launching
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: GardenTheme.background))
                : Icon(c.canStartGame ? Icons.play_arrow_rounded : Icons.add_rounded),
              label: Text(_launching ? '正在启动…' : c.canStartGame ? '启动花园' : short ? '导入资源' : '导入资源，开始探索'),
            ),
            if (short) IconButton(tooltip: '管理资源', onPressed: () => _navigate(1), icon: const Icon(Icons.north_east_rounded))
            else TextButton(onPressed: () => _navigate(1), child: const Text('管理资源  ↗')),
          ]),
          if (!short) ...[
            const SizedBox(height: 23),
            _badge(c.hasCurrentResource ? '资源已就绪' : '等待首次导入',
              color: c.hasCurrentResource ? GardenTheme.acid : GardenTheme.muted),
          ],
        ]),
      );
      final art = Stack(children: [
        Positioned.fill(child: GardenScene(motion: _motion)),
        if (!short) Positioned(right: 24, top: 20, child: _text('BOTANICAL SYSTEM\nNO. ∞ / GROW WITHOUT LIMITS', size: 9, color: GardenTheme.muted)),
        if (!short) Positioned(right: 25, bottom: 18, child: _text('生长，不设终点。', size: 11, color: GardenTheme.muted)),
      ]);
      if (stacked) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          copy, SizedBox(height: 300, child: art),
        ]);
      }
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: copy),
        Expanded(flex: 5, child: ConstrainedBox(constraints: BoxConstraints(minHeight: short ? 220 : 395), child: art)),
      ]));
    }),
  );

  Widget _summary() => _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _eyebrow('YOUR COLLECTION / 当前资源'),
    const SizedBox(height: 18),
    Row(children: [
      Container(padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: GardenTheme.elevated, borderRadius: BorderRadius.circular(15)),
        child: const Icon(Icons.grass_rounded, color: GardenTheme.acid, size: 28)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _text(c.hasCurrentResource ? c.detectedTitle : '一座花园，即将诞生', size: 18, weight: FontWeight.w700),
        const SizedBox(height: 5),
        _text(c.hasCurrentResource ? '本地资源 · ${c.currentGameVersion ?? '版本未知'}' : '导入你拥有的 Gardendless ZIP 资源包', color: GardenTheme.muted, size: 12),
      ])),
      IconButton(tooltip: '查看资源详情', onPressed: () => _navigate(1), icon: const Icon(Icons.north_east_rounded, size: 20)),
    ]),
    const SizedBox(height: 20), const Divider(), const SizedBox(height: 16),
    Wrap(spacing: 26, runSpacing: 14, children: [
      _stat('资源文件', c.hasCurrentResource ? '${c.manifest.fileCount}' : '—'),
      _stat('占用空间', c.hasCurrentResource ? _bytes(c.manifest.totalBytes) : '—'),
      _stat('运行模式', c.hasCurrentResource ? c.hasGpNext ? 'GP NEXT' : 'STANDARD' : '未导入'),
    ]),
  ]));

  Widget _announcementCard() => _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: _eyebrow('GARDEN NOTES / 花园来信')),
      const Icon(Icons.north_east_rounded, size: 18, color: GardenTheme.coral)]),
    const SizedBox(height: 17),
    _text(c.announcement?.title ?? '让每一次出发，都轻盈一点。', size: 20, weight: FontWeight.w700),
    const SizedBox(height: 9),
    Text(c.announcement?.message ?? '资源保存在本地。准备好自己的 ZIP 资源包，即可开启花园。加载器不附带游戏资源。',
      maxLines: 3, overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: GardenTheme.muted, fontSize: 13, height: 1.7)),
    const SizedBox(height: 15),
    TextButton(onPressed: _showAnnouncement, child: const Text('阅读花园来信  →')),
  ]));

  Widget _resources() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('02 / COLLECTION', '你的花园资源', '导入、检查、启程。资源状态在这里一目了然。'),
    const SizedBox(height: 24),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.drive_folder_upload_outlined, size: 38, color: GardenTheme.acid),
      const SizedBox(height: 16),
      _text(c.hasCurrentResource ? '为花园带来新的可能' : '从一个 ZIP 开始', size: 25, weight: FontWeight.w700),
      const SizedBox(height: 10),
      _text('选择用户提供的 Gardendless ZIP 资源包。应用会解压、校验并激活资源；导入过程中请勿关闭应用。', color: GardenTheme.muted),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(key: const ValueKey('garden-import'),
          onPressed: _locked ? null : () => _operate(c.importResources),
          icon: const Icon(Icons.add_rounded), label: Text(c.isImporting ? '正在导入…' : '选择 ZIP 资源包')),
        OutlinedButton.icon(onPressed: _locked ? null : () => _operate(c.refresh),
          icon: const Icon(Icons.fact_check_outlined, size: 19), label: const Text('重新检查资源')),
      ]),
    ]), color: const Color(0xff1b2a20)),
    const SizedBox(height: 18),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: _text('资源档案', size: 20, weight: FontWeight.w700)),
        _badge(c.hasCurrentResource ? '已就绪' : '未就绪', color: c.hasCurrentResource ? GardenTheme.acid : GardenTheme.coral)]),
      const SizedBox(height: 18),
      _data('游戏标题', c.hasCurrentResource ? c.detectedTitle : '尚未导入'),
      _data('游戏版本', c.currentGameVersion ?? '未知'),
      _data('资源文件', '${c.manifest.fileCount} 个'),
      _data('占用空间', _bytes(c.manifest.totalBytes)),
      _data('激活槽位', c.manifest.activeSlot?.name ?? '无'),
      _data('导入时间', _date(c.manifest.lastImportAt)),
      _data('检查时间', _date(c.manifest.lastSelfCheckAt)),
      _data('资源目录', c.userVisibleRoot),
      if (c.hasGpNext) _data('GP Next', '${c.gpNextVersion ?? '版本未知'} · ${c.gpNextCompatible ? '兼容' : '需要注意'}'),
      if (c.gpNextCompatibilityError != null) _warning(c.gpNextCompatibilityError!),
      if (!c.currentValidation.isValid && c.currentValidation.errorMessage != null)
        _warning(c.currentValidation.errorMessage!),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => _copy(c.userVisibleRoot, '资源目录已复制'),
        icon: const Icon(Icons.copy_outlined, size: 17), label: const Text('复制资源目录')),
    ])),
  ]);

  Widget _logs() {
    final events = c.logSnapshot?.events.where((event) {
      final level = (event['level'] ?? 'INFO').toString().toUpperCase();
      return (_logLevel == 'ALL' || level == _logLevel) &&
        jsonEncode(event).toLowerCase().contains(_logQuery.toLowerCase());
    }).toList() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('03 / SYSTEM JOURNAL', '听见花园的脉搏', '查看真实运行事件，让每一次排查都有迹可循。'),
      const SizedBox(height: 22),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(onPressed: c.logSnapshotLoading ? null : () => _guard(c.refreshLogs),
          icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(c.logSnapshotLoading ? '正在刷新…' : '刷新日志')),
        OutlinedButton.icon(key: const ValueKey('garden-copy-diagnostics'), onPressed: !c.initialized ? null : () => _guard(() async {
          await c.refreshLogs();
          await _copy(c.buildDiagnosticSummary(), '诊断信息已复制');
        }), icon: const Icon(Icons.copy_outlined, size: 18), label: const Text('复制完整诊断')),
        TextButton(onPressed: _deleteLogs, child: const Text('清理历史日志', style: TextStyle(color: GardenTheme.coral))),
      ]),
      const SizedBox(height: 18),
      TextField(key: const ValueKey('garden-log-search'),
        onChanged: (value) => setState(() => _logQuery = value),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '搜索事件、错误码或关键词…')),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: ['ALL', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].map((level) => ChoiceChip(
        label: Text(level == 'ALL' ? '全部' : level), selected: _logLevel == level,
        onSelected: (_) => setState(() => _logLevel = level),
      )).toList()),
      const SizedBox(height: 18),
      if (c.logSnapshot?.degraded == true) ...[_warning('日志持久化处于降级状态，请复制诊断信息进行排查。'), const SizedBox(height: 14)],
      if (events.isEmpty) _panel(Padding(padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(children: [
          const Icon(Icons.terminal_rounded, size: 34, color: GardenTheme.muted),
          const SizedBox(height: 14), _text(_logQuery.isNotEmpty || _logLevel != 'ALL' ? '没有匹配的事件' : '这里暂时很安静', size: 19),
          const SizedBox(height: 8), _text(c.logSnapshot == null ? '暂无可读取的结构化日志。' : '新的运行事件将在这里出现。', color: GardenTheme.muted),
        ])))
      else _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _eyebrow('${events.length} EVENTS / 匹配事件'),
        const SizedBox(height: 14),
        // Bound UI work for very large snapshots; copied diagnostics stay complete.
        for (final event in events.reversed.take(200)) Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 5, children: [
              _badge((event['level'] ?? 'INFO').toString(), color:
                ['ERROR', 'FATAL'].contains((event['level'] ?? '').toString().toUpperCase()) ? GardenTheme.coral : GardenTheme.mint),
              _text((event['event'] ?? event['category'] ?? 'event').toString(), size: 12, weight: FontWeight.w700),
            ]),
            const SizedBox(height: 8),
            SelectableText(const JsonEncoder.withIndent('  ').convert(event),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: GardenTheme.muted, height: 1.6)),
            const SizedBox(height: 12), const Divider(),
          ]),
        ),
        if (events.length > 200) _text('显示最近 200 条；复制完整诊断可获取全部事件。', color: GardenTheme.muted),
      ])),
    ]);
  }

  Widget _settings() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('04 / PREFERENCES', '按你的方式生长', '保留掌控感，把习惯交给花园。'),
    const SizedBox(height: 24),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('GAME EXPERIENCE / 游戏体验'), const SizedBox(height: 14),
      _switch('自动收集阳光', '在游戏中自动收集阳光；设置将在下次启动游戏时生效。', c.autoCollectSunEnabled,
        _locked ? null : (v) => _operate(() => c.setAutoCollectSunEnabled(v)), key: const ValueKey('garden-auto-sun')),
      const Divider(),
      _switch('游戏水印', '显示游戏内的加载器水印。下次启动游戏时生效。', c.watermarkEnabled,
        _locked ? null : (v) => _operate(() => c.setWatermarkEnabled(v))),
    ])),
    const SizedBox(height: 18),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('INTERFACE / 界面'), const SizedBox(height: 14),
      _switch('场景入场动效', '本次会话有效；系统开启减少动态效果时自动关闭动效。', _motion,
        (v) => setState(() => _motion = v), key: const ValueKey('garden-motion')),
    ])),
    const SizedBox(height: 18),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('ADVANCED / 高级诊断'), const SizedBox(height: 14),
      _switch('详细音频诊断', '仅在排查声音问题时开启，会记录更多音频事件。', c.detailedAudioDiagnosticsEnabled,
        _locked ? null : (v) => _operate(() => c.setDetailedAudioDiagnosticsEnabled(v))),
    ])),
    const SizedBox(height: 18),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('ABOUT / 关于'), const SizedBox(height: 14),
      _text('GardendlessLoader', size: 25, weight: FontWeight.w800),
      const SizedBox(height: 8), _text('加载器 v${c.currentAppVersion} · 本地资源，自由探索。', color: GardenTheme.muted),
      const SizedBox(height: 18),
      Wrap(spacing: 12, runSpacing: 10, children: [
        OutlinedButton(onPressed: _showUpdates, child: const Text('版本与更新')),
        OutlinedButton(onPressed: _showAbout, child: const Text('关于项目')),
        TextButton(onPressed: () => _open(appGithubUrl), child: const Text('GitHub  ↗')),
        TextButton(onPressed: () => _open(bilibiliHomeUrl), child: const Text('Bilibili  ↗')),
      ]),
    ])),
  ]);

  Widget _progress() {
    final p = c.importProgress;
    final done = p.phase == ImportPhase.completed;
    final failed = p.phase == ImportPhase.failed;
    final title = switch (p.phase) {
      ImportPhase.idle => '准备导入', ImportPhase.receiving => '正在接收资源',
      ImportPhase.extracting => '正在解压资源', ImportPhase.validating => '正在校验资源',
      ImportPhase.scanning => '正在扫描文件', ImportPhase.selfChecking => '正在自检',
      ImportPhase.completed => '导入完成，花园已就绪', ImportPhase.failed => '导入未完成',
    };
    return Semantics(liveRegion: true, label: title, child: _panel(
      Column(key: const ValueKey('garden-import-progress'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(done ? Icons.check_circle_outline : failed ? Icons.error_outline : Icons.downloading_rounded,
          color: failed ? GardenTheme.coral : GardenTheme.acid),
          const SizedBox(width: 12), Expanded(child: _text(title, weight: FontWeight.w700)),
          IconButton(tooltip: _progressExpanded ? '折叠进度' : '展开进度',
            onPressed: () => setState(() => _progressExpanded = !_progressExpanded),
            icon: Icon(_progressExpanded ? Icons.expand_less : Icons.expand_more)),
          if (done || failed) IconButton(tooltip: '关闭进度', onPressed: c.dismissImportProgress, icon: const Icon(Icons.close_rounded)),
        ]),
        if (_progressExpanded) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: failed ? 0 : p.value, color: failed ? GardenTheme.coral : GardenTheme.acid,
            backgroundColor: GardenTheme.line, minHeight: 5, borderRadius: BorderRadius.circular(5)),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 8, children: [
            _text(p.value == null ? '处理中' : '${(p.value! * 100).round()}%', size: 12),
            _text('${p.copiedFiles} / ${p.totalFiles > 0 ? p.totalFiles : '—'} 个文件', size: 12, color: GardenTheme.muted),
            _text('${_bytes(p.copiedBytes)} / ${p.totalBytes > 0 ? _bytes(p.totalBytes) : '—'}', size: 12, color: GardenTheme.muted),
            if (p.bytesPerSecond > 0) _text('${_bytes(p.bytesPerSecond.round())}/s', size: 12, color: GardenTheme.muted),
            _text('已用时 ${p.elapsed.inSeconds}s', size: 12, color: GardenTheme.muted),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 14, runSpacing: 8, children: List.generate(4, (i) => _text(
            '${i + 1}  ${['接收', '解压', '校验', '自检'][i]}', size: 11,
            color: !failed && p.stepIndex >= i + 1 ? GardenTheme.acid : GardenTheme.muted))),
          if (p.message != null) ...[const SizedBox(height: 12), _text(p.message!, color: failed ? GardenTheme.coral : GardenTheme.muted, size: 12)],
          if (failed) ...[const SizedBox(height: 12), Align(alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _locked ? null : () => _operate(c.importResources), child: const Text('重新选择资源包')))],
        ],
      ]),
    ));
  }

  Future<void> _dialog(String title, Widget Function(BuildContext) content) => showDialog<void>(
    context: context,
    builder: (context) => Theme(data: GardenTheme.dark, child: AnimatedBuilder(
      animation: c,
      builder: (context, _) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: content(context))),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
      ),
    )),
  );

  void _showAbout() => unawaited(_dialog('关于 GardendlessLoader', (_) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _text(c.aboutContent.content, size: 15), const SizedBox(height: 20),
      _text('VERDANT OBSERVATORY\n原创植物观测站界面 · 本地优先', color: GardenTheme.muted, size: 12),
      const SizedBox(height: 12),
      TextButton(onPressed: () => _open(appGithubUrl), child: const Text('访问加载器项目  ↗')),
    ],
  )));

  void _showAnnouncement() => unawaited(_dialog(c.announcement?.title ?? '花园来信', (_) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _text(c.announcement?.message ?? '暂时没有公告。加载器不附带游戏资源，请使用自己提供的资源包。'),
      const SizedBox(height: 18),
      for (final link in c.announcement?.links ?? <AnnouncementLink>[])
        TextButton(onPressed: () => _open(link.url), child: Text('${link.label}  ↗')),
      TextButton(onPressed: () => _guard(c.refreshAnnouncement), child: const Text('刷新公告')),
    ],
  )));

  void _showUpdates() => unawaited(_dialog('版本与更新', (_) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _data('加载器版本', c.currentAppVersion),
      _data('本地游戏版本', c.currentGameVersion ?? '未知 / 未导入'),
      _data('已知稳定版', c.latestGameVersion ?? '尚未获取'),
      const SizedBox(height: 16),
      if (c.availableUpdate case final update?) ...[
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _eyebrow('LOADER UPDATE'), const SizedBox(height: 12),
          _text('${update.currentVersion} → ${update.latestVersion}', size: 22, weight: FontWeight.w700),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: () => _open(appCloudDriveUpdateUrl), child: const Text('网盘更新')),
            OutlinedButton(onPressed: () => _open(update.releaseUrl), child: const Text('GitHub Release  ↗')),
            TextButton(onPressed: () => c.deferUpdate(update), child: const Text('稍后提醒')),
          ]),
        ])), const SizedBox(height: 14),
      ],
      if (c.availableGameUpdate case final update?) ...[
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _eyebrow('GAME UPDATE'), const SizedBox(height: 12),
          _text('${update.currentVersion} → ${update.latestVersion}', size: 22, weight: FontWeight.w700),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => _open(githubUrl), child: const Text('查看游戏项目  ↗')),
            TextButton(onPressed: () => c.deferGameUpdate(update), child: const Text('稍后提醒')),
          ]),
        ])), const SizedBox(height: 14),
      ],
      OutlinedButton.icon(onPressed: c.updateCheckInProgress ? null : () => _guard(c.checkForUpdates),
        icon: const Icon(Icons.sync_rounded), label: Text(c.updateCheckInProgress ? '正在检查…' : '检查更新')),
    ],
  )));

  Future<void> _deleteLogs() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => Theme(
      data: GardenTheme.dark, child: AlertDialog(
        title: const Text('清理历史日志？'),
        content: const Text('只删除已经结束的历史 Session，当前运行日志会保留。此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认清理')),
        ],
      ),
    ));
    if (confirmed == true && mounted) {
      await _guard(c.deleteLogHistory);
    }
  }

  Widget _switch(String title, String subtitle, bool value, ValueChanged<bool>? onChanged, {Key? key}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _text(title, size: 17, weight: FontWeight.w600), const SizedBox(height: 7),
      _text(subtitle, size: 12, color: GardenTheme.muted),
    ])), const SizedBox(width: 20), Semantics(label: title,
      child: Switch(key: key, value: value, onChanged: onChanged))]),
  );

  Widget _data(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 112, child: _text(label, size: 12, color: GardenTheme.muted)),
      const SizedBox(width: 10), Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13, height: 1.6))),
    ]),
  );

  Widget _warning(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: GardenTheme.coral, size: 18), const SizedBox(width: 10),
      Expanded(child: _text(text, color: GardenTheme.coral, size: 12)),
    ]));

  Widget _heading(String index, String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow(index), const SizedBox(height: 14),
      _text(title, size: 34, weight: FontWeight.w800), const SizedBox(height: 10),
      _text(description, color: GardenTheme.muted),
    ],
  );

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _text(value, size: 18, weight: FontWeight.w700), const SizedBox(height: 4),
    _text(label, size: 10, color: GardenTheme.muted),
  ]);

  Widget _badge(String label, {Color color = GardenTheme.acid}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
    child: Text('•  $label', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _panel(Widget child, {Color color = GardenTheme.panel}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22), border: Border.all(color: GardenTheme.line)),
    child: child,
  );

  Widget _eyebrow(String value) => Text(value, style: const TextStyle(
    color: GardenTheme.mint, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.6, height: 1.6));

  Widget _text(String value, {double size = 14, Color color = GardenTheme.ink, FontWeight weight = FontWeight.w400}) =>
    Text(value, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.55));

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _date(DateTime? value) {
    if (value == null) return '—';
    final date = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
}
