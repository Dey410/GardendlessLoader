import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../services/auto_sun_collector.dart';
import '../services/game_download_service.dart';
import '../web/collect_sunlight_key_press.dart';
import '../web/export_download_patch.dart';
import '../web/touch_patch.dart';
import 'launcher_visuals.dart';

const gameWatermarkText = '本加载器B站xiaozhu_410免费分享，仅供学习，严禁售卖';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  late final AutoSunCollector _autoSunCollector;
  late final GameDownloadService _downloadService;
  bool _autoCollectSunlightEnabled = false;
  bool _resumeReloadNotified = false;

  @override
  void initState() {
    super.initState();
    _autoSunCollector = AutoSunCollector(
      onPressCollectKey: _pressCollectSunlightKey,
    );
    _downloadService = GameDownloadService();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSunCollector.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showMenu();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GameViewportFrame(
                showWatermark: widget.controller.watermarkEnabled,
                child: InAppWebView(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: gardendlessExportDownloadPatchSource,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                    UserScript(
                      source: gardendlessTouchPatchSource,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                  ]),
                  initialUrlRequest: URLRequest(
                    url: WebUri('$localOrigin/index.html'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    transparentBackground: false,
                    supportZoom: false,
                    builtInZoomControls: false,
                    displayZoomControls: false,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    disableContextMenu: true,
                    useShouldOverrideUrlLoading: true,
                    useShouldInterceptRequest: true,
                    useOnDownloadStart: true,
                    allowFileAccess: false,
                    allowContentAccess: false,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    controller.addJavaScriptHandler(
                      handlerName: gardendlessExportDownloadHandlerName,
                      callback: (args) {
                        if (args.isNotEmpty) {
                          unawaited(_handlePatchedDownload(args.first));
                        }
                        return {'accepted': true};
                      },
                    );
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final url = action.request.url;
                    if (_isLocalUrl(url)) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    if (_isInlineDownloadUrl(url)) {
                      unawaited(_handleInlineDownloadUrl(url!));
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (_isGitHubUrl(url)) {
                      final browser = ChromeSafariBrowser();
                      await browser.open(url: url);
                    }
                    return NavigationActionPolicy.CANCEL;
                  },
                  shouldInterceptRequest: (controller, request) async {
                    if (_isLocalUrl(request.url)) {
                      return null;
                    }
                    return WebResourceResponse(
                      statusCode: 204,
                      reasonPhrase: 'No Content',
                      contentType: 'text/plain',
                      data: Uint8List(0),
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.DENY,
                    );
                  },
                  onDownloadStartRequest: _handleDownloadStart,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LauncherVisuals.workbenchGradient(context),
                        border: Border.all(
                          color: LauncherVisuals.glassBorder(context),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          key: const ValueKey('game-menu-button'),
                          tooltip: '游戏菜单',
                          onPressed: _showMenu,
                          icon: Icon(
                            Icons.tune_rounded,
                            color: LauncherVisuals.primaryText(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleResume() async {
    final restarted = await widget.controller.ensureServerAfterResume();
    if (!mounted || !restarted) {
      return;
    }
    await _webViewController?.reload();
    if (!mounted) {
      return;
    }
    if (!_resumeReloadNotified) {
      _resumeReloadNotified = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地 server 已重启，游戏页面已重新加载')),
      );
    }
  }

  bool _isLocalUrl(WebUri? url) {
    return url != null &&
        url.scheme == 'http' &&
        url.host == localServerHost &&
        url.port == localServerPort;
  }

  bool _isGitHubUrl(WebUri? url) {
    return url != null &&
        (url.host == 'github.com' || url.host.endsWith('.github.com'));
  }

  bool _isInlineDownloadUrl(WebUri? url) {
    return url != null && (url.scheme == 'blob' || url.scheme == 'data');
  }

  Future<void> _showMenu() async {
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      barrierLabel: '游戏菜单',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) => StatefulBuilder(
        builder: (context, setDialogState) => GameMenuOverlay(
          onContinue: () => Navigator.of(dialogContext).pop(),
          child: GameMenuDialog(
            autoCollectSunlightEnabled: _autoCollectSunlightEnabled,
            onAutoCollectSunlightChanged: (enabled) {
              _setAutoCollectSunlightEnabled(enabled);
              setDialogState(() {});
            },
            watermarkEnabled: widget.controller.watermarkEnabled,
            onWatermarkChanged: (enabled) {
              unawaited(_setWatermarkEnabled(enabled));
              setDialogState(() {});
            },
            onContinue: () => Navigator.of(dialogContext).pop(),
            onReturnHome: () {
              Navigator.of(dialogContext).pop();
              unawaited(_confirmReturnHome());
            },
            onReload: () {
              Navigator.of(dialogContext).pop();
              unawaited(_confirmReload());
            },
            onDiagnostics: () {
              Navigator.of(dialogContext).pop();
              unawaited(_showDiagnostics());
            },
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  void _setAutoCollectSunlightEnabled(bool enabled) {
    if (_autoCollectSunlightEnabled == enabled) {
      return;
    }

    setState(() {
      _autoCollectSunlightEnabled = enabled;
    });
    _autoSunCollector.setEnabled(enabled);
  }

  Future<void> _setWatermarkEnabled(bool enabled) async {
    final persistence = widget.controller.setWatermarkEnabled(enabled);
    if (mounted) {
      setState(() {});
    }
    try {
      await persistence;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存水印设置失败：$error')),
      );
    }
  }

  Future<void> _pressCollectSunlightKey() async {
    await _webViewController?.evaluateJavascript(
      source: gardendlessCollectSunlightKeyPressScript,
    );
  }

  Future<void> _handleDownloadStart(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    await _exportGameDownload(
      GameDownloadRequest(
        uri: Uri.parse(request.url.toString()),
        suggestedFilename: request.suggestedFilename,
        contentDisposition: request.contentDisposition,
        mimeType: request.mimeType,
        userAgent: request.userAgent,
      ),
    );
  }

  Future<void> _handleInlineDownloadUrl(WebUri url) async {
    await _exportGameDownload(
      GameDownloadRequest(uri: Uri.parse(url.toString())),
    );
  }

  Future<void> _handlePatchedDownload(Object? payload) async {
    final parsed = gameDownloadRequestFromPatchedPayload(payload);
    final failure = parsed.failure;
    if (failure != null) {
      await _showDownloadFailure(failure);
      return;
    }

    await _exportGameDownload(parsed.request!);
  }

  Future<void> _exportGameDownload(GameDownloadRequest request) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在准备导出文件...')),
    );

    try {
      final file = await _downloadService.exportDownload(
        request: request,
        presentationOrigin: _presentationOrigin(),
        blobResolver: _resolveBlobDownload,
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已打开保存位置选择：${file.name}')),
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.code == 'export_cancelled'
          ? '已取消导出'
          : '导出失败：${error.message ?? error.code}';
      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on GameDownloadFailure catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          error.message == '已取消导出' ? error.message : '导出失败：${error.message}';
      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败：$error')),
      );
    }
  }

  Future<void> _showDownloadFailure(String message) async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('导出失败：$message')),
    );
  }

  Rect _presentationOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      return const Rect.fromLTWH(1, 1, 1, 1);
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<GameDownloadPayload> _resolveBlobDownload(String blobUrl) async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
(async function () {
  const response = await fetch(${jsonEncode(blobUrl)});
  const blob = await response.blob();
  const dataUrl = await new Promise(function (resolve, reject) {
    const reader = new FileReader();
    reader.onloadend = function () { resolve(reader.result); };
    reader.onerror = function () { reject(reader.error); };
    reader.readAsDataURL(blob);
  });
  return JSON.stringify({ dataUrl: dataUrl, mimeType: blob.type || null });
})()
''',
    );
    final jsonText = result is String ? result : result?.toString();
    if (jsonText == null || jsonText.isEmpty) {
      throw const GameDownloadFailure('无法读取 Blob 导出内容');
    }
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    return GameDownloadPayload.fromDataUri(
      decoded['dataUrl'] as String,
      mimeTypeOverride: decoded['mimeType'] as String?,
    );
  }

  Future<void> _confirmReturnHome() async {
    final confirmed = await _confirm(
      title: '返回首页',
      message: '当前游戏页面状态可能丢失。确定返回首页并停止本地 server？',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.controller.stopGame();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmReload() async {
    final confirmed = await _confirm(
      title: '重新加载',
      message: '当前游戏页面状态可能丢失。确定重新加载？',
    );
    if (confirmed) {
      await _webViewController?.reload();
    }
  }

  Future<bool> _confirm(
      {required String title, required String message}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showDiagnostics() async {
    final text = widget.controller.diagnostics().toCopyText();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class GameMenuOverlay extends StatelessWidget {
  const GameMenuOverlay({
    super.key,
    required this.onContinue,
    required this.child,
  });

  final VoidCallback onContinue;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: GestureDetector(
                key: const ValueKey('game-menu-backdrop'),
                behavior: HitTestBehavior.opaque,
                onDoubleTap: onContinue,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: isDark ? 0.52 : 0.34),
                ),
              ),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }
}

class GameMenuDialog extends StatelessWidget {
  const GameMenuDialog({
    super.key,
    required this.autoCollectSunlightEnabled,
    required this.onAutoCollectSunlightChanged,
    required this.watermarkEnabled,
    required this.onWatermarkChanged,
    required this.onContinue,
    required this.onReturnHome,
    required this.onReload,
    required this.onDiagnostics,
  });

  final bool autoCollectSunlightEnabled;
  final ValueChanged<bool> onAutoCollectSunlightChanged;
  final bool watermarkEnabled;
  final ValueChanged<bool> onWatermarkChanged;
  final VoidCallback onContinue;
  final VoidCallback onReturnHome;
  final VoidCallback onReload;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = math.min(480.0, screenSize.width * 0.9);
    final panelHeight = screenSize.height * 0.9;
    final radius = BorderRadius.circular(28);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: panelHeight),
        child: SizedBox(
          key: const ValueKey('game-menu-panel'),
          width: panelWidth,
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                key: const ValueKey('game-menu-glass-surface'),
                decoration: BoxDecoration(
                  gradient: LauncherVisuals.workbenchGradient(context),
                  borderRadius: radius,
                  border: Border.all(
                    color: LauncherVisuals.glassBorder(context),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 42,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: LauncherVisuals.accentBlue
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.sports_esports_rounded,
                                color: LauncherVisuals.accentBlue,
                                size: 25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '游戏菜单',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: LauncherVisuals.primaryText(
                                          context,
                                        ),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '调整辅助功能或继续游戏',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: LauncherVisuals.secondaryText(
                                          context,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Material(
                        color: LauncherVisuals.innerPanelBackground(context),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: LauncherVisuals.separator(context)
                                .withValues(alpha: 0.66),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SwitchListTile(
                              secondary: const Icon(Icons.wb_sunny_rounded),
                              title: const Text('自动收集阳光'),
                              subtitle: const Text('每 1.5 秒自动按下 A 键'),
                              value: autoCollectSunlightEnabled,
                              onChanged: onAutoCollectSunlightChanged,
                            ),
                            Divider(
                              height: 1,
                              indent: 18,
                              endIndent: 18,
                              color: LauncherVisuals.separator(context),
                            ),
                            SwitchListTile(
                              secondary: const Icon(Icons.branding_watermark),
                              title: const Text('显示水印'),
                              subtitle: const Text('在游戏画面左下角显示防倒卖提示'),
                              value: watermarkEnabled,
                              onChanged: onWatermarkChanged,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('继续游戏'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: FilledButton.tonalIcon(
                                onPressed: onReload,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('重新加载'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: FilledButton.tonalIcon(
                                onPressed: onDiagnostics,
                                icon: const Icon(Icons.terminal_rounded),
                                label: const Text('诊断信息'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: LauncherVisuals.danger,
                            side: BorderSide(
                              color: LauncherVisuals.danger
                                  .withValues(alpha: 0.62),
                            ),
                          ),
                          onPressed: onReturnHome,
                          icon: const Icon(Icons.home_rounded),
                          label: const Text('返回首页'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameViewportFrame extends StatelessWidget {
  const GameViewportFrame({
    super.key,
    required this.child,
    this.showWatermark = true,
    this.minAspectRatio = 16 / 10,
    this.maxAspectRatio = 17 / 9,
  })  : assert(minAspectRatio > 0),
        assert(maxAspectRatio >= minAspectRatio);

  final Widget child;
  final bool showWatermark;
  final double minAspectRatio;
  final double maxAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = MediaQuery.sizeOf(context);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackSize.width;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackSize.height;

        if (maxWidth <= 0 || maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final screenAspectRatio = maxWidth / maxHeight;
        final targetAspectRatio = screenAspectRatio.clamp(
          minAspectRatio,
          maxAspectRatio,
        );
        final width = screenAspectRatio > targetAspectRatio
            ? maxHeight * targetAspectRatio
            : maxWidth;
        final height = screenAspectRatio < targetAspectRatio
            ? maxWidth / targetAspectRatio
            : maxHeight;

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (showWatermark)
                      const Positioned(
                        left: 10,
                        bottom: 8,
                        child: GameWatermark(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GameWatermark extends StatelessWidget {
  const GameWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: const ValueKey('game-watermark-ignore-pointer'),
      ignoring: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            gameWatermarkText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xcfffffff),
              fontSize: 11,
              height: 1.1,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

({GameDownloadRequest? request, String? failure})
    gameDownloadRequestFromPatchedPayload(Object? payload) {
  if (payload is! Map) {
    return (request: null, failure: '导出消息格式无效');
  }

  final scriptError = payload['error'];
  if (scriptError is String && scriptError.trim().isNotEmpty) {
    return (request: null, failure: scriptError.trim());
  }

  final dataUrl = _payloadString(payload, 'dataUrl');
  final url = dataUrl == null || dataUrl.isEmpty
      ? _payloadString(payload, 'url')
      : dataUrl;
  if (url == null || url.isEmpty) {
    return (request: null, failure: '导出消息缺少文件地址');
  }

  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    return (request: null, failure: '导出地址无效');
  }

  return (
    request: GameDownloadRequest(
      uri: uri,
      suggestedFilename: _payloadString(payload, 'suggestedFilename'),
      mimeType: _payloadString(payload, 'mimeType'),
    ),
    failure: null,
  );
}

String? _payloadString(Map<dynamic, dynamic> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}
