import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../models.dart';
import '../services/update_check_service.dart';
import 'game_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _lastMessage;
  String? _activeAnnouncementId;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.checkForUpdates(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _showMessageIfNeeded();
        _showAnnouncementIfNeeded();

        final controller = widget.controller;
        if (!controller.initialized && controller.busy) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('$appDisplayName | B站xiaozhu_410免费分享，严禁售卖'),
            actions: [
              IconButton(
                tooltip: '诊断信息',
                onPressed: _showDiagnostics,
                icon: const Icon(Icons.receipt_long_outlined),
              ),
              IconButton(
                tooltip: '免责声明',
                onPressed: _showDisclaimer,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StatusPanel(controller: controller),
                const SizedBox(height: 20),
                if (controller.availableUpdate != null) ...[
                  _UpdateNotice(
                    update: controller.availableUpdate!,
                    onOpenRelease: _openRelease,
                    onDefer: widget.controller.deferUpdate,
                  ),
                  const SizedBox(height: 20),
                ],
                if (controller.hasCurrentResource &&
                    controller.importValidation.status ==
                        ResourceStatus.invalid)
                  _Notice(
                    title: '上次选择的 docs 无效',
                    message:
                        controller.importValidation.errorMessage ?? 'docs 校验失败',
                    icon: Icons.warning_amber_outlined,
                  )
                else if (!controller.hasCurrentResource)
                  const _Notice(
                    title: '需要导入资源',
                    message: '请选择从 GitHub 下载的资源 ZIP 导入。',
                    icon: Icons.file_upload_outlined,
                  ),
                if (controller.importProgress.phase != ImportPhase.idle)
                  _ImportProgressView(progress: controller.importProgress),
                const SizedBox(height: 20),
                _Actions(
                  controller: controller,
                  onOpenGitHub: _openGitHub,
                  onCheckUpdates: widget.controller.checkForUpdates,
                ),
                const SizedBox(height: 24),
                const _InstructionBlock(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessageIfNeeded() {
    final message = widget.controller.message;
    if (message == null || message == _lastMessage) {
      return;
    }
    _lastMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _openGitHub() async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(githubUrl));
  }

  Future<void> _openRelease(UpdateInfo update) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(update.releaseUrl));
  }

  Future<void> _openAnnouncementLink(AnnouncementLink link) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(link.url));
  }

  void _showAnnouncementIfNeeded() {
    final announcement = widget.controller.pendingAnnouncement;
    if (announcement == null || announcement.id == _activeAnnouncementId) {
      return;
    }

    _activeAnnouncementId = announcement.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          widget.controller.pendingAnnouncement?.id != announcement.id) {
        _activeAnnouncementId = null;
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Text(announcement.message),
          ),
          actions: [
            for (final link in announcement.links)
              TextButton.icon(
                onPressed: () => _openAnnouncementLink(link),
                icon: const Icon(Icons.open_in_new),
                label: Text(link.label),
              ),
            TextButton(
              onPressed: () async {
                await widget.controller.dismissAnnouncement(announcement);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('关闭'),
            ),
          ],
        ),
      );

      if (mounted && _activeAnnouncementId == announcement.id) {
        _activeAnnouncementId = null;
      }
    });
  }

  Future<void> _startGame() async {
    try {
      await widget.controller.startGame();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GamePage(controller: widget.controller),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法启动游戏：$error')),
      );
    }
  }

  Future<void> _showDisclaimer() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('来源和免责声明'),
        content: const Text(disclaimerText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    final text = widget.controller.diagnostics().toCopyText();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(text),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('诊断信息已复制')),
                );
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

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hasCurrent = controller.hasCurrentResource;
    final title = hasCurrent ? '资源已导入' : '尚未导入资源';
    final subtitle = hasCurrent
        ? controller.detectedTitle
        : '请选择从 GitHub 下载的资源 ZIP，App 会自动解压、校验并导入。';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(hasCurrent
                    ? Icons.check_circle_outline
                    : Icons.folder_open_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(subtitle),
            const SizedBox(height: 12),
            Text(
              '导入来源：${controller.userVisibleImportDocs}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '资源根目录：${controller.userVisibleRoot}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.controller,
    required this.onOpenGitHub,
    required this.onCheckUpdates,
  });

  final AppController controller;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function() onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_HomePageState>();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: controller.canStartGame ? state?._startGame : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始游戏'),
        ),
        FilledButton.tonalIcon(
          onPressed: controller.busy || controller.isImporting
              ? null
              : controller.importResources,
          icon: const Icon(Icons.file_upload_outlined),
          label:
              Text(controller.hasCurrentResource ? '选择 ZIP 更新' : '选择 ZIP 导入'),
        ),
        OutlinedButton.icon(
          onPressed: onOpenGitHub,
          icon: const Icon(Icons.open_in_new),
          label: const Text('打开 GitHub'),
        ),
        OutlinedButton.icon(
          onPressed: controller.updateCheckInProgress ? null : onCheckUpdates,
          icon: const Icon(Icons.system_update_alt),
          label: Text(controller.updateCheckInProgress ? '检查中...' : '检查更新'),
        ),
      ],
    );
  }
}

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({
    required this.update,
    required this.onOpenRelease,
    required this.onDefer,
  });

  final UpdateInfo update;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDefer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '发现新版本 v${update.latestVersion}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('当前版本 ${update.currentVersion}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => onOpenRelease(update),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('查看 GitHub Release'),
                ),
                TextButton(
                  onPressed: () => onDefer(update),
                  child: const Text('稍后提醒'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionBlock extends StatelessWidget {
  const _InstructionBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('导入指引', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('1. 打开 GitHub 下载 ZIP。'),
        const Text('2. 点击选择 ZIP 导入，并选择下载的 ZIP 文件。'),
        const Text('3. App 会自动解压并定位 ZIP 内的 docs 资源目录。'),
        const Text('4. docs 内应直接包含 index.html、assets、cocos-js、src。'),
      ],
    );
  }
}

class _ImportProgressView extends StatelessWidget {
  const _ImportProgressView({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final total = progress.totalBytes;
    final value = total <= 0 ? null : progress.copiedBytes / total;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(progress.message ?? '处理中'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: value),
          const SizedBox(height: 8),
          Text(
            '${progress.copiedFiles}/${progress.totalFiles} 文件，'
            '${progress.copiedBytes}/${progress.totalBytes} 字节',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(message),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
