import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game_host/game_host.dart';
import '../models.dart';
import '../services/app_settings_store.dart';

/// A text with its Chinese and English wording.
class LocalizedText {
  const LocalizedText(this.zh, this.en);

  final String zh;
  final String en;

  String of(AppStrings strings) => strings.isChinese ? zh : en;
}

/// Launcher text in the active language. Widgets read it with
/// [AppStrings.of]; code without a BuildContext reads [current], which the
/// controller keeps in sync with the language setting.
class AppStrings {
  const AppStrings._(this.isChinese);

  static const chinese = AppStrings._(true);
  static const english = AppStrings._(false);

  static AppStrings current = resolve(
    LanguagePreference.system,
    PlatformDispatcher.instance.locales,
  );

  static const supportedLocales = [Locale('zh'), Locale('en')];
  static const LocalizationsDelegate<AppStrings> delegate = _Delegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

  /// The first Chinese or English entry among the system languages decides;
  /// any other system language gets English.
  static AppStrings resolve(
    LanguagePreference preference,
    List<Locale> systemLocales,
  ) {
    return switch (preference) {
      LanguagePreference.chinese => chinese,
      LanguagePreference.english => english,
      LanguagePreference.system =>
        systemLocales.map((locale) => locale.languageCode).firstWhere(
                      (code) => code == 'zh' || code == 'en',
                      orElse: () => 'en',
                    ) ==
                'zh'
            ? chinese
            : english,
    };
  }

  final bool isChinese;

  Locale get locale => isChinese ? const Locale('zh') : const Locale('en');

  String _t(String zh, String en) => isChinese ? zh : en;

  // Navigation and shell.
  String get navGame => _t('游戏', 'Play');
  String get navResources => _t('资源', 'Resources');
  String get navLogs => _t('日志', 'Logs');
  String get navSettings => _t('设置', 'Settings');
  String loaderVersion(String version) =>
      _t('加载器 v$version', 'Loader v$version');
  String get checking => _t('检查中', 'Checking');
  String get checkForUpdates => _t('检查更新', 'Check for updates');
  String get announcement => _t('公告', 'Announcement');
  String get noAnnouncement => _t('暂无公告。', 'No announcement.');
  String get close => _t('关闭', 'Close');
  String get cancel => _t('取消', 'Cancel');
  String get delete => _t('删除', 'Delete');
  String get copy => _t('复制', 'Copy');
  String get none => _t('无', 'None');
  String get unknown => _t('未知', 'Unknown');
  String get remindLater => _t('稍后提醒', 'Remind me later');
  String get bilibiliHome => _t('B站主页', 'Bilibili');
  String get technicalDetails => _t('技术详情', 'Technical details');

  // Toasts and dialogs owned by the home page.
  String cannotStartGame(String reason) =>
      _t('无法启动游戏：$reason', 'Cannot start the game: $reason');
  String get resourceRootCopied =>
      _t('资源根目录已复制', 'Resource folder path copied');
  String get diagnosticsCopied => _t('日志信息已复制', 'Diagnostics copied');
  String get logEventCopied => _t('单条事件 JSON 已复制', 'Event JSON copied');
  String get deleteLogHistoryTitle => _t('删除历史日志？', 'Delete log history?');
  String get deleteLogHistoryMessage => _t(
        '只会删除已经结束的历史 Session，当前运行日志会保留。',
        'Only finished sessions are deleted; the current session log is kept.',
      );

  // Play page.
  String get resourcesReady => _t('资源已就绪', 'Resources ready');
  String get resourcesNeeded => _t('需要导入资源', 'Resources needed');
  String gameVersionLabel(String? version) =>
      _t('版本 ${version ?? '未知'}', 'Version ${version ?? 'unknown'}');
  String get standardWeb => _t('标准 Web', 'Standard Web');
  String get gpNextIncompatibleShort =>
      _t('GP-Next 不兼容', 'GP-Next incompatible');
  String get importToPlayHint => _t(
        '导入一份 Gardendless Web 资源 ZIP 后即可开始游戏。',
        'Import a Gardendless web resource ZIP to start playing.',
      );
  String get starting => _t('正在启动…', 'Starting…');
  String get startGame => _t('开始游戏', 'Start Game');
  String get goToImport => _t('前往导入资源', 'Import resources');

  // Resources page: import.
  String get importResources => _t('导入资源', 'Import Resources');
  String get updateResources => _t('更新资源', 'Update Resources');
  String get importDescription => _t(
        '选择 Gardendless Web 资源 ZIP，支持标准 Cocos 构建、GP-Next 构建与移动端优化包。'
            '新资源写入空闲槽，校验和自检通过后才会切换；失败或取消不影响当前资源。',
        'Choose a Gardendless web resource ZIP: standard Cocos builds, '
            'GP-Next builds and mobile-optimized packages are supported. New '
            'resources go to the idle slot and are switched in only after '
            'validation and the self-check pass; a failure or cancel leaves '
            'the current resources untouched.',
      );
  String get importing => _t('导入中…', 'Importing…');
  String get chooseZipToUpdate => _t('选择 ZIP 更新', 'Select ZIP to update');
  String get chooseZipToImport => _t('选择 ZIP 导入', 'Select ZIP to import');
  List<String> get importSteps => isChinese
      ? const ['读取', '解压', '校验', '自检']
      : const ['Read', 'Extract', 'Validate', 'Self-check'];
  String importFailedTitle(String reason) =>
      _t('导入失败 · $reason', 'Import failed · $reason');
  String get importCompletedTitle => _t('导入完成 100%', 'Import complete 100%');
  String importStepTitle(int step, int count, String message) =>
      _t('步骤 $step/$count · $message', 'Step $step/$count · $message');
  String get collapseProgressDetails => _t('收起进度详情', 'Hide progress details');
  String get expandProgressDetails => _t('展开进度详情', 'Show progress details');
  String get dismissFailure => _t('关闭失败提示', 'Dismiss failure');
  String get dismissCompletion => _t('关闭完成提示', 'Dismiss');
  String get files => _t('文件', 'Files');
  String get dataSize => _t('数据量', 'Data');
  String get speed => _t('速度', 'Speed');
  String get elapsed => _t('已用时间', 'Elapsed');

  String importPhase(ImportPhase phase) => switch (phase) {
        ImportPhase.receiving => _t('正在读取 ZIP', 'Reading ZIP'),
        ImportPhase.extracting => _t('正在解压资源', 'Extracting resources'),
        ImportPhase.validating => _t('正在校验资源', 'Validating resources'),
        ImportPhase.scanning => _t('正在统计资源', 'Counting resources'),
        ImportPhase.selfChecking => _t('正在本地自检', 'Running self-check'),
        ImportPhase.completed => _t('导入完成', 'Import complete'),
        ImportPhase.failed => _t('导入失败', 'Import failed'),
        ImportPhase.idle => _t('等待导入', 'Waiting for import'),
      };

  // Resources page: game version.
  String get gameVersion => _t('游戏版本', 'Game Version');
  String get updateAvailable => _t('有新版本', 'Update available');
  String get latestNotFetched => _t('尚未获取最新版本', 'Latest not fetched');
  String get stableAvailable => _t('可获取稳定版', 'Stable release available');
  String get upToDate => _t('已是最新', 'Up to date');
  String get currentLabel => _t('当前', 'Current');
  String get latestStable => _t('最新稳定版', 'Latest stable');
  String get githubDownload => _t('GitHub 下载', 'GitHub download');
  String get cloudDriveDownload => _t('网盘下载', 'Cloud drive download');
  List<String> get downloadNotes => isChinese
      ? const [
          'GitHub 下载是官方渠道，但部分地区可能无法访问。',
          '网盘中的游戏资源由加载器作者自行上传，与 PvZ2 Gardendless 官方无关，仅为方便大家下载。',
          '网盘更新可能晚于官方，如果迟迟没有更新，欢迎到 B 站提醒作者。',
        ]
      : const [
          'GitHub is the official source, but it may be unreachable in some '
              'regions.',
          'The cloud drive copy is uploaded by the loader author for '
              'convenience and is not affiliated with PvZ2 Gardendless.',
          'The cloud drive may lag behind official releases; feel free to '
              'remind the author on Bilibili.',
        ];

  // Resources page: current resource.
  String get currentResource => _t('当前资源', 'Current Resources');
  String get slotA => _t('槽 A', 'Slot A');
  String get slotB => _t('槽 B', 'Slot B');
  String get noActiveSlot => _t('无激活槽', 'No active slot');
  String get notRun => _t('未执行', 'Not run');
  String get waitingForImport => _t('等待导入', 'Waiting for import');
  String passedAt(String time) => _t('已通过 · $time', 'Passed · $time');
  String get gpNextNotDetected =>
      _t('未检测到（标准 Web 构建）', 'Not detected (standard web build)');
  String gpNextCompatible(String version) =>
      _t('兼容 $version', 'Compatible $version').trim();
  String get gpNextIncompatible => _t('不兼容', 'Incompatible');
  String get fileCount => _t('文件数', 'Files');
  String get size => _t('体积', 'Size');
  String get importedAt => _t('导入时间', 'Imported');
  String get title => _t('标题', 'Title');
  String get notImported => _t('尚未导入', 'Not imported');
  String get noTitleDetected => _t('未检测到标题', 'No title detected');
  String get validation => _t('资源校验', 'Validation');
  String get validationPassed => _t('校验通过', 'Passed');
  String get gameHost => _t('游戏宿主', 'Game host');
  String noHttpServer(String host) =>
      _t('$host · 无 HTTP Server', '$host · no HTTP server');
  String get lastSelfCheck => _t('上次自检', 'Last self-check');
  String get recentError => _t('最近错误', 'Recent error');
  String get resourceRoot => _t('资源根目录', 'Resource folder');

  // Settings page: loader.
  String get noUpdate => _t('无可用更新', 'No update');
  String get currentVersion => _t('当前版本', 'Current');
  String get latestVersion => _t('最新版本', 'Latest');
  String get autoCheckHint => _t(
        '进入启动器时会自动检查，也可以点右上角的刷新图标手动检查。',
        'Checked automatically when the launcher opens; tap the refresh icon '
            'at the top right to check now.',
      );
  String get cloudDriveUpdate => _t('网盘更新', 'Update from cloud drive');
  String get viewGithubRelease => _t('查看 GitHub Release', 'GitHub release');

  // Settings page: launch preferences.
  String get launchPreferences => _t('启动偏好', 'Launch Preferences');
  String get appliesNextLaunch => _t('下次启动生效', 'Applies next launch');
  String get quickLaunch => _t('快速启动', 'Quick launch');
  String get quickLaunchSubtitle => _t(
        '打开应用时直接进入游戏，点击游戏左下角 X 返回加载器',
        'Open the game directly when the app starts; tap the X at the '
            'bottom left of the game to return to the loader',
      );
  String get autoCollectSun => _t('自动收集', 'Auto Collect Sun');
  String get autoCollectSunSubtitle => _t(
        '游戏中约每 3 秒模拟一次 A 键，暂停、后台或输入时不触发',
        'Presses A about every 3 seconds in play; skipped while paused, in '
            'the background or typing',
      );
  String get renderResolution => _t('渲染分辨率', 'Render resolution');
  String get renderResolutionSubtitle => _t(
        '按屏幕原生分辨率的百分比渲染游戏画面，百分比越低越省显存，画面也越模糊',
        'Renders the game at a percentage of the screen\'s native resolution; '
            'a lower percentage uses less GPU memory and looks softer',
      );
  String renderResolutionLabel(RenderResolution resolution) =>
      switch (resolution) {
        RenderResolution.full => '100%',
        RenderResolution.medium => '75%',
        RenderResolution.low => '50%',
      };
  String get screenFit => _t('画面比例', 'Screen fit');
  String get screenFitSubtitle => _t(
        '均衡比例裁掉少量画面换取更小的黑边；完整显示显示全部画面，黑边更大；'
            '强制拉伸铺满屏幕，但可能造成画面变形',
        'Balanced trims a little of the picture for smaller black bars; Show '
            'all shows the whole picture with larger bars; Stretch fills the '
            'screen but can distort the picture',
      );
  String screenFitLabel(ScreenFit fit) => switch (fit) {
        ScreenFit.balanced => _t('均衡比例', 'Balanced'),
        ScreenFit.showAll => _t('完整显示', 'Show all'),
        ScreenFit.stretch => _t('强制拉伸', 'Stretch'),
      };
  String get watermark => _t('游戏水印', 'Watermark');
  String get watermarkSubtitle => _t(
        '在游戏画面角落显示加载器标识',
        'Show the loader name in a corner of the game',
      );

  // Settings page: appearance.
  String get appearance => _t('外观', 'Appearance');
  String get theme => _t('主题', 'Theme');
  String get followSystem => _t('跟随系统', 'System');
  String get lightTheme => _t('浅色', 'Light');
  String get darkTheme => _t('深色', 'Dark');
  String get language => _t('语言', 'Language');
  String get reduceMotion => _t('减少动效', 'Reduce motion');
  String get reduceMotionSubtitle => _t(
        '关闭按压缩放与切换过渡；系统的减少动态效果设置同样生效',
        'Turns off press scaling and transitions; the system Reduce Motion '
            'setting also applies',
      );

  // Settings page: about and guide.
  String get aboutTitle =>
      _t('关于 GardendlessLoader', 'About GardendlessLoader');
  String get loaderGithub => _t('加载器 GitHub', 'Loader on GitHub');
  String get upstreamGithub => _t('上游游戏 GitHub', 'Upstream game on GitHub');
  String get guide => _t('使用说明', 'How to Play');
  List<(String, String)> get gestures => isChinese
      ? const [
          ('单指轻点或拖动', '鼠标左键点击或拖动'),
          ('双指轻点', '双指中心执行右键点击'),
          ('双指滑动', '模拟鼠标滚轮'),
          ('三指及以上', '取消当前触摸映射'),
          ('实体鼠标和键盘', '交由系统 WebView 原生处理'),
        ]
      : const [
          ('One-finger tap or drag', 'Left click or drag'),
          ('Two-finger tap', 'Right click between the fingers'),
          ('Two-finger swipe', 'Mouse wheel'),
          ('Three or more fingers', 'Cancel the current touch'),
          ('Physical mouse and keyboard', 'Handled by the system WebView'),
        ];
  List<String> get guideTips => isChinese
      ? const [
          '返回启动器：Android / 鸿蒙使用系统返回，iOS 从屏幕左边缘右滑。',
          '存档导入导出、GP-Next 补丁与 Mod 安装都在游戏内完成，使用系统文件选择器。',
          'JS Modding 由游戏内 GP-Next 管理；Mod 会在游戏中执行代码，请只安装可信来源的 Mod。',
        ]
      : const [
          'Back to the launcher: use system Back on Android / HarmonyOS, or '
              'swipe right from the left edge on iOS.',
          'Save import/export, GP-Next patches and Mod installs all happen '
              'in the game through the system file picker.',
          'JS Modding is managed by GP-Next in the game; Mods run code in '
              'the game, so only install Mods from sources you trust.',
        ];

  // Logs page.
  String get errorsOnly => _t('只看错误', 'Errors only');
  String get filterByOperation => _t('按 Operation 筛选', 'Filter by operation');
  String get allOperations => _t('全部 Operation', 'All operations');
  String get clearFilters => _t('清空筛选', 'Clear filters');
  String get refreshLogs => _t('刷新日志', 'Refresh logs');
  String get copyDiagnostics => _t('复制诊断', 'Copy diagnostics');
  String get deleteHistory => _t('删除历史', 'Delete history');
  String get logStatusUnknown => _t('日志状态未知', 'Log status unknown');
  String get logPersisting => _t('持久化正常', 'Persisting');
  String get logDegraded => _t('内存降级', 'Memory only');
  String get overview => _t('概览', 'Overview');
  String get appSession => _t('当前会话', 'App session');
  String get gameSession => _t('游戏会话', 'Game session');
  String get logSize => _t('日志占用', 'Log size');
  String get writeFailures => _t('写入失败', 'Write failures');
  String dropped(String counts) => _t('丢弃 $counts', 'Dropped $counts');
  String get detailedAudioDiagnostics =>
      _t('详细音频诊断', 'Detailed audio diagnostics');
  String get detailedAudioDiagnosticsSubtitle => _t(
        '下一次启动游戏时采集音频加载与播放事件',
        'Records audio loading and playback events on the next game launch',
      );
  String get readingLogs => _t('正在读取日志…', 'Reading logs…');
  String get logsNotLoaded => _t('日志尚未加载', 'Logs not loaded');
  String get noMatchingEvents =>
      _t('当前筛选条件下没有事件', 'No events match the filters');
  String get copyEventJson => _t('复制单条事件 JSON', 'Copy event JSON');

  // Import confirmations.
  String get backUpSaveTitle =>
      _t('更新前建议先备份存档', 'Back up your save before updating');
  String get backUpSaveMessage => _t(
        '存档保存在游戏里，更新资源不会删除它；但新版本可能改写存档，出错时也可能损坏它。'
            '建议先进入游戏导出存档，再更新资源。',
        'Your save lives in the game, and updating resources does not delete '
            'it. A new version may still rewrite it, and an error could '
            'corrupt it, so export your save in the game before updating.',
      );
  String get continueImport => _t('继续选择 ZIP', 'Continue');
  String importZipTitle(String name) => _t('导入 $name？', 'Import $name?');
  String updateWithZipTitle(String name) =>
      _t('用 $name 更新资源？', 'Update resources with $name?');
  String get importZipMessage => _t(
        '将把这个 ZIP 作为游戏资源导入。',
        'This ZIP will be imported as the game resources.',
      );
  String get import => _t('导入', 'Import');

  // Controller notices.
  String get openingFilePicker =>
      _t('正在打开系统文件选择器', 'Opening the system file picker');
  String get zipSelectionCancelled =>
      _t('已取消选择 ZIP', 'ZIP selection cancelled');
  String get importSucceeded => _t('导入成功', 'Import succeeded');
  String get importSucceededCleanupDeferred => _t(
        '导入成功，旧槽清理将在下次启动重试',
        'Import succeeded; the old slot is cleaned up on the next start',
      );
  String get updateCheckFailedBoth => _t(
        '加载器和游戏更新检查失败，请稍后重试',
        'Could not check loader and game updates; try again later',
      );
  String get updateCheckFailedLoader => _t(
        '加载器更新检查失败，请稍后重试',
        'Could not check for loader updates; try again later',
      );
  String get updateCheckFailedGame => _t(
        '游戏更新检查失败，请稍后重试',
        'Could not check for game updates; try again later',
      );
  String loaderLatestGameUnknown(
    String appVersion,
    bool hasResource,
    String? latestGame,
  ) =>
      isChinese
          ? '加载器 v$appVersion 已是最新；'
              '${hasResource ? '游戏版本未知' : '游戏资源尚未导入'}，当前稳定版 $latestGame'
          : 'Loader v$appVersion is up to date; '
              '${hasResource ? 'the game version is unknown' : 'no game resources are imported'}'
              ', latest stable is $latestGame';
  String loaderLatestGameAhead(
    String appVersion,
    String game,
    String? latestGame,
  ) =>
      _t(
        '加载器 v$appVersion 已是最新；本地游戏 $game 高于公开稳定版 $latestGame',
        'Loader v$appVersion is up to date; local game $game is newer than '
            'the public stable $latestGame',
      );
  String bothUpToDate(String appVersion, String game) => _t(
        '加载器 v$appVersion 与游戏 $game 均为最新版',
        'Loader v$appVersion and game $game are both up to date',
      );

  // Garden journal: play time and version rings.
  String lastPlayed(DateTime at, Duration duration) => _t(
        '上次游玩 ${relativeTime(at)} · ${playDuration(duration)}',
        'Last played ${relativeTime(at)} · ${playDuration(duration)}',
      );
  String totalPlayed(Duration duration) =>
      _t('累计 ${playDuration(duration)}', '${playDuration(duration)} in total');
  String playDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0 && minutes == 0) return _t('不到 1 分钟', 'under a minute');
    if (hours == 0) return _t('$minutes 分钟', '$minutes min');
    if (minutes == 0) return _t('$hours 小时', '$hours h');
    return _t('$hours 小时 $minutes 分钟', '$hours h $minutes min');
  }

  /// Today and yesterday by name with the time, other days by date.
  String relativeTime(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    if (days == 0) return _t('今天 $time', 'today at $time');
    if (days == 1) return _t('昨天 $time', 'yesterday at $time');
    return shortDate(local);
  }

  String shortDate(DateTime at) {
    final local = at.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final thisYear = local.year == DateTime.now().year;
    return isChinese
        ? '${thisYear ? '' : '${local.year}年'}${local.month}月${local.day}日'
        : '${months[local.month - 1]} ${local.day}'
            '${thisYear ? '' : ', ${local.year}'}';
  }

  String get versionRings => _t('版本年轮', 'Version rings');
  String importCount(int count) => _t(
        '$count 次导入',
        count == 1 ? '1 import' : '$count imports',
      );

  // Version moments.
  String get downgradeTitle =>
      _t('这个资源包的版本更旧', 'This package is an older version');
  String downgradeMessage(String current, String incoming) => _t(
        '当前游戏是 $current，这个资源包是 $incoming。旧版本可能读不了新版本写过的存档。'
            '建议先取消，进入游戏导出存档后再导入。',
        'The current game is $current and this package is $incoming. An '
            'older version may not read a save written by a newer one. '
            'Cancel, export your save in the game, then import again.',
      );
  String get importAnyway => _t('仍然导入', 'Import anyway');
  String get downgradeDeclined => _t(
        '已取消导入，当前游戏保持不变',
        'Import cancelled; the current game is unchanged',
      );
  String upgradedTitle(String version) =>
      _t('已升级到 $version', 'Updated to $version');
  String get releaseNotes => _t('更新说明', 'Release notes');

  // One tip shown while an import runs.
  List<String> get importTips => isChinese
      ? const [
          '双指轻点就是右键，双指上下滑动可以滚动。',
          '画面卡顿或游戏闪退？试试把设置里的渲染分辨率调到 75%。',
          '黑边太宽或画面被裁？设置里的画面比例可以换成完整显示或强制拉伸。',
          '打开自动收集后，关卡中约每 3 秒自动收一次阳光。',
          '更新资源不会删除存档、补丁和 Mod，不过更新前导出一次存档更安心。',
          'JS Mod 会在游戏里执行代码，只安装可信来源的 Mod。',
          '打开快速启动，下次打开应用就直接进入游戏。',
          'iOS 从屏幕左边缘右滑，Android 和鸿蒙用系统返回，就能回到加载器。',
          '遇到问题时，到日志页复制诊断，反馈时附上它。',
          '加载器的图标好像藏着什么……多点几下试试？',
        ]
      : const [
          'A two-finger tap is a right click; swipe with two fingers to '
              'scroll.',
          'Stutters or crashes? Try setting Render resolution to 75%.',
          'Black bars too wide or picture cut off? Change Screen fit to Show '
              'all or Stretch.',
          'With Auto Collect Sun on, sun is collected about every 3 seconds '
              'in a level.',
          'Updating resources keeps your save, patches and Mods, but exporting '
              'the save first is safer.',
          'JS Mods run code in the game; only install Mods you trust.',
          'Turn on Quick launch to go straight into the game next time.',
          'Swipe right from the left edge on iOS, or use system Back on '
              'Android and HarmonyOS, to return to the launcher.',
          'When something goes wrong, copy the diagnostics on the Logs page '
              'and attach them to your report.',
          'The launcher icon seems to hide something... try tapping it a few '
              'times?',
        ];

  // Gesture hint shown over the game on the first launch.
  List<String> gestureHintLines(GameHostPlatform platform) => [
        for (final (gesture, mapping) in gestures.take(3))
          '$gesture → $mapping',
        platform == GameHostPlatform.ios
            ? _t('从屏幕左边缘右滑 → 返回加载器',
                'Swipe right from the left edge → back to the launcher')
            : _t('系统返回 → 返回加载器', 'System Back → back to the launcher'),
      ];

  // Tool shed, found by tapping the launcher icon seven times.
  String toolShedTapsLeft(int count) => _t(
        '再点 $count 次…',
        count == 1 ? '1 more tap…' : '$count more taps…',
      );
  String get toolShedFound => _t('你发现了工具棚 🪴', 'You found the tool shed 🪴');
  String get toolShedHidden => _t('工具棚已收起', 'Tool shed put away');
  String get toolShed => _t('工具棚', 'Tool shed');
  String get toolShedIntro => _t(
        '藏在花园角落的维护工具，排查问题时再用。',
        'Maintenance tools tucked in a corner of the garden, for tracking '
            'down problems.',
      );
  String get touchTrace => _t('触摸轨迹记录', 'Touch trace');
  String get touchTraceSubtitle => _t(
        '下一次启动游戏时，把触摸输入与映射结果写入日志（game.touch）',
        'Writes touch input and how it was mapped to the logs (game.touch) '
            'on the next game launch',
      );
  String get localData => _t('本地数据', 'Local data');
  String get hideToolShed => _t('收起工具棚', 'Put the tool shed away');
}

class _Delegate extends LocalizationsDelegate<AppStrings> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppStrings> load(Locale locale) => SynchronousFuture(
        locale.languageCode == 'zh' ? AppStrings.chinese : AppStrings.english,
      );

  @override
  bool shouldReload(_Delegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
