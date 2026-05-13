import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../web/touch_patch.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  bool _resumeReloadNotified = false;

  @override
  void initState() {
    super.initState();
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
            InAppWebView(
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
              initialUrlRequest: URLRequest(url: WebUri('$localOrigin/index.html')),
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
                mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
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
    return url != null && (url.host == 'github.com' || url.host.endsWith('.github.com'));
  }

  Future<void> _showMenu() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text('游戏菜单'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('继续游戏'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await _confirmReturnHome();
            },
            child: const Text('返回首页'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await _confirmReload();
            },
            child: const Text('重新加载'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(context).pop();
              _showDiagnostics();
            },
            child: const Text('诊断信息'),
          ),
        ],
      ),
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

  Future<bool> _confirm({required String title, required String message}) async {
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
