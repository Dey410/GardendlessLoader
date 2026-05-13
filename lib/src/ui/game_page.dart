import 'dart:async';
import 'dart:math' as math;
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../services/auto_sun_collector.dart';
import '../web/touch_patch.dart';

const _collectSunlightKeyPressScript = r'''
(function () {
  const eventInit = {
    key: "a",
    code: "KeyA",
    keyCode: 65,
    which: 65,
    bubbles: true,
    cancelable: true,
    composed: true
  };
  const targets = [
    document.activeElement,
    document.getElementById("GameCanvas"),
    document,
    window
  ].filter(Boolean);
  const uniqueTargets = Array.from(new Set(targets));

  for (const target of uniqueTargets) {
    target.dispatchEvent(new KeyboardEvent("keydown", eventInit));
  }
  setTimeout(function () {
    for (const target of uniqueTargets) {
      target.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    }
  }, 30);
})();
''';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  late final AutoSunCollector _autoSunCollector;
  bool _autoCollectSunlightEnabled = false;
  bool _stretchGameViewport = false;
  bool _resumeReloadNotified = false;

  @override
  void initState() {
    super.initState();
    _autoSunCollector = AutoSunCollector(
      onPressCollectKey: _pressCollectSunlightKey,
    );
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
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
                fit: _stretchGameViewport
                    ? GameViewportFit.stretch
                    : GameViewportFit.contain,
                child: InAppWebView(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: gardendlessTouchPatchSource,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      forMainFrameOnly: false,
                    ),
                  ]),
                  initialUrlRequest:
                      URLRequest(url: WebUri('$localOrigin/index.html')),
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
                    allowFileAccess: false,
                    allowContentAccess: false,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final url = action.request.url;
                    if (_isLocalUrl(url)) {
                      return NavigationActionPolicy.ALLOW;
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
                  onDownloadStartRequest: (controller, request) async {},
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: '菜单',
                  onPressed: _showMenu,
                  icon: const Icon(Icons.menu),
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

  Future<void> _showMenu() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => GameMenuDialog(
          autoCollectSunlightEnabled: _autoCollectSunlightEnabled,
          onAutoCollectSunlightChanged: (enabled) {
            _setAutoCollectSunlightEnabled(enabled);
            setDialogState(() {});
          },
          onContinue: () => Navigator.of(context).pop(),
          onReturnHome: () {
            Navigator.of(context).pop();
            unawaited(_confirmReturnHome());
          },
          onReload: () {
            Navigator.of(context).pop();
            unawaited(_confirmReload());
          },
          onDiagnostics: () {
            Navigator.of(context).pop();
            unawaited(_showDiagnostics());
          },
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

  Future<void> _pressCollectSunlightKey() async {
    await _webViewController?.evaluateJavascript(
      source: _collectSunlightKeyPressScript,
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

class GameMenuDialog extends StatelessWidget {
  const GameMenuDialog({
    super.key,
    required this.autoCollectSunlightEnabled,
    required this.onAutoCollectSunlightChanged,
    required this.onContinue,
    required this.onReturnHome,
    required this.onReload,
    required this.onDiagnostics,
  });

  final bool autoCollectSunlightEnabled;
  final ValueChanged<bool> onAutoCollectSunlightChanged;
  final VoidCallback onContinue;
  final VoidCallback onReturnHome;
  final VoidCallback onReload;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('游戏菜单'),
      children: [
        SwitchListTile(
          title: const Text('自动收集阳光'),
          subtitle: const Text('每 1.5 秒自动按下 A 键'),
          value: autoCollectSunlightEnabled,
          onChanged: onAutoCollectSunlightChanged,
        ),
        const Divider(height: 1),
        SimpleDialogOption(
          onPressed: onContinue,
          child: const Text('继续游戏'),
        ),
        SimpleDialogOption(
          onPressed: onReturnHome,
          child: const Text('返回首页'),
        ),
        SimpleDialogOption(
          onPressed: onReload,
          child: const Text('重新加载'),
        ),
        SimpleDialogOption(
          onPressed: onDiagnostics,
          child: const Text('诊断信息'),
        ),
      ],
    );
  }
}

class GameViewportFrame extends StatelessWidget {
  const GameViewportFrame({
    super.key,
    required this.child,
    this.aspectRatio = 16 / 9,
    this.fit = GameViewportFit.contain,
  });

  final Widget child;
  final double aspectRatio;
  final GameViewportFit fit;

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

        if (maxWidth <= 0 || maxHeight <= 0 || aspectRatio <= 0) {
          return const SizedBox.shrink();
        }

        final (width, height) = switch (fit) {
          GameViewportFit.contain => (
              math.min(maxWidth, maxHeight * aspectRatio),
              math.min(maxWidth, maxHeight * aspectRatio) / aspectRatio,
            ),
          GameViewportFit.stretch => (maxWidth, maxHeight),
        };

        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(child: child),
            ),
          ),
        );
      },
    );
  }
}

enum GameViewportFit {
  contain,
  stretch,
}
