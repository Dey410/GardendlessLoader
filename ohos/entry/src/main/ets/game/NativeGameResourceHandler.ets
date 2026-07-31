import fs from '@ohos.file.fs';
import { webview, WebNetErrorList } from '@kit.ArkWeb';
import { GameSession } from './GameSession';
import { appLogStore, AppLogContext, AppLogEvent } from '../logging/AppLogStore';

interface ByteRange {
  start: number;
  end: number;
}

class ActiveRequest {
  cancelled: boolean = false;
}

export class NativeGameResourceHandler {
  readonly schemeHandler: webview.WebSchemeHandler = new webview.WebSchemeHandler();
  private readonly root: string;
  private readonly session: GameSession;
  private readonly activeRequests: Map<webview.WebSchemeHandlerRequest, ActiveRequest> =
    new Map<webview.WebSchemeHandlerRequest, ActiveRequest>();

  constructor(session: GameSession) {
    this.session = session;
    this.root = session.resourceRoot.replace(/\/$/, '');
    if (!fs.statSync(this.root).isDirectory() || fs.lstatSync(this.root).isSymbolicLink()) {
      throw new Error('Resource root is not a safe directory');
    }
    this.schemeHandler.onRequestStart((
      request: webview.WebSchemeHandlerRequest,
      resourceHandler: webview.WebResourceHandler,
    ): boolean => this.onRequestStart(request, resourceHandler));
    this.schemeHandler.onRequestStop((request: webview.WebSchemeHandlerRequest): void => {
      const active = this.activeRequests.get(request);
      if (active != null) {
        active.cancelled = true;
      }
    });
  }

  attach(controller: webview.WebviewController): void {
    controller.setWebSchemeHandler('http', this.schemeHandler);
    controller.setWebSchemeHandler('https', this.schemeHandler);
  }

  destroy(): void {
    this.activeRequests.forEach((request: ActiveRequest): void => {
      request.cancelled = true;
    });
    this.activeRequests.clear();
  }

  private onRequestStart(
    request: webview.WebSchemeHandlerRequest,
    handler: webview.WebResourceHandler,
  ): boolean {
    const url = request.getRequestUrl();
    if (!url.startsWith(`${GameSession.ORIGIN}/`) && url !== GameSession.ORIGIN) {
      const host = this.hostFromHttpsUrl(url);
      if (host != null && this.isAllowedRemoteHost(host)) {
        return false;
      }
      this.logFailure('resource_path_forbidden', url, 403);
      this.sendEmpty(handler, 403, 'Forbidden');
      return true;
    }
    const method = request.getRequestMethod();
    if (method !== 'GET' && method !== 'HEAD') {
      this.logFailure('resource_method_not_allowed', url, 405, method);
      this.sendEmpty(handler, 405, 'Method Not Allowed', new Map([['Allow', 'GET, HEAD']]));
      return true;
    }
    const relativePath = this.decodePath(url);
    const filePath = relativePath == null ? null : this.resolveFile(relativePath);
    if (relativePath == null || filePath == null) {
      this.logFailure('resource_file_not_found', relativePath ?? url, 404);
      this.sendEmpty(handler, 404, 'Not Found');
      return true;
    }
    let responseStarted = false;
    try {
      const stat = fs.statSync(filePath);
      const etag = `"${stat.mtime}-${stat.size}"`;
      const headers = new Map<string, string>();
      headers.set('Accept-Ranges', 'bytes');
      headers.set('ETag', etag);
      headers.set('Cache-Control', this.cacheControl(relativePath));
      headers.set('X-Content-Type-Options', 'nosniff');
      if (this.requestHeader(request, 'If-None-Match') === etag) {
        this.sendEmpty(handler, 304, 'Not Modified', headers);
        return true;
      }
      const rangeHeader = this.requestHeader(request, 'Range');
      const range = rangeHeader == null ? null : this.parseRange(rangeHeader, stat.size);
      if (rangeHeader != null && range == null) {
        this.logFailure('resource_read_failed', relativePath, 416);
        headers.set('Content-Range', `bytes */${stat.size}`);
        this.sendEmpty(handler, 416, 'Range Not Satisfiable', headers);
        return true;
      }
      const start = range?.start ?? 0;
      const end = range?.end ?? Math.max(0, stat.size - 1);
      const length = stat.size === 0 ? 0 : end - start + 1;
      headers.set('Content-Length', length.toString());
      if (range != null) {
        headers.set('Content-Range', `bytes ${start}-${end}/${stat.size}`);
      }
      const mime = this.mimeType(relativePath, filePath);
      if (mime === 'application/octet-stream') {
        this.logFailure(
          'resource_mime_mismatch',
          relativePath,
          200,
          undefined,
          'known resource MIME',
          mime,
        );
      }
      this.sendHeaders(
        handler,
        range == null ? 200 : 206,
        range == null ? 'OK' : 'Partial Content',
        mime,
        headers,
      );
      responseStarted = true;
      if (method === 'HEAD' || length === 0) {
        handler.didFinish();
        return true;
      }
      const active = new ActiveRequest();
      this.activeRequests.set(request, active);
      this.streamBody(request, handler, filePath, relativePath, start, length, active)
        .catch((_error: Error): void => {});
    } catch (error) {
      this.logFailure(
        'resource_read_failed', relativePath, 500,
        undefined, undefined, undefined, (error as Error).name,
      );
      if (!responseStarted) {
        this.sendEmpty(handler, 500, 'Internal Server Error');
      } else {
        try {
          handler.didFail(WebNetErrorList.ERR_FAILED);
        } catch (_handlerError) {
        }
      }
    }
    return true;
  }

  private async streamBody(
    request: webview.WebSchemeHandlerRequest,
    handler: webview.WebResourceHandler,
    filePath: string,
    relativePath: string,
    start: number,
    length: number,
    active: ActiveRequest,
  ): Promise<void> {
    let file: fs.File | null = null;
    try {
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      let position = start;
      let remaining = length;
      while (!active.cancelled && remaining > 0) {
        const requested = Math.min(remaining, 128 * 1024);
        const buffer = new ArrayBuffer(requested);
        const count = await fs.read(file.fd, buffer, { offset: position, length: requested });
        if (active.cancelled) {
          return;
        }
        if (count <= 0) {
          throw new Error('Unexpected end of resource file');
        }
        handler.didReceiveResponseBody(count === requested ? buffer : buffer.slice(0, count));
        position += count;
        remaining -= count;
      }
      if (!active.cancelled) {
        handler.didFinish();
      }
    } catch (error) {
      this.logFailure(
        'resource_read_failed', relativePath, 500,
        undefined, undefined, undefined, (error as Error).name,
      );
      if (!active.cancelled) {
        try {
          handler.didFail(WebNetErrorList.ERR_FAILED);
        } catch (_handlerError) {
        }
      }
    } finally {
      if (file != null) {
        try {
          fs.closeSync(file.fd);
        } catch (_closeError) {
        }
      }
      if (this.activeRequests.get(request) === active) {
        this.activeRequests.delete(request);
      }
    }
  }

  private decodePath(url: string): string | null {
    let encoded = url.substring(GameSession.ORIGIN.length);
    encoded = encoded.split('?')[0].split('#')[0];
    if (encoded.length === 0 || encoded === '/') {
      return 'index.html';
    }
    if (!encoded.startsWith('/')) {
      return null;
    }
    let decoded: string;
    try {
      decoded = decodeURIComponent(encoded.substring(1));
    } catch (_error) {
      return null;
    }
    if (/%(?:2e|2f|5c|25)/i.test(decoded) || decoded.includes('\\') || decoded.includes('\0')) {
      return null;
    }
    const parts = decoded.split('/');
    if (parts.some((part: string): boolean => part.length === 0 || part === '.' || part === '..')) {
      return null;
    }
    return parts.join('/');
  }

  private resolveFile(relativePath: string): string | null {
    let current = this.root;
    for (const part of relativePath.split('/')) {
      current = `${current}/${part}`;
      try {
        if (fs.lstatSync(current).isSymbolicLink()) {
          return null;
        }
      } catch (_error) {
        return null;
      }
    }
    try {
      return fs.statSync(current).isFile() ? current : null;
    } catch (_error) {
      return null;
    }
  }

  private parseRange(value: string, length: number): ByteRange | null {
    if (length <= 0 || !value.startsWith('bytes=') || value.includes(',')) {
      return null;
    }
    const parts = value.substring(6).split('-');
    if (parts.length !== 2) {
      return null;
    }
    if (parts[0].length === 0) {
      const suffix = Number(parts[1]);
      if (!Number.isSafeInteger(suffix) || suffix <= 0) {
        return null;
      }
      return { start: Math.max(0, length - suffix), end: length - 1 };
    }
    const start = Number(parts[0]);
    const requestedEnd = parts[1].length === 0 ? length - 1 : Number(parts[1]);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(requestedEnd) ||
      start < 0 || start >= length || requestedEnd < start) {
      return null;
    }
    return { start: start, end: Math.min(requestedEnd, length - 1) };
  }

  private sendEmpty(
    handler: webview.WebResourceHandler,
    status: number,
    text: string,
    headers: Map<string, string> = new Map<string, string>(),
  ): void {
    headers.set('Content-Length', '0');
    this.sendHeaders(handler, status, text, 'text/plain', headers);
    handler.didFinish();
  }

  private sendHeaders(
    handler: webview.WebResourceHandler,
    status: number,
    text: string,
    mime: string,
    headers: Map<string, string>,
  ): void {
    const response = new webview.WebSchemeHandlerResponse();
    response.setNetErrorCode(WebNetErrorList.NET_OK);
    response.setStatus(status);
    response.setStatusText(text);
    response.setMimeType(mime);
    response.setEncoding(this.isTextMime(mime) ? 'utf-8' : '');
    headers.forEach((value: string, key: string): void => {
      response.setHeaderByName(key, value, true);
    });
    handler.didReceiveResponse(response);
  }

  private requestHeader(request: webview.WebSchemeHandlerRequest, name: string): string | null {
    const found = request.getHeader().find((header): boolean =>
      header.headerKey.toLowerCase() === name.toLowerCase());
    return found?.headerValue ?? null;
  }

  private hostFromHttpsUrl(url: string): string | null {
    if (!url.startsWith('https://')) {
      return null;
    }
    return url.substring(8).split('/')[0].split(':')[0].toLowerCase();
  }

  private isAllowedRemoteHost(host: string): boolean {
    for (const allowed of this.session.allowedRemoteHosts) {
      if (host === allowed || host.endsWith(`.${allowed}`)) {
        return true;
      }
    }
    return false;
  }

  private cacheControl(path: string): string {
    if (path === 'index.html' || path === 'src/settings.json' || path === 'src/import-map.json') {
      return 'no-cache';
    }
    const name = path.substring(path.lastIndexOf('/') + 1);
    if (/(?:^|[._-])[0-9a-f]{8,}(?:[._-]|$)/i.test(name)) {
      return 'public, max-age=31536000, immutable';
    }
    const extension = name.includes('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
    return ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'mp3', 'm4a', 'aac', 'ogg', 'wav', 'mp4',
      'webm', 'wasm', 'bin']
      .includes(extension) ? 'public, max-age=86400' : 'no-cache';
  }

  private mimeType(path: string, filePath: string): string {
    const extension = path.includes('.') ? path.substring(path.lastIndexOf('.') + 1).toLowerCase() : '';
    if (['png', 'jpg', 'jpeg', 'webp'].includes(extension) && this.isAvif(filePath)) {
      return 'image/avif';
    }
    if (extension === 'mp3') {
      const audioMime = this.sniffAudioMimeType(filePath);
      if (audioMime != null) return audioMime;
    }
    const types = new Map<string, string>([
      ['html', 'text/html'], ['htm', 'text/html'], ['js', 'application/javascript'],
      ['mjs', 'application/javascript'], ['css', 'text/css'], ['json', 'application/json'],
      ['json5', 'application/json'], ['wasm', 'application/wasm'], ['svg', 'image/svg+xml'],
      ['png', 'image/png'], ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'], ['gif', 'image/gif'],
      ['webp', 'image/webp'], ['avif', 'image/avif'], ['mp3', 'audio/mpeg'],
      ['m4a', 'audio/mp4'], ['aac', 'audio/aac'], ['ogg', 'audio/ogg'], ['wav', 'audio/wav'],
      ['mp4', 'video/mp4'], ['webm', 'video/webm'], ['woff', 'font/woff'],
      ['woff2', 'font/woff2'], ['ttf', 'font/ttf'],
    ]);
    return types.get(extension) ?? 'application/octet-stream';
  }

  private isAvif(filePath: string): boolean {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(64);
      const count = fs.readSync(file.fd, buffer, { offset: 0, length: 64 });
      if (count < 12) return false;
      const bytes = new Uint8Array(buffer, 0, count);
      if (bytes[4] !== 0x66 || bytes[5] !== 0x74 ||
        bytes[6] !== 0x79 || bytes[7] !== 0x70) {
        return false;
      }
      for (let offset = 8; offset + 3 < count; offset += 4) {
        const isAvifBrand = bytes[offset] === 0x61 && bytes[offset + 1] === 0x76 &&
          bytes[offset + 2] === 0x69 &&
          (bytes[offset + 3] === 0x66 || bytes[offset + 3] === 0x73);
        if (isAvifBrand) return true;
      }
      return false;
    } catch (_error) {
      return false;
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private sniffAudioMimeType(filePath: string): string | null {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(64);
      const count = fs.readSync(file.fd, buffer, { offset: 0, length: 64 });
      if (count < 2) return null;
      const bytes = new Uint8Array(buffer, 0, count);
      if (bytes[0] === 0xff && (bytes[1] & 0xf6) === 0xf0) {
        return 'audio/aac';
      }
      if (count >= 12 && bytes[4] === 0x66 && bytes[5] === 0x74 &&
        bytes[6] === 0x79 && bytes[7] === 0x70) {
        return 'audio/mp4';
      }
      return null;
    } catch (_error) {
      return null;
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private isTextMime(mime: string): boolean {
    return mime.startsWith('text/') || mime === 'application/javascript' || mime === 'application/json';
  }

  private logFailure(
    code: string,
    path: string,
    status: number,
    method?: string,
    expectedMime?: string,
    actualMime?: string,
    errorType?: string,
  ): void {
    const safePath = path.startsWith(GameSession.ORIGIN)
      ? path.substring(GameSession.ORIGIN.length).split('?')[0].split('#')[0]
      : path.startsWith('/') ? path : '<external-url>';
    const context: AppLogContext = {
      path: safePath,
      status: status,
    };
    context.command = method;
    context.expectedMime = expectedMime;
    context.actualMime = actualMime;
    context.errorType = errorType;
    const event: AppLogEvent = {
      source: 'ohos',
      level: status >= 500 ? 'ERROR' : 'WARN',
      category: 'resource.handler',
      event: 'resource_request_failed',
      outcome: 'failed',
      code: code,
      gameSessionId: this.session.sessionId,
      context: context,
    };
    appLogStore.emit(event);
  }
}
