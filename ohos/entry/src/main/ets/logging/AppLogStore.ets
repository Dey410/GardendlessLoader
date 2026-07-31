import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';

export interface AppLogEvent {
  source: string;
  level: string;
  category: string;
  event: string;
  outcome: string;
  code?: string;
  message?: string;
  gameSessionId?: string;
  operationId?: string;
  durationMs?: number;
  context?: Record<string, Object>;
  error?: Record<string, Object>;
}

export class AppLogStore {
  private initialized: boolean = false;
  private appSessionId: string = 'unavailable';
  private logsDirectory: string = '';
  private markerFile: string = '';
  private startedAt: number = 0;
  private sequence: number = 0;
  private segment: number = 0;
  private recent: Array<Record<string, Object>> = [];
  private dropped: Record<string, number> = {};
  private writeFailureCount: number = 0;
  private degraded: boolean = false;
  private pending: number = 0;
  private writes: Promise<void> = Promise.resolve();

  initialize(context: common.Context): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.logsDirectory = `${context.filesDir}/logs`;
    this.markerFile = `${this.logsDirectory}/active-session.json`;
    const previous = this.readPreviousSession();
    this.appSessionId = this.newSessionId();
    this.startedAt = Date.now();
    try {
      this.ensureDirectory(this.logsDirectory);
      this.writeText(this.markerFile, JSON.stringify({ appSessionId: this.appSessionId }));
      this.cleanup();
    } catch (_error) {
      this.markDegraded();
    }
    this.emitImmediate({
      source: 'ohos', level: 'INFO', category: 'app.lifecycle',
      event: 'app_session_started', outcome: 'started',
      context: { platform: 'ohos' },
    });
    if (previous != null && previous !== this.appSessionId) {
      this.emitImmediate({
        source: 'ohos', level: 'WARN', category: 'app.lifecycle',
        event: 'previous_run_unclean_shutdown', outcome: 'observed',
        code: 'previous_run_unclean_shutdown',
        context: { previousAppSessionId: previous },
      });
    }
  }

  getSessionId(): string {
    return this.appSessionId;
  }

  emit(event: AppLogEvent): void {
    if (!this.initialized) {
      return;
    }
    const level = this.level(event.level);
    if (this.pending >= 1000 && level !== 'ERROR' && level !== 'FATAL') {
      this.dropped[level] = (this.dropped[level] ?? 0) + 1;
      return;
    }
    this.pending += 1;
    this.writes = this.writes.then((): void => {
      this.emitImmediate(event);
      this.pending -= 1;
    }).catch((_error: Error): void => {
      this.pending -= 1;
      this.markDegraded();
    });
  }

  flush(): Promise<void> {
    return this.writes;
  }

  endSession(): Promise<void> {
    this.emit({
      source: 'ohos', level: 'INFO', category: 'app.lifecycle',
      event: 'app_session_ended', outcome: 'succeeded',
    });
    return this.flush().then((): void => {
      try { fs.unlinkSync(this.markerFile); } catch (_error) {}
    });
  }

  snapshot(limit: number): Record<string, Object> {
    const count = Math.max(1, Math.min(500, limit));
    let totalBytes = 0;
    try {
      for (const name of fs.listFileSync(this.logsDirectory)) {
        totalBytes += fs.statSync(`${this.logsDirectory}/${name}`).size;
      }
    } catch (_error) {}
    return {
      appSessionId: this.appSessionId,
      persisting: !this.degraded,
      degraded: this.degraded,
      logDirectory: this.logsDirectory,
      totalBytes: totalBytes,
      writeFailureCount: this.writeFailureCount,
      droppedByLevel: this.dropped,
      events: this.recent.slice(Math.max(0, this.recent.length - count)),
    };
  }

  deleteHistory(): Promise<void> {
    return this.flush().then((): void => {
      const currentPrefix = `app-${this.appSessionId}-`;
      try {
        for (const name of fs.listFileSync(this.logsDirectory)) {
          if (name.endsWith('.jsonl') && !name.startsWith(currentPrefix)) {
            try { fs.unlinkSync(`${this.logsDirectory}/${name}`); } catch (_error) {}
          }
        }
      } catch (_error) {}
    });
  }

  private emitImmediate(input: AppLogEvent): void {
    this.sequence += 1;
    const value: Record<string, Object> = {
      schemaVersion: 1,
      timestampUtc: new Date().toISOString(),
      monotonicMs: Date.now() - this.startedAt,
      sequence: this.sequence,
      level: this.level(input.level),
      source: this.identifier(input.source, 'ohos'),
      category: this.identifier(input.category, 'unknown'),
      event: this.identifier(input.event, 'unknown_event'),
      outcome: this.identifier(input.outcome, 'observed'),
      appSessionId: this.appSessionId,
    };
    this.copyText(input.code, value, 'code', 256);
    this.copyText(input.message, value, 'message', 2048);
    this.copyText(input.gameSessionId, value, 'gameSessionId', 256);
    this.copyText(input.operationId, value, 'operationId', 256);
    if (input.durationMs != null) value['durationMs'] = input.durationMs;
    if (input.context != null) value['context'] = this.sanitizeMap(input.context);
    if (input.error != null) value['error'] = this.sanitizeMap(input.error);
    let line = JSON.stringify(value);
    if (line.length > 16 * 1024) {
      delete value['context'];
      value['message'] = 'Log event exceeded 16 KB and was truncated';
      line = JSON.stringify(value);
    }
    this.recent.push(value);
    if (this.recent.length > 500) this.recent.splice(0, this.recent.length - 500);
    if (this.degraded) return;
    try {
      const path = this.segmentPath(line.length + 1);
      let file: fs.File | null = null;
      try {
        file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        fs.writeSync(file.fd, `${line}\n`, { offset: fs.statSync(path).size });
      } finally {
        if (file != null) fs.closeSync(file.fd);
      }
    } catch (_error) {
      this.markDegraded();
    }
  }

  private segmentPath(nextBytes: number): string {
    let suffix = this.segment.toString().padStart(3, '0');
    let path = `${this.logsDirectory}/app-${this.appSessionId}-${suffix}.jsonl`;
    try {
      if (fs.statSync(path).size + nextBytes > 2 * 1024 * 1024) {
        this.segment += 1;
        suffix = this.segment.toString().padStart(3, '0');
        path = `${this.logsDirectory}/app-${this.appSessionId}-${suffix}.jsonl`;
      }
    } catch (_error) {}
    return path;
  }

  private cleanup(): void {
    const names = fs.listFileSync(this.logsDirectory)
      .filter((name: string): boolean => name.endsWith('.jsonl'))
      .sort();
    const sessionPrefixes: string[] = [];
    for (const name of names) {
      const prefix = name.replace(/-\d{3}\.jsonl$/, '');
      if (!sessionPrefixes.includes(prefix)) sessionPrefixes.push(prefix);
    }
    const keep = new Set<string>(sessionPrefixes.slice(Math.max(0, sessionPrefixes.length - 5)));
    let total = 0;
    for (const name of names) total += fs.statSync(`${this.logsDirectory}/${name}`).size;
    for (const name of names) {
      const path = `${this.logsDirectory}/${name}`;
      const prefix = name.replace(/-\d{3}\.jsonl$/, '');
      const size = fs.statSync(path).size;
      if (!keep.has(prefix) || total > 10 * 1024 * 1024) {
        try { fs.unlinkSync(path); total -= size; } catch (_error) {}
      }
    }
  }

  private readPreviousSession(): string | null {
    try {
      const value = JSON.parse(fs.readTextSync(this.markerFile)) as Record<string, Object>;
      return value['appSessionId'] as string;
    } catch (_error) {
      return null;
    }
  }

  private ensureDirectory(path: string): void {
    try {
      if (fs.statSync(path).isDirectory()) return;
    } catch (_error) {}
    fs.mkdirSync(path);
  }

  private writeText(path: string, value: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, value);
    } finally {
      if (file != null) fs.closeSync(file.fd);
    }
  }

  private sanitizeMap(value: Record<string, Object>): Record<string, Object> {
    const result: Record<string, Object> = {};
    const forbidden = /password|passwd|secret|token|authorization|cookie|api.?key|private.?key/i;
    for (const key of Object.keys(value).slice(0, 32)) {
      if (forbidden.test(key)) continue;
      const item = value[key];
      if (typeof item === 'string') result[key] = this.sanitize(item, 4096);
      else if (typeof item === 'number' || typeof item === 'boolean') result[key] = item;
    }
    return result;
  }

  private copyText(value: string | undefined, target: Record<string, Object>, key: string, limit: number): void {
    if (value != null) target[key] = this.sanitize(value, limit);
  }

  private sanitize(value: string, limit: number): string {
    let result = value
      .replace(/(token|authorization|cookie|password|passwd|secret|apiKey)\s*[:=]\s*[^\s,;]+/gi,
        (_match: string, key: string): string => `${key}=<redacted>`)
      .replace(/\/(Users|home)\/[^/\s]+/g, '/<user-home>');
    if (result.length > limit) result = `${result.substring(0, limit)}...[truncated]`;
    return result;
  }

  private level(value: string): string {
    const result = value.toUpperCase();
    return ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].includes(result) ? result : 'INFO';
  }

  private identifier(value: string, fallback: string): string {
    return /^[A-Za-z0-9._-]{1,128}$/.test(value) ? value : fallback;
  }

  private markDegraded(): void {
    this.degraded = true;
    this.writeFailureCount += 1;
  }

  private newSessionId(): string {
    const timestamp = new Date().toISOString().replace(/[-:T]/g, '').substring(0, 15);
    return `${timestamp}-${Math.random().toString(16).substring(2, 8)}`;
  }
}

export const appLogStore = new AppLogStore();
