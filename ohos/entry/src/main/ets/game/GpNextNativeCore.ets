import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { GameSession } from './GameSession';
import { ExportDocumentSpec } from './ExportDocumentSpec';

export type GpNextValue = Object | string | number | boolean | null;

export interface GpNextResult {
  value: GpNextValue;
  exportPath?: string;
  exportHandle?: string;
  suggestedFilename?: string;
  mimeType?: string;
  openUrl?: string;
  importRequested?: boolean;
  selectionDirectory?: boolean;
}

interface GpNextArguments {
  path?: string;
  oldPath?: string;
  newPath?: string;
  url?: string;
  options?: GpNextOptions;
  mode?: string;
  destination?: string;
  totalBytes?: number;
  suggestedFilename?: string;
  mimeType?: string;
  handle?: string;
  index?: number;
  offset?: number;
  length?: number;
  data?: string;
  action?: string;
}

interface GpNextOptions {
  baseDir?: number;
  recursive?: boolean;
  directory?: boolean;
  multiple?: boolean;
  defaultPath?: string;
  oldPathBaseDir?: number;
  newPathBaseDir?: number;
  append?: boolean;
}

interface GpNextRequest {
  command: string;
  args?: GpNextArguments;
  options?: GpNextOptions;
}

interface FileBeginValue { handle: string; sizeBytes: number; }
interface FileChunkValue { data: string; }

interface GpNextFileInfo {
  isFile: boolean;
  isDirectory: boolean;
  isSymlink: boolean;
  size: number;
  mtime: Object | null;
  atime: Object | null;
  birthtime: Object | null;
  readonly: boolean;
  fileAttributes: Object | null;
  dev: number;
  ino: number;
  mode: number;
  nlink: number;
  uid: number;
  gid: number;
  rdev: number;
  blksize: number;
  blocks: number;
}

class GpNextDirectoryEntry {
  readonly name: string;
  readonly isFile: boolean;
  readonly isDirectory: boolean;
  readonly isSymlink: boolean;
  constructor(name: string, isFile: boolean, isDirectory: boolean, isSymlink: boolean) {
    this.name = name; this.isFile = isFile; this.isDirectory = isDirectory; this.isSymlink = isSymlink;
  }
}

class NativeFileTask {
  readonly operation: () => Promise<void>;
  readonly reject: (error: Error) => void;
  readonly control: boolean;
  constructor(operation: () => Promise<void>, reject: (error: Error) => void, control: boolean) {
    this.operation = operation;
    this.reject = reject;
    this.control = control;
  }
}

class FileTransfer {
  readonly path: string;
  readonly temporary: string | null;
  readonly file: fs.File;
  readonly mode: string;
  readonly export: boolean;
  readonly fileName: string;
  readonly mimeType: string;
  readonly size: number;
  readonly deadline: number = Date.now() + 10 * 60 * 1000;
  offset: number = 0;
  nextIndex: number = 0;
  status: string = 'active';
  busy: boolean = false;
  exportCancelled: (() => void) | null = null;
  finishResolved: (() => void) | null = null;
  readonly finishWait: Promise<void>;

  constructor(path: string, temporary: string | null, file: fs.File, mode: string,
    exporting: boolean, fileName: string, mimeType: string, size: number) {
    this.path = path;
    this.temporary = temporary;
    this.file = file;
    this.mode = mode;
    this.export = exporting;
    this.fileName = fileName;
    this.mimeType = mimeType;
    this.size = size;
    this.finishWait = new Promise<void>((resolve): void => { this.finishResolved = resolve; });
  }
}

export class FileFailure extends Error {
  readonly code: string;
  constructor(code: string, message: string) { super(message); this.code = code; }
}

// Owns the session's file descriptors and bounded asynchronous IO admission.
export class GpNextNativeCore {
  static readonly CHUNK_BYTES: number = 64 * 1024;
  static readonly MAX_FILE_BYTES: number = 512 * 1024 * 1024;
  private static readonly MAX_HANDLES: number = 8;
  private static readonly MAX_QUEUE: number = 16;
  private readonly session: GameSession;
  private readonly root: string;
  private readonly pendingExports: Set<string> = new Set<string>();
  private readonly handles: Map<string, FileTransfer> = new Map<string, FileTransfer>();
  private readonly finished: Map<string, string> = new Map<string, string>();
  private readonly openingPaths: Set<string> = new Set<string>();
  private readonly files: Map<number, string | null> = new Map<number, string | null>();
  private readonly queue: NativeFileTask[] = [];
  private running: number = 0;
  private destroyed: boolean = false;
  private readonly expiryTimer: number;

  constructor(session: GameSession) {
    this.session = session;
    this.root = session.gpNextRoot.replace(/\/$/, '');
    this.expiryTimer = setInterval((): void => { this.expireHandles(); }, 60 * 1000);
  }

  runIO<T>(operation: () => Promise<T>, control: boolean = false): Promise<T> {
    if (this.destroyed) return Promise.reject(new FileFailure('host_destroyed', 'Game host was destroyed'));
    return new Promise<T>((resolve, reject): void => {
      const task = new NativeFileTask(async (): Promise<void> => {
        try {
          this.checkActive();
          const value = await operation();
          this.checkActive();
          resolve(value);
        } catch (error) { reject(error as Error); }
      }, reject, control);
      if (this.queue.length >= GpNextNativeCore.MAX_QUEUE) {
        if (!control) { reject(new FileFailure('resource_limit_exceeded', 'File task queue is full')); return; }
        const displaced = this.queue.pop();
        displaced?.reject(new FileFailure('resource_limit_exceeded', 'File task displaced by cancellation'));
      }
      if (control) this.queue.unshift(task); else this.queue.push(task);
      this.drain();
    });
  }

  private drain(): void {
    while (!this.destroyed && this.running < 2 && this.queue.length > 0) {
      const task = this.queue.shift();
      if (task == null) return;
      this.running++;
      task.operation().finally((): void => { this.running--; this.drain(); });
    }
  }

  invoke(raw: Object): Promise<GpNextResult> {
    const request = raw as GpNextRequest;
    const args = request.args ?? {};
    const control = request.command === 'file:finish' && (args.action === 'close' || args.action === 'cancel');
    // Cancellation claims the terminal state and starts descriptor closure immediately,
    // even while both IO slots or the admission queue are occupied.
    if (request.command === 'file:finish' && args.action === 'cancel' && args.handle != null) {
      const state = this.handles.get(args.handle);
      if (state != null && (state.status === 'active' || state.status === 'exportPending')) {
        state.status = 'cancelled';
        state.exportCancelled?.();
        this.closeFiles(args.handle).catch((_error: Error): void => {});
      }
    }
    return this.runIO(async (): Promise<GpNextResult> => {
      const options = request.options ?? {};
      if (!request.command.startsWith('file:')) {
        this.requireGpNext();
        await this.ensureGpDirectories();
      }
      switch (request.command) {
        case 'file:begin': return this.beginFile(args);
        case 'file:chunk': return this.chunkFile(args);
        case 'file:finish': return this.finishFile(args);
        case 'plugin:fs|mkdir':
          await this.ensureDirectory(await this.resolve(args.path, args.options ?? options));
          return { value: null };
        case 'plugin:fs|read_dir':
          return { value: await this.readDirectory(await this.resolve(args.path, args.options ?? options)) };
        case 'plugin:fs|lstat':
          return { value: await this.fileInfo(await this.resolve(args.path, args.options ?? options)) };
        case 'plugin:fs|exists':
          return { value: await this.exists(await this.resolve(args.path, args.options ?? options)) };
        case 'plugin:fs|remove':
          await this.remove(await this.resolve(args.path, args.options ?? options), (args.options ?? options).recursive !== false);
          return { value: null };
        case 'plugin:fs|rename':
          await this.rename(args, args.options ?? options);
          return { value: null };
        case 'plugin:dialog|open': {
          const dialogOptions = args.options ?? {};
          if (dialogOptions.multiple === true) throw new FileFailure('unsupported', 'GP-Next 仅支持选择一个 Mod 包');
          return { value: null, selectionDirectory: dialogOptions.directory === true };
        }
        case 'plugin:dialog|save': return { value: await this.prepareExport(args) };
        case 'plugin:opener|open_url': return { value: null, openUrl: args.url ?? '' };
        case 'plugin:opener|open_path': return { value: null, importRequested: true };
        default: throw new FileFailure('unsupported', 'Unsupported native command');
      }
    }, control);
  }

  checkActive(): void {
    if (this.destroyed) throw new FileFailure('host_destroyed', 'Game host was destroyed');
  }

  private rethrow(error: Error): never {
    if (error instanceof FileFailure) throw new FileFailure(error.code, error.message);
    throw new FileFailure('io_failed', 'File operation failed');
  }

  private requireGpNext(): void {
    if (!this.session.hasGpNext || !this.session.gpNextCompatible) {
      throw new FileFailure('gp_next_unavailable', 'GP-Next compatibility is unavailable');
    }
  }

  private async ensureGpDirectories(): Promise<void> {
    await this.ensureDirectory(this.root);
    await this.ensureDirectory(`${this.root}/packs`);
    await this.ensureDirectory(`${this.root}/patches`);
  }

  private integer(value: number | undefined, maximum: number): number {
    if (value == null || !Number.isSafeInteger(value) || value < 0 || value > maximum) {
      throw new FileFailure('invalid_file_transfer', 'Invalid file integer');
    }
    return value;
  }

  private async beginFile(args: GpNextArguments): Promise<GpNextResult> {
    if (args.mode !== 'read' && args.mode !== 'write') throw new FileFailure('invalid_file_transfer', 'Invalid file mode');
    if (args.destination !== 'gp-next' && args.destination !== 'export') throw new FileFailure('invalid_file_transfer', 'Invalid destination');
    if (args.options?.append === true) throw new FileFailure('unsupported', 'Append writes are unsupported');
    const handle = util.generateRandomUUID();
    let path: string;
    let exporting = args.destination === 'export';
    if (args.destination === 'gp-next') {
      this.requireGpNext();
      await this.ensureGpDirectories();
      path = await this.resolve(args.path, args.options ?? {});
      exporting = this.pendingExports.has(path);
    } else {
      if (args.mode !== 'write') throw new FileFailure('unsupported', 'Export is write-only');
      await this.ensureDirectory(this.session.exportTemporaryRoot);
      path = `${this.session.exportTemporaryRoot}/.export-${handle}`;
    }
    if (args.mode === 'read' && exporting) throw new FileFailure('unsupported', 'Export is write-only');
    this.checkActive();
    if (this.handles.size + this.openingPaths.size >= GpNextNativeCore.MAX_HANDLES) {
      throw new FileFailure('resource_limit_exceeded', 'Too many open files');
    }
    if (this.openingPaths.has(path)) throw new FileFailure('invalid_file_transfer', 'File is already being opened');
    for (const state of this.handles.values()) {
      if (args.mode === 'write' && state.path === path && state.mode === 'write') {
        throw new FileFailure('invalid_file_transfer', 'File already has an active writer');
      }
    }
    this.openingPaths.add(path);
    let file: fs.File | null = null;
    let temporary: string | null = null;
    try {
      let size: number;
      if (args.mode === 'read') {
        file = await this.openFile(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW, handle);
        const stat = await fs.stat(file.fd);
        if (!stat.isFile()) throw new FileFailure('invalid_file_transfer', 'Source is not a file');
        size = stat.size;
      } else {
        size = this.integer(args.totalBytes, GpNextNativeCore.MAX_FILE_BYTES);
        await this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
        await this.assertNoSymlink(path);
        temporary = `${path.substring(0, path.lastIndexOf('/'))}/.gardendless-write-${handle}`;
        file = await this.openFile(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW, handle);
      }
      if (size > GpNextNativeCore.MAX_FILE_BYTES) throw new FileFailure('resource_limit_exceeded', 'File exceeds 512 MiB');
      this.checkActive();
      const fileName = ExportDocumentSpec.safeFileName(args.suggestedFilename ?? (args.destination === 'export' ? 'gardendless-export.json' : path));
      this.handles.set(handle, new FileTransfer(path, temporary, file, args.mode, exporting,
        fileName, args.mimeType ?? 'application/octet-stream', size));
      file = null;
      const value: FileBeginValue = { handle: handle, sizeBytes: size };
      return { value: value };
    } catch (error) {
      if (file != null) await this.closeFile(file);
      if (temporary != null) await this.discardTemporary(temporary);
      this.rethrow(error as Error);
    } finally { this.openingPaths.delete(path); }
  }

  private getHandle(handle: string | undefined): FileTransfer {
    const state = handle == null ? undefined : this.handles.get(handle);
    if (state == null) throw new FileFailure('invalid_file_transfer', 'File handle is not active');
    return state;
  }

  private checkTransfer(state: FileTransfer): void {
    this.checkActive();
    if (state.status === 'cancelled') throw new FileFailure('cancelled', 'File transaction was cancelled');
    if (Date.now() > state.deadline) throw new FileFailure('deadline_exceeded', 'File transaction expired');
  }

  private async chunkFile(args: GpNextArguments): Promise<GpNextResult> {
    const state = this.getHandle(args.handle);
    this.checkTransfer(state);
    if (state.status !== 'active' || state.busy) throw new FileFailure('invalid_file_transfer', 'File transaction is busy');
    const index = this.integer(args.index, GpNextNativeCore.MAX_FILE_BYTES);
    const offset = this.integer(args.offset, GpNextNativeCore.MAX_FILE_BYTES);
    if (index !== state.nextIndex || offset !== state.offset) throw new FileFailure('invalid_file_transfer', 'File chunk sequence is invalid');
    state.busy = true;
    try {
      let bytes: Uint8Array;
      if (state.mode === 'read') {
        const length = this.integer(args.length, GpNextNativeCore.CHUNK_BYTES);
        if (length === 0 || length > state.size - state.offset) throw new FileFailure('invalid_file_transfer', 'Invalid read length');
        const buffer = new ArrayBuffer(length);
        const count = await fs.read(state.file.fd, buffer, { offset: offset, length: length });
        if (count !== length) throw new FileFailure('io_failed', 'File read was incomplete');
        bytes = new Uint8Array(buffer);
      } else {
        const data = args.data;
        if (data == null || data.length > Math.ceil(GpNextNativeCore.CHUNK_BYTES / 3) * 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(data)) {
          throw new FileFailure('invalid_file_transfer', 'Invalid Base64 chunk');
        }
        bytes = await new util.Base64Helper().decode(data, util.Type.BASIC);
        if (bytes.length === 0 || bytes.length > GpNextNativeCore.CHUNK_BYTES || bytes.length > state.size - state.offset ||
          await new util.Base64Helper().encodeToString(bytes, util.Type.BASIC) !== data) {
          throw new FileFailure('invalid_file_transfer', 'Invalid file chunk size or encoding');
        }
        this.checkTransfer(state);
        const count = await fs.write(state.file.fd, bytes.buffer, { offset: offset, length: bytes.length });
        if (count !== bytes.length) throw new FileFailure('io_failed', 'File write was incomplete');
      }
      this.checkTransfer(state);
      state.offset += bytes.length;
      state.nextIndex++;
      if (state.mode === 'read') {
        const value: FileChunkValue = { data: await new util.Base64Helper().encodeToString(bytes, util.Type.BASIC) };
        this.checkTransfer(state);
        return { value: value };
      }
      return { value: null };
    } finally { state.busy = false; }
  }

  private async finishFile(args: GpNextArguments): Promise<GpNextResult> {
    const handle = args.handle ?? '';
    const action = args.action;
    if (action !== 'close' && action !== 'commit' && action !== 'cancel') throw new FileFailure('invalid_file_transfer', 'Invalid finish action');
    const terminal = this.finished.get(handle);
    if (terminal != null) {
      if (terminal === 'cancelled' && action !== 'cancel') throw new FileFailure('cancelled', 'File transaction was cancelled');
      if (terminal === 'failed') throw new FileFailure('io_failed', 'File transaction failed');
      return { value: null };
    }
    const state = this.getHandle(handle);
    if (action === 'cancel') {
      if (state.status === 'committing' || state.status === 'closing') {
        await state.finishWait;
        if (this.finished.get(handle) === 'failed') throw new FileFailure('io_failed', 'File transaction failed');
        return { value: null };
      }
      state.status = 'cancelled';
      state.exportCancelled?.();
      await this.closeFiles(handle);
      await this.finishHandle(handle, state, 'cancelled');
      return { value: null };
    }
    this.checkTransfer(state);
    if (state.busy || state.status !== 'active') throw new FileFailure('invalid_file_transfer', 'File transaction is busy');
    if ((state.mode === 'read' && action !== 'close') || (state.mode === 'write' && action !== 'commit')) {
      throw new FileFailure('invalid_file_transfer', 'Invalid finish action for file mode');
    }
    state.busy = true;
    try {
      if (action === 'close') {
        state.status = 'closing';
        await this.closeFile(state.file);
        await this.finishHandle(handle, state, 'closed');
        return { value: null };
      }
      if (state.offset !== state.size) throw new FileFailure('invalid_file_transfer', 'File transaction is incomplete');
      await fs.fsync(state.file.fd);
      await this.closeFile(state.file);
      this.checkTransfer(state);
      if (state.temporary == null) throw new FileFailure('invalid_file_transfer', 'Write transaction has no temporary file');
      if (state.export) {
        state.status = 'exportPending';
        return { value: null, exportHandle: handle, exportPath: state.temporary,
          suggestedFilename: state.fileName, mimeType: state.mimeType };
      }
      await this.assertNoSymlink(state.path);
      this.checkTransfer(state);
      // This synchronous check/claim/rename-dispatch is one ArkTS event-loop
      // critical section shared with destroy(). Destroy honours an already
      // dispatched commit and never removes its temporary file.
      state.status = 'committing';
      try {
        await fs.rename(state.temporary, state.path);
        await this.finishHandle(handle, state, 'committed');
      } catch (error) {
        await this.finishHandle(handle, state, 'failed');
        this.rethrow(error as Error);
      }
      return { value: null };
    } finally { state.busy = false; }
  }

  setExportCancellation(handle: string, callback: () => void): void {
    const state = this.getHandle(handle);
    this.checkTransfer(state);
    state.exportCancelled = callback;
  }

  isFileActive(handle: string): boolean {
    const state = this.handles.get(handle);
    return !this.destroyed && state != null && (state.status === 'active' || state.status === 'exportPending') && Date.now() <= state.deadline;
  }

  async exportFinished(handle: string, succeeded: boolean): Promise<void> {
    const state = this.handles.get(handle);
    if (state == null || state.status !== 'exportPending') return;
    await this.finishHandle(handle, state, succeeded ? 'committed' : 'failed');
  }

  private async finishHandle(handle: string, state: FileTransfer, terminal: string): Promise<void> {
    state.status = terminal;
    this.handles.delete(handle);
    this.finished.set(handle, terminal);
    state.finishResolved?.();
    if (terminal === 'committed') this.pendingExports.delete(state.path);
    if (this.finished.size > 128) {
      for (const key of this.finished.keys()) { this.finished.delete(key); break; }
    }
    if (state.temporary != null) await this.discardTemporary(state.temporary);
  }

  private expireHandles(): void {
    for (const entry of this.handles.entries()) {
      const handle = entry[0];
      const state = entry[1];
      if (Date.now() <= state.deadline || state.status === 'committing' || state.status === 'closing') continue;
      state.status = 'cancelled';
      state.exportCancelled?.();
      this.closeFiles(handle).then((): Promise<void> => this.finishHandle(handle, state, 'failed'))
        .catch((_error: Error): void => {});
    }
  }

  async openFile(path: string, mode: number, handle: string | null = null): Promise<fs.File> {
    this.checkActive();
    const file = await fs.open(path, mode);
    if (this.destroyed) { await fs.close(file.fd); this.checkActive(); }
    this.files.set(file.fd, handle);
    return file;
  }

  async closeFile(file: fs.File): Promise<void> {
    if (!this.files.has(file.fd)) return;
    this.files.delete(file.fd);
    await fs.close(file.fd);
  }

  private async closeFiles(handle: string | null = null): Promise<void> {
    const closing: Promise<void>[] = [];
    for (const entry of this.files.entries()) {
      if (handle != null && entry[1] !== handle) continue;
      this.files.delete(entry[0]);
      closing.push(fs.close(entry[0]).catch((_error: Error): void => {}));
    }
    await Promise.all(closing);
  }

  async copyFile(sourcePath: string, target: string, handle: string | null = null): Promise<void> {
    let input: fs.File | null = null;
    let output: fs.File | null = null;
    try {
      input = await this.openFile(sourcePath, fs.OpenMode.READ_ONLY, handle);
      output = await this.openFile(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC, handle);
      const size = (await fs.stat(input.fd)).size;
      if (size > GpNextNativeCore.MAX_FILE_BYTES) throw new FileFailure('resource_limit_exceeded', 'File exceeds 512 MiB');
      let offset = 0;
      while (offset < size) {
        this.checkActive();
        if (handle != null && !this.isFileActive(handle)) throw new FileFailure('cancelled', 'File transaction was cancelled');
        const length = Math.min(GpNextNativeCore.CHUNK_BYTES, size - offset);
        const buffer = new ArrayBuffer(length);
        if (await fs.read(input.fd, buffer, { offset: offset, length: length }) !== length) throw new FileFailure('io_failed', 'File read was incomplete');
        if (await fs.write(output.fd, buffer, { offset: offset, length: length }) !== length) throw new FileFailure('io_failed', 'File write was incomplete');
        offset += length;
      }
      await fs.fsync(output.fd);
    } finally {
      if (input != null) await this.closeFile(input);
      if (output != null) await this.closeFile(output);
    }
  }

  destroy(): void {
    this.destroyed = true;
    clearInterval(this.expiryTimer);
    for (const task of this.queue.splice(0)) task.reject(new FileFailure('host_destroyed', 'Game host was destroyed'));
    const temporary: string[] = [];
    for (const state of this.handles.values()) {
      if (state.status === 'committing') continue;
      state.status = 'cancelled';
      state.exportCancelled?.();
      if (state.temporary != null) temporary.push(state.temporary);
    }
    this.handles.clear();
    this.pendingExports.clear();
    this.closeFiles().then(async (): Promise<void> => {
      for (const path of temporary) await this.discardTemporary(path);
    }).catch((_error: Error): void => {});
  }

  private async discardTemporary(path: string): Promise<void> {
    try { await fs.unlink(path); } catch (_error) {}
  }

  private async prepareExport(args: GpNextArguments): Promise<string> {
    const name = ExportDocumentSpec.safeFileName(args.options?.defaultPath ?? 'gardendless-export.json');
    await this.ensureDirectory(this.session.exportTemporaryRoot);
    const path = `${this.session.exportTemporaryRoot}/${name}`;
    if (this.pendingExports.size >= GpNextNativeCore.MAX_HANDLES && !this.pendingExports.has(path)) {
      throw new FileFailure('resource_limit_exceeded', 'Too many pending exports');
    }
    this.pendingExports.add(path);
    return path;
  }

  private async readDirectory(path: string): Promise<Object> {
    await this.assertNoSymlink(path);
    if (!(await fs.stat(path)).isDirectory()) throw new FileFailure('invalid_file_transfer', 'Path is not a directory');
    const entries: GpNextDirectoryEntry[] = [];
    const names = (await fs.listFile(path)).sort();
    for (const name of names) {
      this.checkActive();
      const stat = await fs.lstat(`${path}/${name}`);
      entries.push(new GpNextDirectoryEntry(name, stat.isFile() && !stat.isSymbolicLink(),
        stat.isDirectory() && !stat.isSymbolicLink(), stat.isSymbolicLink()));
    }
    return entries;
  }

  private async fileInfo(path: string): Promise<GpNextFileInfo> {
    await this.assertNoSymlink(path);
    const stat = await fs.lstat(path);
    return { isFile: stat.isFile(), isDirectory: stat.isDirectory(), isSymlink: stat.isSymbolicLink(),
      size: stat.isFile() ? stat.size : 0, mtime: null, atime: null, birthtime: null, readonly: false,
      fileAttributes: null, dev: 0, ino: 0, mode: 0, nlink: 0, uid: 0, gid: 0, rdev: 0, blksize: 0, blocks: 0 };
  }

  private async rename(args: GpNextArguments, options: GpNextOptions): Promise<void> {
    const source = await this.resolve(args.oldPath, { baseDir: options.oldPathBaseDir });
    const destination = await this.resolve(args.newPath, { baseDir: options.newPathBaseDir });
    if (source === this.root || !await this.exists(source) || await this.exists(destination)) {
      throw new FileFailure('invalid_file_transfer', 'Invalid GP-Next rename');
    }
    await this.ensureDirectory(destination.substring(0, destination.lastIndexOf('/')));
    await this.assertNoSymlink(source);
    await this.assertNoSymlink(destination);
    this.checkActive();
    await fs.rename(source, destination);
  }

  private async exists(path: string): Promise<boolean> {
    await this.assertNoSymlink(path);
    return fs.access(path);
  }

  private async remove(path: string, recursive: boolean): Promise<void> {
    this.checkActive();
    await this.assertNoSymlink(path);
    if (path === this.root) throw new FileFailure('invalid_file_transfer', 'Cannot remove GP-Next root');
    if (!await this.exists(path)) return;
    const stat = await fs.lstat(path);
    if (stat.isSymbolicLink()) throw new FileFailure('invalid_file_transfer', 'Symbolic links are forbidden');
    if (stat.isDirectory()) {
      if (!recursive) throw new FileFailure('invalid_file_transfer', 'Directory removal requires recursive=true');
      for (const name of await fs.listFile(path)) await this.remove(`${path}/${name}`, true);
      await fs.rmdir(path);
    } else await fs.unlink(path);
  }

  private async resolve(value: string | undefined, options: GpNextOptions): Promise<string> {
    if (value == null || value.trim().length === 0) throw new FileFailure('invalid_file_transfer', 'File path is empty');
    if (options.baseDir != null && options.baseDir !== 14) throw new FileFailure('invalid_file_transfer', 'Tauri baseDir is not authorized');
    let raw = value.trim().replace(/\\/g, '/');
    if (raw.startsWith('file://')) raw = raw.substring(7);
    if (raw.includes('\u0000')) throw new FileFailure('invalid_file_transfer', 'Invalid file path');
    const parts = raw.split('/').filter((part: string): boolean => part.length > 0);
    if (parts.includes('.') || parts.includes('..')) throw new FileFailure('invalid_file_transfer', 'Path escaped the sandbox');
    const namespaceIndex = parts.indexOf('gp-next');
    if (namespaceIndex < 0 || (!raw.startsWith('/') && namespaceIndex !== 0)) throw new FileFailure('invalid_file_transfer', 'Path escaped the sandbox');
    let normalized = this.root;
    for (let index = namespaceIndex + 1; index < parts.length; index++) normalized += `/${parts[index]}`;
    await this.assertNoSymlink(normalized);
    return normalized;
  }

  private async assertNoSymlink(target: string): Promise<void> {
    if (target !== this.root && !target.startsWith(`${this.root}/`)) throw new FileFailure('invalid_file_transfer', 'Path escaped the sandbox');
    const parts = target.substring(this.root.length).split('/').filter((part: string): boolean => part.length > 0);
    let current = this.root;
    for (let index = -1; index < parts.length; index++) {
      if (index >= 0) current += `/${parts[index]}`;
      try {
        if ((await fs.lstat(current)).isSymbolicLink()) throw new FileFailure('invalid_file_transfer', 'Symbolic links are forbidden');
      } catch (error) {
        if ((error as BusinessError).code === 13900002) return;
        this.rethrow(error as Error);
      }
    }
  }

  private async ensureDirectory(path: string): Promise<void> {
    this.checkActive();
    await this.assertNoSymlink(path);
    if (await fs.access(path)) {
      if (!(await fs.stat(path)).isDirectory()) throw new FileFailure('invalid_file_transfer', 'Path is not a directory');
      return;
    }
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.length >= this.root.length) await this.ensureDirectory(parent);
    try { await fs.mkdir(path); } catch (error) {
      if (!(await fs.stat(path)).isDirectory()) this.rethrow(error as Error);
    }
    await this.assertNoSymlink(path);
  }
}
