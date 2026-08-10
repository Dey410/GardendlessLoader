import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { appLogStore, AppLogContext, AppLogError, AppLogEvent } from '../logging/AppLogStore';
import { withDocumentPickerOrientation } from '../picker/DocumentPickerOrientation';
import { ExportDocumentSpec } from './ExportDocumentSpec';
import { GameSession } from './GameSession';
import { GpNextNativeCore, GpNextValue } from './GpNextNativeCore';

interface BridgeRequest {
  id: string;
  namespace: string;
  command: string;
  args?: BridgeArguments;
}

interface BridgeArguments {
  enabled?: boolean;
  dataUrl?: string;
  url?: string;
  suggestedFilename?: string;
  mimeType?: string;
  directory?: number;
  token?: string;
  index?: number;
  data?: string;
  totalBytes?: number;
  event?: string;
  level?: string;
  message?: string;
  stack?: string;
  page?: string;
  line?: number;
  column?: number;
}

interface BridgeError {
  code: string;
  message: string;
}

type BridgeValue = GpNextValue;

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
  private readonly gpNextCore: GpNextNativeCore | null;
  private readonly activeIds: Set<string> = new Set<string>();
  private destroyed: boolean = false;
  private chunkedExport: ChunkedExport | null = null;
  private pickerActive: boolean = false;

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
    this.gpNextCore = session.hasGpNext && session.gpNextCompatible
      ? new GpNextNativeCore(session)
      : null;
  }

  postMessage(message: string): void {
    if (this.destroyed) {
      return;
    }
    if (message.length > 1024 * 1024 || !this.isTrustedFrame()) {
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
    if (request.id == null || request.id.length === 0 || request.command == null || request.command.length === 0) {
      this.logInvalid('missing_id_or_command');
      return;
    }
    if (this.activeIds.has(request.id)) {
      this.logInvalid('duplicate_request_id', request.command);
      this.respond({
        id: request.id,
        ok: false,
        error: {
          code: 'duplicate_request_id',
          message: 'Bridge request id is already active',
        },
      }, false);
      return;
    }
    this.activeIds.add(request.id);
    switch (request.command) {
      case 'host:returnHome':
      case 'host:return_home':
        this.complete(request.id, null);
        this.onReturnHome();
        break;
      case 'host:setWatermark':
      case 'host:set_watermark':
        try {
          this.persistWatermark(request.args?.enabled ?? true);
          this.complete(request.id, null);
        } catch (error) {
          this.fail(request.id, 'native_error', (error as Error).message);
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
          ];
          const event = allowed.includes(requested) ? requested : 'javascript_console';
          const context: AppLogContext = {
            page: args.page ?? '',
            line: args.line ?? 0,
            column: args.column ?? 0,
          };
          const logError: AppLogError = {
            type: 'JavaScriptError',
            message: args.message ?? '',
            stackTrace: args.stack ?? '',
          };
          const logEvent: AppLogEvent = {
            source: 'javascript',
            level: args.level ?? 'ERROR',
            category: 'game.javascript',
            event: event,
            outcome: 'failed',
            code: event === 'javascript_console' ? undefined : event,
            message: args.message ?? '',
            gameSessionId: this.session.sessionId,
            context: context,
            error: logError,
          };
          appLogStore.emit(logEvent);
          this.complete(request.id, null);
        }
        break;
      case 'host:export':
        this.exportFile(request.id, request.args ?? {});
        break;
      case 'host:exportBegin':
        this.beginChunkedExport(request.id, request.args ?? {});
        break;
      case 'host:exportChunk':
        this.appendChunkedExport(request.id, request.args ?? {});
        break;
      case 'host:exportCommit':
        this.commitChunkedExport(request.id, request.args ?? {});
        break;
      case 'host:exportAbort':
        this.abortChunkedExport(request.id, request.args ?? {});
        break;
      default:
        if (request.namespace === 'gp-next') {
          this.dispatchGpNext(request);
        } else {
          this.logInvalid('unknown_command', request.command);
          this.fail(request.id, 'unknown_command', `Unsupported host command: ${request.command}`);
        }
    }
  }

  destroy(): void {
    this.clearChunkedExport();
    this.destroyed = true;
    this.activeIds.clear();
    this.controller.runJavaScript(
      "window.__gardendlessTransport && window.__gardendlessTransport.rejectAll('host_destroyed','Game host was destroyed')",
    ).catch((_error: Error): void => {});
  }

  private beginChunkedExport(id: string, args: BridgeArguments): void {
    if (this.pickerActive || this.chunkedExport != null) {
      this.fail(id, 'export_in_progress', 'Another import or export picker is active');
      return;
    }
    if (args.totalBytes == null || args.totalBytes < 0 || args.totalBytes > 512 * 1024 * 1024) {
      this.fail(id, 'invalid_export_size', 'Export size is invalid');
      return;
    }
    try {
      this.ensureDirectory(this.session.exportTemporaryRoot);
      const name = this.safeFileName(args.suggestedFilename ?? 'gardendless-export.json');
      const path = `${this.session.exportTemporaryRoot}/.chunk-${Date.now()}-${name}`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const token = `${this.session.sessionId}-${Date.now()}`;
      this.chunkedExport = new ChunkedExport(
        token, path, file, args.totalBytes, args.mimeType ?? 'application/octet-stream', name,
      );
      this.complete(id, token);
    } catch (error) {
      this.fail(id, 'export_failed', (error as Error).message);
    }
  }

  private appendChunkedExport(id: string, args: BridgeArguments): void {
    const target = this.chunkedExport;
    if (target == null || args.token !== target.token || args.index !== target.nextIndex || args.data == null) {
      this.fail(id, 'invalid_export_chunk', 'Export chunk sequence is invalid');
      return;
    }
    try {
      const bytes = new util.Base64Helper().decodeSync(args.data);
      if (bytes.length > 256 * 1024 || target.written + bytes.length > target.expectedBytes) {
        throw new Error('Export chunk is too large');
      }
      fs.writeSync(target.file.fd, bytes.buffer, { offset: target.written, length: bytes.length });
      target.written += bytes.length;
      target.nextIndex += 1;
      this.complete(id, null);
    } catch (error) {
      this.clearChunkedExport();
      this.fail(id, 'invalid_export_chunk', (error as Error).message);
    }
  }

  private commitChunkedExport(id: string, args: BridgeArguments): void {
    const target = this.chunkedExport;
    if (target == null || args.token !== target.token || target.written !== target.expectedBytes) {
      this.fail(id, 'incomplete_export', 'Export did not receive every byte');
      return;
    }
    fs.closeSync(target.file.fd);
    this.chunkedExport = null;
    this.exportExistingFile(id, target.path, target.fileName, target.mimeType);
  }

  private abortChunkedExport(id: string, args: BridgeArguments): void {
    if (this.chunkedExport != null && args.token === this.chunkedExport.token) {
      this.clearChunkedExport();
    }
    this.complete(id, null);
  }

  private clearChunkedExport(): void {
    const target = this.chunkedExport;
    this.chunkedExport = null;
    if (target == null) return;
    try { fs.closeSync(target.file.fd); } catch (_error) {}
    try { fs.unlinkSync(target.path); } catch (_error) {}
  }

  private dispatchGpNext(request: BridgeRequest): void {
    const core = this.gpNextCore;
    if (core == null) {
      this.fail(request.id, 'gp_next_unavailable', 'GP-Next compatibility is unavailable');
      return;
    }
    try {
      const result = core.invoke(request);
      if (result.openUrl != null) {
        this.openGpNextUrl(request.id, result.openUrl);
      } else if (result.exportPath != null) {
        this.exportExistingFile(
          request.id,
          result.exportPath,
          this.safeFileName(result.exportPath),
          'application/json',
        );
      } else if (result.importRequested === true) {
        this.importGpNextPackages(request.id);
      } else {
        this.complete(request.id, result.value);
      }
    } catch (error) {
      this.fail(request.id, 'gp_next_error', (error as Error).message);
    }
  }

  private openGpNextUrl(id: string, url: string): void {
    let host = '';
    if (url.startsWith('https://')) host = url.substring(8).split('/')[0].split(':')[0].toLowerCase();
    if (url.startsWith('http://')) host = url.substring(7).split('/')[0].split(':')[0].toLowerCase();
    let allowed = false;
    for (const candidate of this.session.allowedRemoteHosts) {
      if (host === candidate || host.endsWith(`.${candidate}`)) allowed = true;
    }
    if (!allowed) {
      this.fail(id, 'external_url_blocked', 'GP-Next 请求打开了未授权网址');
      return;
    }
    this.context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
      .then((): void => this.complete(id, null))
      .catch((error: Error): void => this.fail(id, 'external_open_failed', error.message));
  }

  private async exportExistingFile(
    id: string,
    sourcePath: string,
    suggestedFileName: string,
    mimeType: string,
  ): Promise<void> {
    if (this.pickerActive) {
      if (sourcePath.startsWith(`${this.session.exportTemporaryRoot}/`)) {
        try { fs.unlinkSync(sourcePath); } catch (_error) {}
      }
      this.fail(id, 'export_in_progress', 'Another import or export picker is active');
      return;
    }
    this.pickerActive = true;
    try {
      const options = new picker.DocumentSaveOptions();
      const fileName = this.safeFileName(suggestedFileName);
      options.newFileNames = [fileName];
      const suffixChoices = ExportDocumentSpec.fileSuffixChoices(fileName, mimeType);
      if (suffixChoices.length > 0) {
        options.fileSuffixChoices = suffixChoices;
      }
      const targets = await withDocumentPickerOrientation(
        this.context,
        (): Promise<string[]> => new picker.DocumentViewPicker().save(options),
      );
      if (targets == null || targets.length === 0) {
        this.fail(id, 'export_cancelled', 'Export was cancelled');
        return;
      }
      this.copyFile(sourcePath, targets[0]);
      this.complete(id, null);
    } catch (error) {
      this.fail(id, 'export_failed', (error as Error).message);
    } finally {
      this.pickerActive = false;
      if (sourcePath.startsWith(`${this.session.exportTemporaryRoot}/`)) {
        try { fs.unlinkSync(sourcePath); } catch (_error) {}
      }
    }
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
      this.ensureDirectory(`${this.session.gpNextRoot}/packs`);
      this.ensureDirectory(`${this.session.gpNextRoot}/patches`);
      for (const uri of selected) {
        const name = this.safeFileName(uri);
        const extension = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
        const directory = extension === 'zip'
          ? `${this.session.gpNextRoot}/packs`
          : (extension === 'json' || extension === 'json5')
            ? `${this.session.gpNextRoot}/patches`
            : '';
        if (directory.length === 0) throw new Error(`不支持的 GP-Next 文件：${name}`);
        const destination = `${directory}/${name}`;
        const incoming = `${directory}/.${name}.incoming-${Date.now()}`;
        try {
          this.copyFile(uri, incoming);
          if (extension === 'json') {
            JSON.parse(fs.readTextSync(incoming));
          } else if (extension === 'zip') {
            if (!this.zipContainsRootPackJson(incoming)) {
              throw new Error(`${name} 缺少根目录 pack.json`);
            }
          } else if (fs.statSync(incoming).size === 0) {
            throw new Error(`${name} 是空文件`);
          }
          const existed = this.fileExists(destination);
          if (existed && !await this.confirmReplacement(name)) {
            continue;
          }
          const backup = `${directory}/.${name}.backup-${Date.now()}`;
          if (existed) fs.renameSync(destination, backup);
          try {
            fs.renameSync(incoming, destination);
            if (existed) fs.unlinkSync(backup);
          } catch (error) {
            if (existed && !this.fileExists(destination) && this.fileExists(backup)) {
              fs.renameSync(backup, destination);
            }
            throw new Error((error as Error).message);
          }
        } finally {
          if (this.fileExists(incoming)) fs.unlinkSync(incoming);
        }
      }
      this.complete(id, null);
    } catch (error) {
      this.fail(id, 'gp_next_import_failed', (error as Error).message);
    } finally {
      this.pickerActive = false;
    }
  }

  private async exportFile(id: string, args: BridgeArguments): Promise<void> {
    if (args.url == null || !this.isAllowedRemoteUrl(args.url)) {
      this.fail(id, 'unsupported_export', 'Export URL is not authorized');
      return;
    }
    try {
      await this.context.startAbility({ action: 'ohos.want.action.viewData', uri: args.url });
      this.complete(id, null);
    } catch (error) {
      this.fail(id, 'external_open_failed', (error as Error).message);
    }
  }

  private copyFile(sourcePath: string, targetUri: string): void {
    let input: fs.File | null = null;
    let output: fs.File | null = null;
    try {
      input = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      output = fs.openSync(targetUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.copyFileSync(input.fd, output.fd);
    } finally {
      if (output != null) fs.closeSync(output.fd);
      if (input != null) fs.closeSync(input.fd);
    }
  }

  private persistWatermark(enabled: boolean): void {
    const output = `${this.session.appRoot}/app_settings.json`;
    const temporary = `${output}.tmp`;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(
        temporary,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
      );
      fs.writeSync(file.fd, `${JSON.stringify({ watermarkEnabled: enabled }, null, 2)}\n`);
    } finally {
      if (file != null) {
        fs.closeSync(file.fd);
      }
    }
    fs.renameSync(temporary, output);
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

  private isAllowedRemoteUrl(url: string): boolean {
    if (!url.startsWith('https://')) return false;
    const host = url.substring(8).split('/')[0].split(':')[0].toLowerCase();
    for (const allowed of this.session.allowedRemoteHosts) {
      if (host === allowed || host.endsWith(`.${allowed}`)) return true;
    }
    return false;
  }

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

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

  private zipContainsRootPackJson(path: string): boolean {
    let file: fs.File | null = null;
    try {
      const size = fs.statSync(path).size;
      if (size < 22) return false;
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const tailLength = Math.min(size, 65557);
      const tailBuffer = new ArrayBuffer(tailLength);
      const tailCount = fs.readSync(file.fd, tailBuffer, { offset: size - tailLength, length: tailLength });
      if (tailCount !== tailLength) return false;
      const tail = new Uint8Array(tailBuffer);
      let eocd = -1;
      for (let index = tail.length - 22; index >= 0; index--) {
        if (tail[index] === 0x50 && tail[index + 1] === 0x4b &&
          tail[index + 2] === 0x05 && tail[index + 3] === 0x06) {
          eocd = index;
          break;
        }
      }
      if (eocd < 0) return false;
      const entryCount = this.uint16LE(tail, eocd + 10);
      let offset = this.uint32LE(tail, eocd + 16);
      const decoder = util.TextDecoder.create('utf-8');
      for (let entry = 0; entry < entryCount; entry++) {
        const headerBuffer = new ArrayBuffer(46);
        if (fs.readSync(file.fd, headerBuffer, { offset: offset, length: 46 }) !== 46) return false;
        const header = new Uint8Array(headerBuffer);
        if (this.uint32LE(header, 0) !== 0x02014b50) return false;
        const nameLength = this.uint16LE(header, 28);
        const extraLength = this.uint16LE(header, 30);
        const commentLength = this.uint16LE(header, 32);
        const nameBuffer = new ArrayBuffer(nameLength);
        if (fs.readSync(file.fd, nameBuffer, { offset: offset + 46, length: nameLength }) !== nameLength) {
          return false;
        }
        const name = decoder.decodeToString(new Uint8Array(nameBuffer)).replace(/\\/g, '/');
        if (name === 'pack.json') return true;
        offset += 46 + nameLength + extraLength + commentLength;
      }
      return false;
    } catch (_error) {
      return false;
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private uint16LE(bytes: Uint8Array, offset: number): number {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  private uint32LE(bytes: Uint8Array, offset: number): number {
    return (bytes[offset] | (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
  }

  private complete(id: string, value: BridgeValue): void {
    this.respond({ id: id, ok: true, value: value });
  }

  private fail(id: string, code: string, message: string): void {
    this.respond({ id: id, ok: false, error: { code: code, message: message } });
  }

  private respond(response: BridgeResponse, removeActive: boolean = true): void {
    if (removeActive) {
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
      const url = this.controller.getLastJavascriptProxyCallingFrameUrl();
      return url === GameSession.ORIGIN || url.startsWith(`${GameSession.ORIGIN}/`);
    } catch (_error) {
      return false;
    }
  }

  private ensureDirectory(path: string): void {
    try {
      if (fs.accessSync(path)) {
        return;
      }
    } catch (_error) {
      // Create the missing directory after its parent has been secured.
    }
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.length > 0) {
      this.ensureDirectory(parent);
    }
    fs.mkdirSync(path);
  }

  private safeFileName(value: string): string {
    const normalized = value.replace(/\\/g, '/');
    const base = normalized.substring(normalized.lastIndexOf('/') + 1);
    const cleaned = base.replace(/[\u0000-\u001f:*?"<>|]/g, '_').trim();
    return cleaned.length === 0 || cleaned === '.' || cleaned === '..'
      ? 'gardendless-export.json'
      : cleaned;
  }
}

class ChunkedExport {
  readonly token: string;
  readonly path: string;
  readonly file: fs.File;
  readonly expectedBytes: number;
  readonly mimeType: string;
  readonly fileName: string;
  written: number = 0;
  nextIndex: number = 0;

  constructor(
    token: string,
    path: string,
    file: fs.File,
    expectedBytes: number,
    mimeType: string,
    fileName: string,
  ) {
    this.token = token;
    this.path = path;
    this.file = file;
    this.expectedBytes = expectedBytes;
    this.mimeType = mimeType;
    this.fileName = fileName;
  }
}
