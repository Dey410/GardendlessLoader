import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

class PackZipEntry {
  readonly path: string;
  readonly isDirectory: boolean;
  readonly crc32: number;
  readonly compressionMethod: number;
  readonly compressedSize: number;
  readonly uncompressedSize: number;
  readonly localHeaderOffset: number;
  readonly externalAttributes: number;

  constructor(
    path: string,
    isDirectory: boolean,
    crc32: number,
    compressionMethod: number,
    compressedSize: number,
    uncompressedSize: number,
    localHeaderOffset: number,
    externalAttributes: number,
  ) {
    this.path = path;
    this.isDirectory = isDirectory;
    this.crc32 = crc32;
    this.compressionMethod = compressionMethod;
    this.compressedSize = compressedSize;
    this.uncompressedSize = uncompressedSize;
    this.localHeaderOffset = localHeaderOffset;
    this.externalAttributes = externalAttributes;
  }
}

class NormalizedPackZipEntry {
  readonly source: PackZipEntry;
  readonly name: string;
  localHeaderOffset: number = 0;

  constructor(source: PackZipEntry, name: string) {
    this.source = source;
    this.name = name;
  }
}

export class GpNextPackArchiveNormalizer {
  static prepare(source: string, directory: string, displayName: string): string {
    const entries = GpNextPackArchiveNormalizer.readEntries(source, displayName);
    if (entries.some((entry: PackZipEntry): boolean =>
      !entry.isDirectory && entry.path === 'pack.json')) {
      return source;
    }

    const candidates: Set<string> = new Set<string>();
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      const parts = entry.path.split('/');
      if (parts.length === 2 && parts[1] === 'pack.json') {
        candidates.add(parts[0]);
      }
    }
    if (candidates.size !== 1) throw new Error(GpNextPackArchiveNormalizer.missingRootPack(displayName));
    let wrapper = '';
    for (const candidate of candidates) wrapper = candidate;
    const prefix = `${wrapper}/`;
    if (!entries.every((entry: PackZipEntry): boolean =>
      entry.path === wrapper || entry.path.startsWith(prefix))) {
      throw new Error(GpNextPackArchiveNormalizer.missingRootPack(displayName));
    }

    const names: Set<string> = new Set<string>();
    const normalized: NormalizedPackZipEntry[] = [];
    for (const entry of entries) {
      if (!entry.path.startsWith(prefix)) continue;
      let name = entry.path.substring(prefix.length);
      if (name.length === 0) continue;
      if (entry.isDirectory) name += '/';
      if (names.has(name)) throw new Error(`${displayName} 规范化后包含重复路径`);
      names.add(name);
      normalized.push(new NormalizedPackZipEntry(entry, name));
    }
    if (!normalized.some((entry: NormalizedPackZipEntry): boolean =>
      !entry.source.isDirectory && entry.name === 'pack.json')) {
      throw new Error(GpNextPackArchiveNormalizer.missingRootPack(displayName));
    }

    const output = `${directory}/.${displayName}.normalized-${Date.now()}`;
    try {
      GpNextPackArchiveNormalizer.writeArchive(source, output, normalized);
      return output;
    } catch (error) {
      try { fs.unlinkSync(output); } catch (_cleanupError) {}
      throw new Error((error as Error).message);
    }
  }

  private static readEntries(path: string, displayName: string): PackZipEntry[] {
    let file: fs.File | null = null;
    try {
      const size = fs.statSync(path).size;
      if (size < 22) throw new Error(`${displayName} 不是有效的 ZIP`);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const tailLength = Math.min(size, 65557);
      const tail = GpNextPackArchiveNormalizer.read(file, size - tailLength, tailLength);
      let eocd = -1;
      for (let index = tail.length - 22; index >= 0; index--) {
        if (GpNextPackArchiveNormalizer.uint32LE(tail, index) !== 0x06054b50) continue;
        const commentLength = GpNextPackArchiveNormalizer.uint16LE(tail, index + 20);
        if (index + 22 + commentLength === tail.length) {
          eocd = index;
          break;
        }
      }
      if (eocd < 0) throw new Error(`${displayName} 不是有效的 ZIP`);
      const entryCount = GpNextPackArchiveNormalizer.uint16LE(tail, eocd + 10);
      const centralSize = GpNextPackArchiveNormalizer.uint32LE(tail, eocd + 12);
      let offset = GpNextPackArchiveNormalizer.uint32LE(tail, eocd + 16);
      if (entryCount === 0xffff || centralSize === 0xffffffff || offset === 0xffffffff) {
        throw new Error('暂不支持 ZIP64 格式');
      }

      const decoder = util.TextDecoder.create('utf-8');
      const entries: PackZipEntry[] = [];
      for (let index = 0; index < entryCount; index++) {
        const header = GpNextPackArchiveNormalizer.read(file, offset, 46);
        if (GpNextPackArchiveNormalizer.uint32LE(header, 0) !== 0x02014b50) {
          throw new Error(`${displayName} 的 ZIP 中央目录无效`);
        }
        const flags = GpNextPackArchiveNormalizer.uint16LE(header, 8);
        if ((flags & 0x0001) !== 0) throw new Error(`${displayName} 已加密，无法导入`);
        const compressionMethod = GpNextPackArchiveNormalizer.uint16LE(header, 10);
        const crc32 = GpNextPackArchiveNormalizer.uint32LE(header, 16);
        const compressedSize = GpNextPackArchiveNormalizer.uint32LE(header, 20);
        const uncompressedSize = GpNextPackArchiveNormalizer.uint32LE(header, 24);
        const nameLength = GpNextPackArchiveNormalizer.uint16LE(header, 28);
        const extraLength = GpNextPackArchiveNormalizer.uint16LE(header, 30);
        const commentLength = GpNextPackArchiveNormalizer.uint16LE(header, 32);
        const externalAttributes = GpNextPackArchiveNormalizer.uint32LE(header, 38);
        const localHeaderOffset = GpNextPackArchiveNormalizer.uint32LE(header, 42);
        const unixType = (externalAttributes >>> 16) & 0xf000;
        if (unixType === 0xa000) {
          throw new Error(`${displayName} 包含不支持的符号链接`);
        }
        if (compressedSize === 0xffffffff || uncompressedSize === 0xffffffff ||
          localHeaderOffset === 0xffffffff) {
          throw new Error('暂不支持 ZIP64 格式');
        }
        const nameBytes = GpNextPackArchiveNormalizer.read(file, offset + 46, nameLength);
        const name = decoder.decodeToString(nameBytes).replace(/\\/g, '/');
        const archivePath = GpNextPackArchiveNormalizer.safeArchivePath(name);
        if (!GpNextPackArchiveNormalizer.isMetadataArtifact(archivePath)) {
          entries.push(new PackZipEntry(
            archivePath,
            name.endsWith('/'),
            crc32,
            compressionMethod,
            compressedSize,
            uncompressedSize,
            localHeaderOffset,
            externalAttributes,
          ));
        }
        offset += 46 + nameLength + extraLength + commentLength;
      }
      return entries;
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private static writeArchive(
    sourcePath: string,
    outputPath: string,
    entries: NormalizedPackZipEntry[],
  ): void {
    if (entries.length > 0xffff) throw new Error('GP-Next ZIP 文件条目过多');
    let source: fs.File | null = null;
    let output: fs.File | null = null;
    try {
      source = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      output = fs.openSync(
        outputPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC,
      );
      let outputOffset = 0;
      for (const entry of entries) {
        const nameBytes = GpNextPackArchiveNormalizer.utf8(entry.name);
        if (nameBytes.length > 0xffff) throw new Error('GP-Next ZIP 文件名过长');
        entry.localHeaderOffset = outputOffset;
        const header = GpNextPackArchiveNormalizer.localHeader(entry.source, nameBytes);
        GpNextPackArchiveNormalizer.write(output, outputOffset, header);
        outputOffset += header.length;
        const dataOffset = GpNextPackArchiveNormalizer.localDataOffset(source, entry.source);
        GpNextPackArchiveNormalizer.copy(source, dataOffset, output, outputOffset, entry.source.compressedSize);
        outputOffset += entry.source.compressedSize;
        if (outputOffset > 0xffffffff) throw new Error('暂不支持 ZIP64 格式');
      }

      const centralOffset = outputOffset;
      for (const entry of entries) {
        const central = GpNextPackArchiveNormalizer.centralHeader(entry, GpNextPackArchiveNormalizer.utf8(entry.name));
        GpNextPackArchiveNormalizer.write(output, outputOffset, central);
        outputOffset += central.length;
      }
      const centralSize = outputOffset - centralOffset;
      if (outputOffset > 0xffffffff || centralSize > 0xffffffff) {
        throw new Error('暂不支持 ZIP64 格式');
      }
      GpNextPackArchiveNormalizer.write(
        output,
        outputOffset,
        GpNextPackArchiveNormalizer.endOfCentralDirectory(entries.length, centralSize, centralOffset),
      );
    } finally {
      if (source != null) fs.closeSync(source.fd);
      if (output != null) fs.closeSync(output.fd);
    }
  }

  private static localDataOffset(file: fs.File, entry: PackZipEntry): number {
    const header = GpNextPackArchiveNormalizer.read(file, entry.localHeaderOffset, 30);
    if (GpNextPackArchiveNormalizer.uint32LE(header, 0) !== 0x04034b50) throw new Error('ZIP 本地文件头无效');
    return entry.localHeaderOffset + 30 +
      GpNextPackArchiveNormalizer.uint16LE(header, 26) + GpNextPackArchiveNormalizer.uint16LE(header, 28);
  }

  private static copy(
    source: fs.File,
    sourceOffset: number,
    output: fs.File,
    outputOffset: number,
    byteCount: number,
  ): void {
    let copied = 0;
    while (copied < byteCount) {
      const length = Math.min(64 * 1024, byteCount - copied);
      const bytes = GpNextPackArchiveNormalizer.read(source, sourceOffset + copied, length);
      GpNextPackArchiveNormalizer.write(output, outputOffset + copied, bytes);
      copied += length;
    }
  }

  private static localHeader(entry: PackZipEntry, name: Uint8Array): Uint8Array {
    const bytes = new Uint8Array(30 + name.length);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 0, 0x04034b50);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 4, 20);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 6, 0x0800);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 8, entry.compressionMethod);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 14, entry.crc32);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 18, entry.compressedSize);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 22, entry.uncompressedSize);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 26, name.length);
    bytes.set(name, 30);
    return bytes;
  }

  private static centralHeader(entry: NormalizedPackZipEntry, name: Uint8Array): Uint8Array {
    const bytes = new Uint8Array(46 + name.length);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 0, 0x02014b50);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 4, 0x0314);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 6, 20);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 8, 0x0800);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 10, entry.source.compressionMethod);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 16, entry.source.crc32);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 20, entry.source.compressedSize);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 24, entry.source.uncompressedSize);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 28, name.length);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 38, entry.source.externalAttributes);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 42, entry.localHeaderOffset);
    bytes.set(name, 46);
    return bytes;
  }

  private static endOfCentralDirectory(
    entryCount: number,
    centralSize: number,
    centralOffset: number,
  ): Uint8Array {
    const bytes = new Uint8Array(22);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 0, 0x06054b50);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 8, entryCount);
    GpNextPackArchiveNormalizer.setUint16LE(bytes, 10, entryCount);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 12, centralSize);
    GpNextPackArchiveNormalizer.setUint32LE(bytes, 16, centralOffset);
    return bytes;
  }

  private static safeArchivePath(value: string): string {
    const normalized = value.replace(/\\/g, '/');
    if (normalized.startsWith('/')) throw new Error('GP-Next ZIP 包含不安全路径');
    const parts = normalized.split('/').filter((part: string): boolean =>
      part.length > 0 && part !== '.');
    if (parts.length === 0 || parts.includes('..')) {
      throw new Error('GP-Next ZIP 包含不安全路径');
    }
    return parts.join('/');
  }

  private static isMetadataArtifact(path: string): boolean {
    const parts = path.split('/');
    return parts.includes('__MACOSX') || parts[parts.length - 1] === '.DS_Store';
  }

  private static missingRootPack(displayName: string): string {
    return `${displayName} 缺少根目录 pack.json，且未找到唯一的单层外壳目录`;
  }

  private static read(file: fs.File, offset: number, length: number): Uint8Array {
    const buffer = new ArrayBuffer(length);
    const count = fs.readSync(file.fd, buffer, { offset: offset, length: length });
    if (count !== length) throw new Error('ZIP 文件内容不完整');
    return new Uint8Array(buffer);
  }

  private static write(file: fs.File, offset: number, bytes: Uint8Array): void {
    const count = fs.writeSync(file.fd, bytes.buffer, { offset: offset, length: bytes.length });
    if (count !== bytes.length) throw new Error('无法写入规范化 GP-Next ZIP');
  }

  private static utf8(value: string): Uint8Array {
    const values: number[] = [];
    for (let index = 0; index < value.length; index++) {
      let code = value.charCodeAt(index);
      if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
        const low = value.charCodeAt(index + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
          index++;
        }
      }
      if (code <= 0x7f) {
        values.push(code);
      } else if (code <= 0x7ff) {
        values.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code <= 0xffff) {
        values.push(
          0xe0 | (code >> 12),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f),
        );
      } else {
        values.push(
          0xf0 | (code >> 18),
          0x80 | ((code >> 12) & 0x3f),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f),
        );
      }
    }
    const bytes = new Uint8Array(values.length);
    for (let index = 0; index < values.length; index++) bytes[index] = values[index];
    return bytes;
  }

  private static uint16LE(bytes: Uint8Array, offset: number): number {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  private static uint32LE(bytes: Uint8Array, offset: number): number {
    return (bytes[offset] | (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
  }

  private static setUint16LE(bytes: Uint8Array, offset: number, value: number): void {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >>> 8) & 0xff;
  }

  private static setUint32LE(bytes: Uint8Array, offset: number, value: number): void {
    bytes[offset] = value & 0xff;
    bytes[offset + 1] = (value >>> 8) & 0xff;
    bytes[offset + 2] = (value >>> 16) & 0xff;
    bytes[offset + 3] = (value >>> 24) & 0xff;
  }
}
