import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import vibrator from '@ohos.vibrator';
import { appLogStore, AppLogContext, AppLogError, AppLogEvent } from '../logging/AppLogStore';
import { withDocumentPickerOrientation } from '../picker/DocumentPickerOrientation';
import { ExportDocumentSpec } from './ExportDocumentSpec';
import { GpNextPackArchiveNormalizer } from './GpNextPackArchiveNormalizer';
import { GameSession } from './GameSession';
import { GpNextNativeCore, GpNextValue, FileFailure } from './GpNextNativeCore';

interface BridgeRequest {
  id: string;
  namespace: string;
  command: string;
  args?: BridgeArguments;
}

interface BridgeArguments {
  kind?: string;
  url?: string;
  suggestedFilename?: string;
  mimeType?: string;
  directory?: number;
  action?: string;
  event?: string;
  level?: string;
  message?: string;
  stack?: string;
  page?: string;
  line?: number;
  column?: number;
  outcome?: string;
  context?: AppLogContext;
}

interface BridgeError {
  code: string;
  message: string;
}

type BridgeValue = GpNextValue;

/** A file the player exported, reported to the launcher in the exit result. */
export interface ExportRecord {
  name: string;
  at: string;
}

interface BridgeResponse {
  id: string;
  ok: boolean;
  value?: BridgeValue;
  error?: BridgeError;
}

export class GameBridge {
  private readonly controller: webview.WebviewController;
  private readonly context: common.UIAbilityContext;
  private readonly session: GameSession;
  private readonly onReturnHome: () => void;
  private readonly gpNextCore: GpNextNativeCore;
  private readonly activeIds: Set<string> = new Set<string>();
  private destroyed: boolean = false;
  private pickerActive: boolean = false;
  readonly exports: ExportRecord[] = [];

  constructor(
    controller: webview.WebviewController,
    context: common.UIAbilityContext,
    session: GameSession,
    onReturnHome: () => void,
  ) {
    this.controller = controller;
    this.context = context;
    this.session = session;
    this.onReturnHome = onReturnHome;
    this.gpNextCore = new GpNextNativeCore(session);
  }

  postMessage(message: string): void {
    if (this.destroyed) {
      return;
    }
    if (typeof message !== 'string') { this.logInvalid('invalid_message'); return; }
    if (new util.TextEncoder().encodeInto(message).byteLength > 1024 * 1024 || !this.isTrustedFrame()) {
      this.logInvalid('origin_frame_or_size_rejected');
      return;
    }
    let request: BridgeRequest;
    try {
      request = JSON.parse(message) as BridgeRequest;
    } catch (_error) {
      this.logInvalid('invalid_json');
      return;
    }
    if (request == null || typeof request !== 'object') { this.logInvalid('invalid_message'); return; }
    if (typeof request.id !== 'string' || !/^[A-Za-z0-9:_-]{1,128}$/.test(request.id) ||
      typeof request.command !== 'string' || request.command.length === 0 || request.command.length > 128) {
      this.logInvalid('missing_id_or_command');
      return;
    }
    if (this.activeIds.has(request.id)) {
      this.logInvalid('duplicate_request_id', request.command);
      return;
    }
    const control = request.command === 'file:finish' &&
      (request.args?.action === 'close' || request.args?.action === 'cancel');
    if (this.activeIds.size >= (control ? 72 : 64)) {
      this.respond({ id: request.id, ok: false, error: {
        code: 'resource_limit_exceeded', message: 'Too many active bridge requests',
      } }, false);
      return;
    }
    this.activeIds.add(request.id);
    switch (request.command) {
      case 'host:returnHome':
      case 'host:return_home':
        this.complete(request.id, null);
        this.onReturnHome();
        break;
      case 'host:haptic':
        {
          this.complete(request.id, null);
          const effect: vibrator.VibrateTime = {
            type: 'time',
            duration: request.args?.kind === 'selection' ? 10 : 20,
          };
          const attribute: vibrator.VibrateAttribute = { usage: 'touch' };
          // A missed tap is not worth a log entry.
          vibrator.startVibration(effect, attribute).catch((_error: Error): void => {});
        }
        break;
      case 'host:log':
        {
          const args = request.args ?? {};
          const requested = args.event ?? 'javascript_console';
          const allowed = [
            'javascript_uncaught_error',
            'javascript_unhandled_rejection',
            'javascript_console',
            'audio_summary', 'audio_decode_started', 'audio_decode_succeeded', 'audio_decode_failed',
            'audio_media_load_started', 'audio_media_ready', 'audio_media_play_requested',
            'audio_media_playing', 'audio_media_ended', 'audio_media_failed',
            'touch_trace',
          ];
          const event = allowed.includes(requested) ? requested : 'javascript_console';
          const audio = event.startsWith('audio_');
          const touchTrace = event === 'touch_trace';
          const outcome = args.outcome ?? (event === 'javascript_console' ? 'observed' : 'failed');
          const context: AppLogContext = args.context ?? {
            page: args.page ?? '',
            line: args.line ?? 0,
            column: args.column ?? 0,
          };
          const logError: AppLogError = {
            type: audio ? 'AudioError' : 'JavaScriptError',
            message: args.message ?? '',
            stackTrace: args.stack ?? '',
          };
          const logEvent: AppLogEvent = {
            source: 'javascript',
            level: args.level ?? 'ERROR',
            category: audio ? 'game.audio' : touchTrace ? 'game.touch' : 'game.javascript',
            event: event,
            outcome: outcome,
            code: outcome === 'failed' ? event : undefined,
            message: args.message ?? '',
            gameSessionId: this.session.sessionId,
            context: context,
            error: outcome === 'failed' ? logError : undefined,
          };
          appLogStore.emit(logEvent);
          this.complete(request.id, null);
        }
        break;
      case 'host:export':
        this.exportFile(request.id, request.args ?? {});
        break;
      case 'file:begin':
      case 'file:chunk':
      case 'file:finish':
        this.dispatchNative(request);
        break;
      default:
        if (request.namespace === 'gp-next') {
          this.dispatchNative(request);
        } else {
          this.logInvalid('unknown_command', request.command);
          this.fail(request.id, 'unknown_command', `Unsupported host command: ${request.command}`);
        }
    }
  }

  destroy(): void {
    this.destroyed = true;
    this.gpNextCore.destroy();
    this.activeIds.clear();
    this.controller.runJavaScript(
      "window.__gardendlessTransport && window.__gardendlessTransport.rejectAll('host_destroyed','Game host was destroyed')",
    ).catch((_error: Error): void => {});
  }

  private async dispatchNative(request: BridgeRequest): Promise<void> {
    try {
      const result = await this.gpNextCore.invoke(request);
      if (this.destroyed) return;
      if (result.openUrl != null) {
        this.openGpNextUrl(request.id, result.openUrl);
      } else if (result.exportPath != null && result.exportHandle != null) {
        await this.exportExistingFile(request.id, result.exportHandle, result.exportPath,
          result.suggestedFilename ?? 'gardendless-export.json', result.mimeType ?? 'application/octet-stream');
      } else if (result.importRequested === true) {
        await this.importGpNextPackages(request.id);
      } else if (result.selectionDirectory != null) {
        await this.selectGpNextPackage(request.id, result.selectionDirectory);
      } else {
        this.complete(request.id, result.value);
      }
    } catch (error) {
      const failure = error as FileFailure;
      this.fail(request.id, failure.code ?? 'io_failed', failure.code == null ? 'Native file operation failed' : failure.message);
    }
  }

  private openGpNextUrl(id: string, raw: string): void {
    const url = this.session.allowedRemoteUrl(raw, ['https:', 'http:']);
    if (url == null) {
      this.fail(id, 'external_url_blocked', 'GP-Next 请求打开了未授权网址');
      return;
    }
    this.context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
      .then((): void => this.complete(id, null))
      .catch((error: Error): void => this.fail(id, 'external_open_failed', error.message));
  }

  private async exportExistingFile(
    id: string,
    handle: string,
    sourcePath: string,
    suggestedFileName: string,
    mimeType: string,
  ): Promise<void> {
    if (this.pickerActive) {
      await this.gpNextCore.exportFinished(handle, false);
      this.fail(id, 'export_in_progress', 'Another import or export picker is active');
      return;
    }
    this.gpNextCore.setExportCancellation(handle, (): void => {
      this.fail(id, 'cancelled', 'Export was cancelled');
    });
    this.pickerActive = true;
    try {
      const options = new picker.DocumentSaveOptions();
      const fileName = ExportDocumentSpec.safeFileName(suggestedFileName);
      options.newFileNames = [fileName];
      const suffixChoices = ExportDocumentSpec.fileSuffixChoices(fileName, mimeType);
      if (suffixChoices.length > 0) options.fileSuffixChoices = suffixChoices;
      const targets = await withDocumentPickerOrientation(this.context,
        (): Promise<string[]> => new picker.DocumentViewPicker().save(options));
      if (this.destroyed || !this.gpNextCore.isFileActive(handle)) return;
      if (targets == null || targets.length === 0) {
        await this.gpNextCore.exportFinished(handle, false);
        this.fail(id, 'export_cancelled', 'Export was cancelled');
        return;
      }
      await this.gpNextCore.runIO(async (): Promise<void> => {
        await this.gpNextCore.copyFile(sourcePath, targets[0], handle);
        if (!this.gpNextCore.isFileActive(handle)) throw new FileFailure('cancelled', 'Export was cancelled');
        await this.gpNextCore.exportFinished(handle, true);
      });
      this.exports.push({ name: fileName, at: new Date().toISOString() });
      if (this.exports.length > 16) this.exports.shift();
      this.complete(id, null);
    } catch (error) {
      await this.gpNextCore.exportFinished(handle, false);
      this.fail(id, (error as FileFailure).code ?? 'export_failed', 'Export failed');
    } finally { this.pickerActive = false; }
  }

  private async importGpNextPackages(id: string): Promise<void> {
    if (this.pickerActive) {
      this.fail(id, 'gp_next_import_busy', 'Another import or export picker is active');
      return;
    }
    this.pickerActive = true;
    try {
      const selected = await withDocumentPickerOrientation(
        this.context,
        (): Promise<string[]> => new picker.DocumentViewPicker().select(new picker.DocumentSelectOptions()),
      );
      if (selected == null || selected.length === 0) {
        this.fail(id, 'import_cancelled', 'Import was cancelled');
        return;
      }
      await this.gpNextCore.runIO(async (): Promise<void> => {
        await this.ensureDirectory(`${this.session.gpNextRoot}/packs`);
        await this.ensureDirectory(`${this.session.gpNextRoot}/patches`);
        for (const uri of selected) {
          const name = ExportDocumentSpec.safeFileName(uri);
          const extension = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
          const directory = extension === 'zip'
            ? `${this.session.gpNextRoot}/packs`
            : (extension === 'json' || extension === 'json5')
              ? `${this.session.gpNextRoot}/patches`
              : '';
          if (directory.length === 0) throw new Error(`不支持的 GP-Next 文件：${name}`);
          // Only GP-Next's legacy runtime reads packs/; its mod platform installs
          // ZIP mods from its own picker once configuration-state.json exists.
          if (extension === 'zip' && await this.fileExists(`${this.session.gpNextRoot}/configuration-state.json`)) {
            throw new Error('GP-Next 已启用新版模组管理，请在 GP-Next 模组页安装 ZIP 模组');
          }
          const destination = `${directory}/${name}`;
          const incoming = `${directory}/.${name}.incoming-${Date.now()}`;
          let prepared = incoming;
          try {
            await this.gpNextCore.copyFile(uri, incoming);
            if (extension === 'json') {
              JSON.parse(await fs.readText(incoming));
            } else if (extension === 'zip') {
              prepared = await GpNextPackArchiveNormalizer.prepare(incoming, directory, name, this.gpNextCore);
            } else if ((await fs.stat(incoming)).size === 0) {
              throw new Error(`${name} 是空文件`);
            }
            const existed = await this.fileExists(destination);
            if (existed && !await this.confirmReplacement(name)) {
              continue;
            }
            const backup = `${directory}/.${name}.backup-${Date.now()}`;
            this.gpNextCore.checkActive();
            if (existed) await fs.rename(destination, backup);
            try {
              await fs.rename(prepared, destination);
              if (existed) await fs.unlink(backup);
            } catch (error) {
              if (existed && !await this.fileExists(destination) && await this.fileExists(backup)) {
                await fs.rename(backup, destination);
              }
              throw new Error((error as Error).message);
            }
          } finally {
            if (await this.fileExists(incoming)) await fs.unlink(incoming);
            if (prepared !== incoming && await this.fileExists(prepared)) await fs.unlink(prepared);
          }
        }
      });
      this.complete(id, null);
    } catch (error) {
      this.fail(id, 'gp_next_import_failed', (error as Error).message);
    } finally {
      this.pickerActive = false;
    }
  }

  private async selectGpNextPackage(id: string, directory: boolean): Promise<void> {
    if (this.pickerActive) {
      this.fail(id, 'gp_next_selection_busy', 'Another import or export picker is active');
      return;
    }
    this.pickerActive = true;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = directory
        ? picker.DocumentSelectMode.FOLDER
        : picker.DocumentSelectMode.FILE;
      if (!directory) options.fileSuffixFilters = ['Mod ZIP|.zip'];
      const selected = await withDocumentPickerOrientation(
        this.context,
        (): Promise<string[]> => new picker.DocumentViewPicker().select(options),
      );
      if (selected == null || selected.length === 0) {
        this.complete(id, null);
        return;
      }
      await this.gpNextCore.runIO(async (): Promise<void> => {
        await this.clearGpNextSelection();
        const source = selected[0];
        const stagingRoot = `${this.session.gpNextRoot}/.gardendless-selection`;
        await this.ensureDirectory(stagingRoot);
        const budget = new SelectionCopyBudget();
        if (directory) {
          const destination = `${stagingRoot}/selection`;
          await this.ensureDirectory(destination);
          await this.copySelectionDirectory(source, destination, budget);
          this.complete(id, destination);
        } else {
          const name = ExportDocumentSpec.safeFileName(source);
          if (!name.toLowerCase().endsWith('.zip')) throw new Error('请选择 ZIP 格式的 Mod 包');
          const destination = `${stagingRoot}/selection.zip`;
          await this.copySelectionFile(source, destination, budget);
          this.complete(id, destination);
        }
      });
    } catch (error) {
      if (!this.destroyed) try { await this.gpNextCore.runIO(async (): Promise<void> => { await this.clearGpNextSelection(); }, true); } catch (_cleanupError) {}
      this.fail(id, 'gp_next_selection_failed', (error as Error).message);
    } finally {
      this.pickerActive = false;
    }
  }

  private async copySelectionDirectory(
    source: string,
    destination: string,
    budget: SelectionCopyBudget,
  ): Promise<void> {
    const stat = await fs.lstat(source);
    if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error('请选择一个 Mod 目录');
    for (const name of await fs.listFile(source)) {
      this.gpNextCore.checkActive();
      const safeName = this.requireSafeSelectionName(name);
      budget.addEntry();
      const sourceChild = `${source.replace(/\/$/, '')}/${encodeURIComponent(safeName)}`;
      const destinationChild = `${destination}/${safeName}`;
      const childStat = await fs.lstat(sourceChild);
      if (childStat.isSymbolicLink()) throw new Error('选择内容包含符号链接');
      if (childStat.isDirectory()) {
        await this.ensureDirectory(destinationChild);
        await this.copySelectionDirectory(sourceChild, destinationChild, budget);
      } else if (childStat.isFile()) {
        await this.copySelectionFile(sourceChild, destinationChild, budget);
      } else {
        throw new Error('选择内容包含不支持的文件类型');
      }
    }
  }

  private async copySelectionFile(
    source: string,
    destination: string,
    budget: SelectionCopyBudget,
  ): Promise<void> {
    const stat = await fs.lstat(source);
    if (stat.isSymbolicLink() || !stat.isFile()) throw new Error('选择内容包含不支持的文件类型');
    budget.addBytes(stat.size);
    await this.gpNextCore.copyFile(source, destination);
  }

  private async clearGpNextSelection(): Promise<void> {
    const root = `${this.session.gpNextRoot}/.gardendless-selection`;
    if (!await this.fileExists(root)) return;
    await this.removeSelectionTree(root);
  }

  private async removeSelectionTree(path: string): Promise<void> {
    this.gpNextCore.checkActive();
    const stat = await fs.lstat(path);
    if (stat.isSymbolicLink()) throw new Error('选择暂存区包含符号链接');
    if (stat.isDirectory()) {
      for (const name of await fs.listFile(path)) {
        await this.removeSelectionTree(`${path}/${name}`);
      }
      await fs.rmdir(path);
    } else {
      await fs.unlink(path);
    }
  }

  private requireSafeSelectionName(value: string): string {
    const name = value.trim();
    if (name.length === 0 || name === '.' || name === '..' || name.includes('/') || name.includes('\\')) {
      throw new Error('选择内容包含无效名称');
    }
    return name;
  }

  private async exportFile(id: string, args: BridgeArguments): Promise<void> {
    const url = args.url == null ? null : this.session.allowedRemoteUrl(args.url, ['https:']);
    if (url == null) {
      this.fail(id, 'unsupported_export', 'Export URL is not authorized');
      return;
    }
    try {
      await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: url });
      this.complete(id, null);
    } catch (error) {
      this.fail(id, 'external_open_failed', (error as Error).message);
    }
  }

  private logInvalid(reason: string, command?: string): void {
    const context: AppLogContext = { reason: reason };
    if (command != null) {
      context.command = command;
    }
    const event: AppLogEvent = {
      source: 'ohos',
      level: 'WARN',
      category: 'game.bridge',
      event: 'bridge_message_invalid',
      outcome: 'failed',
      code: 'bridge_message_invalid',
      gameSessionId: this.session.sessionId,
      context: context,
    };
    appLogStore.emit(event);
  }

  private async fileExists(path: string): Promise<boolean> { return fs.access(path); }

  private async confirmReplacement(name: string): Promise<boolean> {
    const result = await promptAction.showDialog({
      title: '替换 GP-Next 文件',
      message: `${name} 已存在，是否使用新文件替换？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '替换', color: '#d32f2f' },
      ],
    });
    return result.index === 1;
  }

  private complete(id: string, value: BridgeValue): void {
    this.respond({ id: id, ok: true, value: value });
  }

  private fail(id: string, code: string, message: string): void {
    this.respond({ id: id, ok: false, error: { code: code, message: message } });
  }

  private respond(response: BridgeResponse, removeActive: boolean = true): void {
    if (removeActive) {
      if (!this.activeIds.has(response.id)) return;
      this.activeIds.delete(response.id);
    }
    if (this.destroyed) {
      return;
    }
    const json = JSON.stringify(response);
    this.controller.runJavaScript(
      `window.__gardendlessTransport && window.__gardendlessTransport.resolve(${json})`,
    ).catch((_error: Error): void => {});
  }

  private isTrustedFrame(): boolean {
    try {
      // API 12 exposes the actual calling frame URL, but supplies no proxy
      // main-frame flag. Origin permission alone cannot distinguish same-origin iframes.
      const url = this.controller.getLastJavascriptProxyCallingFrameUrl();
      return url === GameSession.ORIGIN || url.startsWith(`${GameSession.ORIGIN}/`);
    } catch (_error) {
      return false;
    }
  }

  private async ensureDirectory(path: string): Promise<void> {
    this.gpNextCore.checkActive();
    if (await fs.access(path)) {
      if (!(await fs.lstat(path)).isDirectory() || (await fs.lstat(path)).isSymbolicLink()) {
        throw new FileFailure('invalid_file_transfer', 'Unsafe destination directory');
      }
      return;
    }
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.length > 0) await this.ensureDirectory(parent);
    await fs.mkdir(path);
  }

}

class SelectionCopyBudget {
  private entries: number = 0;
  private bytes: number = 0;

  addEntry(): void {
    this.entries += 1;
    if (this.entries > 10000) throw new Error('选择的 Mod 包文件数量过多');
  }

  addBytes(count: number): void {
    this.bytes += count;
    if (this.bytes > 512 * 1024 * 1024) throw new Error('选择的 Mod 包超过 512 MiB');
  }
}
