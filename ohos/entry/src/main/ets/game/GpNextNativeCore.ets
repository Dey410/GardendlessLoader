import fs from '@ohos.file.fs';
import { GameSession } from './GameSession';

export type GpNextValue = Object | string | number | boolean | null;

export interface GpNextResult {
  value: GpNextValue;
  exportPath?: string;
  openUrl?: string;
  importRequested?: boolean;
}

interface GpNextArguments {
  path?: string;
  url?: string;
  directory?: number;
  options?: GpNextOptions;
  __gardendlessBytes?: number[];
}

interface GpNextOptions {
  baseDir?: number;
  recursive?: boolean;
  defaultPath?: string;
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
      case 'plugin:fs|exists':
        return { value: this.exists(this.resolve(args.path, args.options ?? options)) };
      case 'plugin:fs|remove':
        this.remove(this.resolve(args.path, args.options ?? options), (args.options ?? options).recursive !== false);
        return { value: null };
      case 'plugin:fs|write_text_file':
        return this.writeFile(args, options);
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

  private writeFile(args: GpNextArguments, options: GpNextOptions): GpNextResult {
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

  private prepareExport(args: GpNextArguments): string {
    const name = this.safeFileName(args.options?.defaultPath ?? 'gardendless-export.json');
    this.ensureDirectory(this.session.exportTemporaryRoot);
    const path = `${this.session.exportTemporaryRoot}/${name}`;
    this.pendingExports.add(path);
    return path;
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
    const combined = raw.startsWith('/') ? raw : `${this.session.appRoot}/${raw}`;
    const parts: string[] = [];
    for (const part of combined.split('/')) {
      if (part.length === 0) continue;
      if (part === '.' || part === '..') throw new Error('GP-Next 路径超出 Loader 沙箱');
      parts.push(part);
    }
    const normalized = `/${parts.join('/')}`;
    if (normalized !== this.root && !normalized.startsWith(`${this.root}/`)) {
      throw new Error('GP-Next 路径超出 Loader 沙箱');
    }
    this.assertNoSymlink(normalized);
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
