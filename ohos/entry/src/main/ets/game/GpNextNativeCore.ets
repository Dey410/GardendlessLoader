import fs from '@ohos.file.fs';
import { GameSession } from './GameSession';

export type GpNextValue = Object | string | number | boolean | null;

export interface GpNextResult {
  value: GpNextValue;
  exportPath?: string;
  openUrl?: string;
  importRequested?: boolean;
  selectionDirectory?: boolean;
}

interface GpNextArguments {
  path?: string;
  oldPath?: string;
  newPath?: string;
  url?: string;
  directory?: number;
  options?: GpNextOptions;
  __gardendlessBytes?: number[];
  __gardendlessTransfer?: GpNextWriteTransfer;
}

interface GpNextWriteTransfer {
  token: string;
  index?: number;
  totalBytes?: number;
  final?: boolean;
  abort?: boolean;
}

interface GpNextOptions {
  baseDir?: number;
  recursive?: boolean;
  directory?: boolean;
  multiple?: boolean;
  defaultPath?: string;
  oldPathBaseDir?: number;
  newPathBaseDir?: number;
  headers?: GpNextHeaders;
}

interface GpNextHeaders {
  path?: string;
  options?: string;
}

interface GpNextRequest {
  command: string;
  args?: GpNextArguments;
  options?: GpNextOptions;
}

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
    this.name = name;
    this.isFile = isFile;
    this.isDirectory = isDirectory;
    this.isSymlink = isSymlink;
  }
}

export class GpNextNativeCore {
  private readonly session: GameSession;
  private readonly root: string;
  private readonly pendingExports: Set<string> = new Set<string>();
  private readonly pendingWrites: Map<string, PendingWrite> = new Map<string, PendingWrite>();

  constructor(session: GameSession) {
    this.session = session;
    this.root = session.gpNextRoot.replace(/\/$/, '');
    this.ensureDirectory(this.root);
    this.ensureDirectory(`${this.root}/packs`);
    this.ensureDirectory(`${this.root}/patches`);
  }

  invoke(raw: Object): GpNextResult {
    const request = raw as GpNextRequest;
    const args = request.args ?? {};
    const options = request.options ?? {};
    switch (request.command) {
      case 'plugin:fs|mkdir':
        this.ensureDirectory(this.resolve(args.path, args.options ?? options));
        return { value: null };
      case 'plugin:fs|read_dir':
        return { value: this.readDirectory(this.resolve(args.path, args.options ?? options)) };
      case 'plugin:fs|read_file':
      case 'plugin:fs|read_text_file':
        return { value: this.readFile(this.resolve(args.path, args.options ?? options)) };
      case 'plugin:fs|lstat':
        return { value: this.fileInfo(this.resolve(args.path, args.options ?? options)) };
      case 'plugin:fs|exists':
        return { value: this.exists(this.resolve(args.path, args.options ?? options)) };
      case 'plugin:fs|remove':
        this.remove(this.resolve(args.path, args.options ?? options), (args.options ?? options).recursive !== false);
        return { value: null };
      case 'plugin:fs|write_file':
      case 'plugin:fs|write_text_file':
        return this.writeFile(args, options);
      case 'plugin:fs|rename':
        this.rename(args, args.options ?? options);
        return { value: null };
      case 'plugin:dialog|open': {
        const dialogOptions = args.options ?? {};
        if (dialogOptions.multiple === true) throw new Error('GP-Next 仅支持选择一个 Mod 包');
        return { value: null, selectionDirectory: dialogOptions.directory === true };
      }
      case 'plugin:dialog|save':
        return { value: this.prepareExport(args) };
      case 'plugin:opener|open_url':
        return { value: null, openUrl: args.url ?? '' };
      case 'plugin:opener|open_path':
        return { value: null, importRequested: true };
      default:
        throw new Error(`未兼容的 GP-Next 命令：${request.command}`);
    }
  }

  private readDirectory(path: string): Object {
    this.assertNoSymlink(path);
    if (!fs.statSync(path).isDirectory()) {
      throw new Error(`目录不存在：${path}`);
    }
    const entries: GpNextDirectoryEntry[] = [];
    const names = fs.listFileSync(path).sort();
    for (const name of names) {
      const child = `${path}/${name}`;
      const stat = fs.lstatSync(child);
      entries.push(new GpNextDirectoryEntry(
        name,
        stat.isFile(),
        stat.isDirectory(),
        stat.isSymbolicLink(),
      ));
    }
    return entries;
  }

  private readFile(path: string): Object {
    this.assertNoSymlink(path);
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      throw new Error(`文件不存在：${path}`);
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const values: number[] = [];
      let offset = 0;
      while (offset < stat.size) {
        const length = Math.min(64 * 1024, stat.size - offset);
        const buffer = new ArrayBuffer(length);
        const count = fs.readSync(file.fd, buffer, { offset: offset, length: length });
        if (count <= 0) break;
        const bytes = new Uint8Array(buffer, 0, count);
        for (let index = 0; index < bytes.length; index++) values.push(bytes[index]);
        offset += count;
      }
      return values;
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private fileInfo(path: string): GpNextFileInfo {
    this.assertNoSymlink(path);
    const stat = fs.lstatSync(path);
    return {
      isFile: stat.isFile(),
      isDirectory: stat.isDirectory(),
      isSymlink: stat.isSymbolicLink(),
      size: stat.isFile() ? stat.size : 0,
      mtime: null,
      atime: null,
      birthtime: null,
      readonly: false,
      fileAttributes: null,
      dev: 0,
      ino: 0,
      mode: 0,
      nlink: 0,
      uid: 0,
      gid: 0,
      rdev: 0,
      blksize: 0,
      blocks: 0,
    };
  }

  private writeFile(args: GpNextArguments, options: GpNextOptions): GpNextResult {
    if (args.__gardendlessTransfer != null) {
      return this.writeFileChunk(args, options, args.__gardendlessTransfer);
    }
    const headers = options.headers ?? {};
    let headerOptions: GpNextOptions = {};
    if (headers.options != null && headers.options !== 'undefined') {
      try {
        headerOptions = JSON.parse(headers.options) as GpNextOptions;
      } catch (_error) {
      }
    }
    const path = this.resolve(
      headers.path == null ? args.path : decodeURIComponent(headers.path),
      headerOptions,
    );
    const bytes = args.__gardendlessBytes;
    if (bytes == null) {
      throw new Error('GP-Next 写入内容不是字节数组');
    }
    this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
    this.assertNoSymlink(path);
    const encoded = new Uint8Array(bytes.length);
    for (let index = 0; index < bytes.length; index++) encoded[index] = bytes[index];
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, encoded.buffer);
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
    if (this.pendingExports.has(path)) {
      this.pendingExports.delete(path);
      return { value: null, exportPath: path };
    }
    return { value: null };
  }

  private writeFileChunk(
    args: GpNextArguments,
    options: GpNextOptions,
    transfer: GpNextWriteTransfer,
  ): GpNextResult {
    if (!/^[A-Za-z0-9-]{1,96}$/.test(transfer.token)) {
      throw new Error('GP-Next 分块写入 token 无效');
    }
    if (transfer.abort === true) {
      this.clearPendingWrite(transfer.token);
      return { value: null };
    }
    const bytes = args.__gardendlessBytes;
    const index = transfer.index ?? -1;
    const total = transfer.totalBytes ?? -1;
    if (bytes == null || bytes.length > 96 * 1024 || total < 0 || total > 512 * 1024 * 1024) {
      throw new Error('GP-Next 写入分块无效');
    }
    const headers = options.headers ?? {};
    let headerOptions: GpNextOptions = {};
    if (headers.options != null && headers.options !== 'undefined') {
      try {
        headerOptions = JSON.parse(headers.options) as GpNextOptions;
      } catch (_error) {
      }
    }
    const path = this.resolve(
      headers.path == null ? args.path : decodeURIComponent(headers.path),
      headerOptions,
    );
    let state: PendingWrite;
    if (index === 0) {
      if (this.pendingWrites.has(transfer.token)) throw new Error('GP-Next 分块写入已存在');
      this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
      const temporary = `${path.substring(0, path.lastIndexOf('/'))}/.gardendless-write-${transfer.token}`;
      if (this.exists(temporary)) throw new Error('GP-Next 分块临时文件已存在');
      state = new PendingWrite(path, temporary, total);
      this.pendingWrites.set(transfer.token, state);
    } else {
      const existing = this.pendingWrites.get(transfer.token);
      if (existing == null) throw new Error('GP-Next 分块写入不存在');
      state = existing;
    }
    if (state.path !== path || state.nextIndex !== index || state.expectedBytes !== total) {
      throw new Error('GP-Next 分块写入顺序无效');
    }
    const encoded = new Uint8Array(bytes.length);
    for (let position = 0; position < bytes.length; position++) encoded[position] = bytes[position];
    let file: fs.File | null = null;
    try {
      const mode = index === 0
        ? fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
        : fs.OpenMode.READ_WRITE;
      file = fs.openSync(state.temporary, mode);
      fs.writeSync(file.fd, encoded.buffer, { offset: state.written, length: encoded.length });
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
    state.written += encoded.length;
    state.nextIndex += 1;
    if (state.written > state.expectedBytes) throw new Error('GP-Next 分块写入超出声明大小');
    if (transfer.final !== true) return { value: null };
    if (state.written !== state.expectedBytes) throw new Error('GP-Next 分块写入不完整');
    this.pendingWrites.delete(transfer.token);
    fs.renameSync(state.temporary, state.path);
    if (this.pendingExports.has(path)) {
      this.pendingExports.delete(path);
      return { value: null, exportPath: path };
    }
    return { value: null };
  }

  private clearPendingWrite(token: string): void {
    const state = this.pendingWrites.get(token);
    this.pendingWrites.delete(token);
    if (state != null && this.exists(state.temporary)) fs.unlinkSync(state.temporary);
  }

  destroy(): void {
    for (const token of this.pendingWrites.keys()) this.clearPendingWrite(token);
  }

  private prepareExport(args: GpNextArguments): string {
    const name = this.safeFileName(args.options?.defaultPath ?? 'gardendless-export.json');
    this.ensureDirectory(this.session.exportTemporaryRoot);
    const path = `${this.session.exportTemporaryRoot}/${name}`;
    this.pendingExports.add(path);
    return path;
  }

  private rename(args: GpNextArguments, options: GpNextOptions): void {
    const source = this.resolve(args.oldPath, { baseDir: options.oldPathBaseDir });
    const destination = this.resolve(args.newPath, { baseDir: options.newPathBaseDir });
    if (source === this.root) throw new Error('不允许移动 GP-Next 根目录');
    if (!this.exists(source)) throw new Error(`源路径不存在：${source}`);
    if (this.exists(destination)) throw new Error(`目标路径已存在：${destination}`);
    this.ensureDirectory(destination.substring(0, destination.lastIndexOf('/')));
    this.assertNoSymlink(source);
    this.assertNoSymlink(destination);
    fs.renameSync(source, destination);
  }

  private exists(path: string): boolean {
    this.assertNoSymlink(path);
    try {
      return fs.accessSync(path);
    } catch (_error) {
      return false;
    }
  }

  private remove(path: string, recursive: boolean): void {
    this.assertNoSymlink(path);
    if (path === this.root) throw new Error('不允许删除 GP-Next 根目录');
    if (!this.exists(path)) return;
    const stat = fs.lstatSync(path);
    if (stat.isSymbolicLink()) throw new Error('不允许操作符号链接');
    if (stat.isDirectory()) {
      if (!recursive) throw new Error('目录删除需要 recursive=true');
      for (const name of fs.listFileSync(path)) {
        this.remove(`${path}/${name}`, true);
      }
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  }

  private resolve(value: string | undefined, options: GpNextOptions): string {
    if (value == null || value.trim().length === 0) throw new Error('GP-Next 文件路径为空');
    if (options.baseDir != null && options.baseDir !== 14) {
      throw new Error(`不允许访问 Tauri baseDir ${options.baseDir}`);
    }
    let raw = value.trim().replace(/\\/g, '/');
    if (raw.startsWith('file://')) raw = raw.substring(7);
    const normalized = this.resolveGpNextNamespacePath(raw);
    this.assertNoSymlink(normalized);
    return normalized;
  }

  private resolveGpNextNamespacePath(raw: string): string {
    const parts = raw.split('/').filter((part: string): boolean => part.length > 0);
    for (const part of parts) {
      if (part === '.' || part === '..') throw new Error('GP-Next 路径超出 Loader 沙箱');
    }
    const namespaceIndex = parts.indexOf('gp-next');
    if (namespaceIndex < 0 || (!raw.startsWith('/') && namespaceIndex !== 0)) {
      throw new Error('GP-Next 路径超出 Loader 沙箱');
    }
    let normalized = this.root;
    for (let index = namespaceIndex + 1; index < parts.length; index++) {
      const part = parts[index];
      normalized = `${normalized}/${part}`;
    }
    return normalized;
  }

  private assertNoSymlink(target: string): void {
    if (fs.lstatSync(this.root).isSymbolicLink()) throw new Error('GP-Next 根目录不能是符号链接');
    const relative = target.substring(this.root.length).split('/').filter((part: string): boolean => part.length > 0);
    let current = this.root;
    for (const part of relative) {
      current = `${current}/${part}`;
      try {
        if (fs.lstatSync(current).isSymbolicLink()) throw new Error('不允许通过符号链接访问文件');
      } catch (error) {
        if ((error as Error).message === '不允许通过符号链接访问文件') {
          throw new Error('不允许通过符号链接访问文件');
        }
        return;
      }
    }
  }

  private ensureDirectory(path: string): void {
    this.assertNoSymlink(path);
    try {
      if (fs.accessSync(path)) return;
    } catch (_error) {
    }
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (parent.length >= this.root.length) this.ensureDirectory(parent);
    fs.mkdirSync(path);
    this.assertNoSymlink(path);
  }

  private safeFileName(value: string): string {
    const base = value.replace(/\\/g, '/').split('/').pop() ?? '';
    const cleaned = base.replace(/[\u0000-\u001f:*?"<>|]/g, '_').trim();
    return cleaned.length === 0 || cleaned === '.' || cleaned === '..'
      ? 'gardendless-export.json'
      : cleaned;
  }
}

class PendingWrite {
  readonly path: string;
  readonly temporary: string;
  readonly expectedBytes: number;
  written: number = 0;
  nextIndex: number = 0;

  constructor(path: string, temporary: string, expectedBytes: number) {
    this.path = path;
    this.temporary = temporary;
    this.expectedBytes = expectedBytes;
  }
}
