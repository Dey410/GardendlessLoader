import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { http } from '@kit.NetworkKit';
import { FileFailure, NestImportSource } from './GpNextNativeCore';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_PACKAGE_BYTES = 100 * 1024 * 1024;
const MAX_LEVEL_BYTES = 10000000;
const MAX_DESCRIPTOR_BYTES = 64 * 1024;
const MAX_HEADER_BYTES = 16 * 1024;

interface NestDescriptorJson {
  protocolVersion?: number;
  versionId?: string;
  projectId?: string;
  type?: string;
  format?: string;
  version?: string;
  name?: string;
  expiresAt?: string;
  sha256?: string;
  byteLength?: number;
  url?: string;
}

interface NestErrorJson {
  error?: string;
}

/** Only the fields GP-Next reads travel on; the signed URL stays here. */
interface NestHeader {
  protocolVersion: number;
  versionId: string;
  projectId: string;
  type: string;
  format: string;
  version: string;
  name: string;
  expiresAt: string;
  sha256: string;
  byteLength: number;
}

class NestDescriptor {
  readonly header: Uint8Array;
  readonly url: string;
  readonly sha256: string;
  readonly byteLength: number;

  constructor(header: Uint8Array, url: string, sha256: string, byteLength: number) {
    this.header = header;
    this.url = url;
    this.sha256 = sha256;
    this.byteLength = byteLength;
  }
}

class PackageStream {
  received: number = 0;
  failure: string | null = null;
  writes: Promise<void> = Promise.resolve();
}

function nestFailure(reason: string): FileFailure {
  return new FileFailure('nest_import_failed', reason);
}

/**
 * GP-Next's download_nest_import contract. Nest answers
 * https://nest.pvzge.com/api/game-imports/<version> with a descriptor that
 * names a short-lived package URL, its SHA-256 and its size. GP-Next expects
 * the package framed as a little-endian u32 descriptor length, the
 * descriptor JSON and the package bytes, and validates all three again.
 */
export class NestImportDownloader implements NestImportSource {
  private readonly directory: string;
  private busy: boolean = false;
  private cancelled: boolean = false;
  private active: http.HttpRequest | null = null;

  /** Downloads go to `directory`; files left there by an earlier process are removed. */
  constructor(directory: string) {
    this.directory = directory.replace(/\/$/, '');
    this.removeStaleFiles().catch((_error: Error): void => {});
  }

  cancel(): void {
    this.cancelled = true;
    this.active?.destroy();
    this.active = null;
  }

  async download(versionId: string, isActive: () => boolean): Promise<string> {
    if (!UUID.test(versionId)) throw nestFailure('NEST_INTENT');
    if (this.busy || this.cancelled) throw nestFailure('NEST_BUSY');
    this.busy = true;
    try {
      const descriptor = await this.fetchDescriptor(versionId);
      if (!isActive() || this.cancelled) throw nestFailure('NEST_CANCELLED');
      return await this.fetchPackage(descriptor, isActive);
    } finally {
      this.busy = false;
    }
  }

  async discard(path: string): Promise<void> {
    try { await fs.unlink(path); } catch (_error) {}
  }

  private async fetchDescriptor(versionId: string): Promise<NestDescriptor> {
    const request = http.createHttp();
    this.active = request;
    let status = 0;
    let body = '';
    try {
      const response = await request.request(`https://nest.pvzge.com/api/game-imports/${versionId}`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 30000,
        maxLimit: MAX_DESCRIPTOR_BYTES,
      });
      status = response.responseCode;
      body = typeof response.result === 'string' ? response.result : '';
    } catch (_error) {
      throw nestFailure('NEST_NETWORK');
    } finally {
      request.destroy();
      if (this.active === request) this.active = null;
    }
    if (body.length > MAX_DESCRIPTOR_BYTES) throw nestFailure('NEST_DESCRIPTOR');
    if (status !== 200) throw nestFailure(NestImportDownloader.errorCode(body) ?? `NEST_HTTP_${status}`);
    return NestImportDownloader.parse(body, versionId);
  }

  private async fetchPackage(descriptor: NestDescriptor, isActive: () => boolean): Promise<string> {
    await this.ensureDirectory();
    const path = `${this.directory}/nest-${util.generateRandomUUID()}.bin`;
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    const request = http.createHttp();
    this.active = request;
    const stream = new PackageStream();
    let completed = false;
    try {
      const prefix = new ArrayBuffer(4);
      new DataView(prefix).setUint32(0, descriptor.header.length, true);
      await fs.write(file.fd, prefix);
      await fs.write(file.fd, descriptor.header.buffer.slice(descriptor.header.byteOffset,
        descriptor.header.byteOffset + descriptor.header.byteLength));
      const md = cryptoFramework.createMd('SHA256');
      request.on('dataReceive', (data: ArrayBuffer): void => {
        if (stream.failure !== null) return;
        stream.received += data.byteLength;
        if (stream.received > descriptor.byteLength || !isActive() || this.cancelled) {
          stream.failure = stream.received > descriptor.byteLength ? 'NEST_LENGTH' : 'NEST_CANCELLED';
          request.destroy();
          return;
        }
        const chunk = data.slice(0);
        stream.writes = stream.writes.then(async (): Promise<void> => {
          await md.update({ data: new Uint8Array(chunk) });
          await fs.write(file.fd, chunk);
        });
      });
      let status = 0;
      try {
        status = await request.requestInStream(descriptor.url, {
          method: http.RequestMethod.GET,
          usingCache: false,
          connectTimeout: 15000,
          readTimeout: 30000,
        });
      } catch (_error) {
        if (stream.failure === null) stream.failure = 'NEST_NETWORK';
      }
      try { await stream.writes; } catch (_error) {
        if (stream.failure === null) stream.failure = 'NEST_WRITE';
      }
      if (stream.failure === null && status !== 200) stream.failure = `NEST_HTTP_${status}`;
      if (stream.failure === null && stream.received !== descriptor.byteLength) stream.failure = 'NEST_LENGTH';
      if (stream.failure === null) {
        const digest = await md.digest();
        if (NestImportDownloader.hex(digest.data) !== descriptor.sha256) stream.failure = 'NEST_HASH';
      }
      const failure = stream.failure;
      if (failure !== null) throw nestFailure(failure);
      await fs.fsync(file.fd);
      completed = true;
      return path;
    } finally {
      try { request.off('dataReceive'); } catch (_error) {}
      request.destroy();
      if (this.active === request) this.active = null;
      try { await fs.close(file.fd); } catch (_error) {}
      if (!completed) await this.discard(path);
    }
  }

  private async ensureDirectory(): Promise<void> {
    if (await fs.access(this.directory)) return;
    try { await fs.mkdir(this.directory, true); } catch (_error) {
      if (!await fs.access(this.directory)) throw nestFailure('NEST_WRITE');
    }
  }

  private async removeStaleFiles(): Promise<void> {
    if (!await fs.access(this.directory)) return;
    for (const name of await fs.listFile(this.directory)) {
      await this.discard(`${this.directory}/${name}`);
    }
  }

  private static errorCode(body: string): string | null {
    try {
      const code = (JSON.parse(body) as NestErrorJson).error;
      return typeof code === 'string' && /^[a-z0-9-]{1,64}$/.test(code) ? code : null;
    } catch (_error) {
      return null;
    }
  }

  private static parse(body: string, versionId: string): NestDescriptor {
    let json: NestDescriptorJson;
    try {
      json = JSON.parse(body) as NestDescriptorJson;
    } catch (_error) {
      throw nestFailure('NEST_DESCRIPTOR');
    }
    if (json == null || typeof json !== 'object') throw nestFailure('NEST_DESCRIPTOR');
    const projectId = typeof json.projectId === 'string' ? json.projectId : '';
    const name = typeof json.name === 'string' ? json.name : '';
    const version = typeof json.version === 'string' ? json.version : '';
    const sha256 = typeof json.sha256 === 'string' ? json.sha256 : '';
    const expiresAt = typeof json.expiresAt === 'string' ? json.expiresAt : '';
    const type = typeof json.type === 'string' ? json.type : '';
    const format = typeof json.format === 'string' ? json.format : '';
    const size = typeof json.byteLength === 'number' ? json.byteLength : -1;
    if (json.protocolVersion !== 1 || json.versionId !== versionId || !projectId.startsWith('prj_') ||
      !UUID.test(projectId.substring(4)) || name.length === 0 || version.length === 0 ||
      !SHA256.test(sha256) || !Number.isSafeInteger(size) || size <= 0 || expiresAt.length === 0) {
      throw nestFailure('NEST_DESCRIPTOR');
    }
    const level = type === 'level' && (format === 'json' || format === 'json5');
    const archive = (type === 'datapack' || type === 'mod') && format === 'zip';
    if (!level && !archive) throw nestFailure('NEST_UNSUPPORTED_FORMAT');
    if (size > (level ? MAX_LEVEL_BYTES : MAX_PACKAGE_BYTES)) throw nestFailure('NEST_LENGTH');
    const url = typeof json.url === 'string' ? json.url : '';
    if (!NestImportDownloader.isDownloadUrl(url)) throw nestFailure('NEST_DOWNLOAD_URL');
    const header: NestHeader = {
      protocolVersion: 1,
      versionId: versionId,
      projectId: projectId,
      type: type,
      format: format,
      version: version,
      name: name,
      expiresAt: expiresAt,
      sha256: sha256,
      byteLength: size,
    };
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(header));
    if (bytes.length > MAX_HEADER_BYTES) throw nestFailure('NEST_DESCRIPTOR');
    return new NestDescriptor(bytes, url, sha256, size);
  }

  /**
   * Nest serves packages from its Cloudflare R2 bucket through presigned
   * HTTPS URLs; the bytes must still match the descriptor's SHA-256.
   */
  private static isDownloadUrl(url: string): boolean {
    if (!url.startsWith('https://') || url.includes('#')) return false;
    const authority = url.substring('https://'.length).split(/[/?]/)[0];
    if (authority.includes('@')) return false;
    let host = authority.toLowerCase();
    if (host.endsWith(':443')) host = host.substring(0, host.length - 4);
    if (host.includes(':')) return false;
    return host === 'nest.pvzge.com' || host.endsWith('.r2.cloudflarestorage.com');
  }

  private static hex(bytes: Uint8Array): string {
    let result = '';
    for (let index = 0; index < bytes.length; index++) {
      const byte = bytes[index];
      result += (byte < 16 ? '0' : '') + byte.toString(16);
    }
    return result;
  }
}
