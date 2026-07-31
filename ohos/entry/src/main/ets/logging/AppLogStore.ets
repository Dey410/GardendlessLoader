import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';

export interface AppLogContext {
  platform?: string;
  appVersion?: string;
  osVersion?: string;
  state?: string;
  stage?: string;
  transactionState?: string;
  targetSlot?: string;
  recoveryAction?: string;
  activeSlot?: string;
  currentResourceUsable?: boolean;
  processedBytes?: number;
  totalBytes?: number;
  processedFiles?: number;
  totalFiles?: number;
  fileCount?: number;
  buildProfile?: string;
  gpNextVersion?: string;
  cleanupDeferred?: boolean;
  gameVersion?: string;
  previousAppSessionId?: string;
  previousLastEvent?: string;
  previousLastCode?: string;
  previousLastTimestamp?: string;
  reason?: string;
  command?: string;
  page?: string;
  line?: number;
  column?: number;
  path?: string;
  status?: number;
  statusCode?: number;
  expectedMime?: string;
  actualMime?: string;
  errorType?: string;
  crashed?: boolean;
  url?: string;
}

export interface AppLogError {
  type?: string;
  message?: string;
  stackTrace?: string;
}

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
  context?: AppLogContext;
  error?: AppLogError;
}

export interface SerializedLogEvent {
  schemaVersion: number;
  timestampUtc: string;
  monotonicMs: number;
  sequence: number;
  level: string;
  source: string;
  category: string;
  event: string;
  outcome: string;
  appSessionId: string;
  code?: string;
  message?: string;
  gameSessionId?: string;
  operationId?: string;
  durationMs?: number;
  context?: AppLogContext;
  error?: AppLogError;
}

export interface AppLogDroppedCounts {
  DEBUG: number;
  INFO: number;
  WARN: number;
  ERROR: number;
  FATAL: number;
}

export interface AppLogSnapshot {
  appSessionId: string;
  persisting: boolean;
  degraded: boolean;
  logDirectory: string;
  totalBytes: number;
  writeFailureCount: number;
  droppedByLevel: AppLogDroppedCounts;
  events: Array<SerializedLogEvent>;
}

interface AppSessionMarker {
  appSessionId: string;
}

export class AppLogStore {
  private initialized: boolean = false;
  private appSessionId: string = 'unavailable';
  private logsDirectory: string = '';
  private markerFile: string = '';
  private startedAt: number = 0;
  private sequence: number = 0;
  private segment: number = 0;
  private recent: Array<SerializedLogEvent> = [];
  private dropped: AppLogDroppedCounts = {
    DEBUG: 0,
    INFO: 0,
    WARN: 0,
    ERROR: 0,
    FATAL: 0,
  };
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
      const marker: AppSessionMarker = { appSessionId: this.appSessionId };
      this.writeText(this.markerFile, JSON.stringify(marker));
      this.cleanup();
    } catch (_error) {
      this.markDegraded();
    }
    const sessionContext: AppLogContext = { platform: 'ohos' };
    const sessionStarted: AppLogEvent = {
      source: 'ohos', level: 'INFO', category: 'app.lifecycle',
      event: 'app_session_started', outcome: 'started',
      context: sessionContext,
    };
    this.emitImmediate(sessionStarted);
    if (previous != null && previous !== this.appSessionId) {
      const previousLast = this.readLastEvent(previous);
      const previousContext: AppLogContext = {
        previousAppSessionId: previous,
        previousLastEvent: previousLast?.event ?? 'unknown',
        previousLastCode: previousLast?.code ?? 'none',
        previousLastTimestamp: previousLast?.timestampUtc ?? 'unknown',
      };
      const uncleanShutdown: AppLogEvent = {
        source: 'ohos', level: 'WARN', category: 'app.lifecycle',
        event: 'previous_run_unclean_shutdown', outcome: 'observed',
        code: 'previous_run_unclean_shutdown',
        context: previousContext,
      };
      this.emitImmediate(uncleanShutdown);
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
    if (this.pending >= 1100 ||
      (this.pending >= 1000 && level !== 'ERROR' && level !== 'FATAL')) {
      this.incrementDropped(level);
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
    const ended: AppLogEvent = {
      source: 'ohos', level: 'INFO', category: 'app.lifecycle',
      event: 'app_session_ended', outcome: 'succeeded',
    };
    this.emit(ended);
    return this.flush().then((): void => {
      try { fs.unlinkSync(this.markerFile); } catch (_error) {}
    });
  }

  snapshot(limit: number): AppLogSnapshot {
    const count = Math.max(1, Math.min(500, limit));
    let totalBytes = 0;
    try {
      for (const name of fs.listFileSync(this.logsDirectory)) {
        totalBytes += fs.statSync(`${this.logsDirectory}/${name}`).size;
      }
    } catch (_error) {}
    const snapshot: AppLogSnapshot = {
      appSessionId: this.appSessionId,
      persisting: !this.degraded,
      degraded: this.degraded,
      logDirectory: this.logsDirectory,
      totalBytes: totalBytes,
      writeFailureCount: this.writeFailureCount,
      droppedByLevel: this.dropped,
      events: this.recent.slice(Math.max(0, this.recent.length - count)),
    };
    return snapshot;
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
    const value: SerializedLogEvent = {
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
    if (input.code != null) value.code = this.sanitize(input.code, 256);
    if (input.message != null) value.message = this.sanitize(input.message, 2048);
    if (input.gameSessionId != null) value.gameSessionId = this.sanitize(input.gameSessionId, 256);
    if (input.operationId != null) value.operationId = this.sanitize(input.operationId, 256);
    if (input.durationMs != null) value.durationMs = input.durationMs;
    if (input.context != null) value.context = this.sanitizeContext(input.context);
    if (input.error != null) value.error = this.sanitizeError(input.error);
    let line = JSON.stringify(value);
    if (line.length > 16 * 1024) {
      const emptyContext: AppLogContext = {};
      value.context = emptyContext;
      value.message = 'Log event exceeded 16 KB and was truncated';
      line = JSON.stringify(value);
    }
    this.recent.push(value);
    if (this.recent.length > 500) this.recent.splice(0, this.recent.length - 500);
    if (this.degraded) return;
    try {
      const path = this.segmentPath(line.length + 1);
      let file: fs.File | null = null;
      try {
        file = fs.openSync(
          path,
          fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND,
        );
        fs.writeSync(file.fd, `${line}\n`);
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
    let names = fs.listFileSync(this.logsDirectory)
      .filter((name: string): boolean => name.endsWith('.jsonl'))
      .sort();
    const cutoffMs = Date.now() - 7 * 24 * 60 * 60 * 1000;
    for (const name of names) {
      const path = `${this.logsDirectory}/${name}`;
      const rawMtime = fs.statSync(path).mtime;
      const modifiedMs = rawMtime > 100000000000000
        ? rawMtime / 1000000
        : rawMtime < 100000000000 ? rawMtime * 1000 : rawMtime;
      if (modifiedMs < cutoffMs) {
        try { fs.unlinkSync(path); } catch (_error) {}
      }
    }
    names = fs.listFileSync(this.logsDirectory)
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
      const value = JSON.parse(fs.readTextSync(this.markerFile)) as AppSessionMarker;
      return value.appSessionId;
    } catch (_error) {
      return null;
    }
  }

  private readLastEvent(sessionId: string): SerializedLogEvent | null {
    try {
      const names = fs.listFileSync(this.logsDirectory)
        .filter((name: string): boolean =>
          name.startsWith(`app-${sessionId}-`) && name.endsWith('.jsonl'))
        .sort();
      if (names.length === 0) return null;
      const text = fs.readTextSync(`${this.logsDirectory}/${names[names.length - 1]}`);
      const lines = text.split('\n').filter((line: string): boolean => line.trim().length > 0);
      if (lines.length === 0) return null;
      return JSON.parse(lines[lines.length - 1]) as SerializedLogEvent;
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

  private sanitizeContext(value: AppLogContext): AppLogContext {
    const result: AppLogContext = {};
    result.platform = this.sanitizeOptional(value.platform);
    result.appVersion = this.sanitizeOptional(value.appVersion);
    result.osVersion = this.sanitizeOptional(value.osVersion);
    result.state = this.sanitizeOptional(value.state);
    result.stage = this.sanitizeOptional(value.stage);
    result.transactionState = this.sanitizeOptional(value.transactionState);
    result.targetSlot = this.sanitizeOptional(value.targetSlot);
    result.recoveryAction = this.sanitizeOptional(value.recoveryAction);
    result.activeSlot = this.sanitizeOptional(value.activeSlot);
    result.currentResourceUsable = value.currentResourceUsable;
    result.processedBytes = value.processedBytes;
    result.totalBytes = value.totalBytes;
    result.processedFiles = value.processedFiles;
    result.totalFiles = value.totalFiles;
    result.fileCount = value.fileCount;
    result.buildProfile = this.sanitizeOptional(value.buildProfile);
    result.gpNextVersion = this.sanitizeOptional(value.gpNextVersion);
    result.cleanupDeferred = value.cleanupDeferred;
    result.gameVersion = this.sanitizeOptional(value.gameVersion);
    result.previousAppSessionId = this.sanitizeOptional(value.previousAppSessionId);
    result.previousLastEvent = this.sanitizeOptional(value.previousLastEvent);
    result.previousLastCode = this.sanitizeOptional(value.previousLastCode);
    result.previousLastTimestamp = this.sanitizeOptional(value.previousLastTimestamp);
    result.reason = this.sanitizeOptional(value.reason);
    result.command = this.sanitizeOptional(value.command);
    result.page = this.sanitizeOptional(value.page);
    result.line = value.line;
    result.column = value.column;
    result.path = this.sanitizeOptional(value.path);
    result.status = value.status;
    result.statusCode = value.statusCode;
    result.expectedMime = this.sanitizeOptional(value.expectedMime);
    result.actualMime = this.sanitizeOptional(value.actualMime);
    result.errorType = this.sanitizeOptional(value.errorType);
    result.crashed = value.crashed;
    result.url = this.sanitizeOptional(value.url);
    return result;
  }

  private sanitizeError(value: AppLogError): AppLogError {
    const result: AppLogError = {};
    result.type = this.sanitizeOptional(value.type);
    if (value.message != null) result.message = this.sanitize(value.message, 4096);
    if (value.stackTrace != null) result.stackTrace = this.sanitize(value.stackTrace, 8192);
    return result;
  }

  private sanitizeOptional(value: string | undefined): string | undefined {
    return value == null ? undefined : this.sanitize(value, 4096);
  }

  private incrementDropped(level: string): void {
    switch (level) {
      case 'DEBUG': this.dropped.DEBUG += 1; break;
      case 'WARN': this.dropped.WARN += 1; break;
      case 'ERROR': this.dropped.ERROR += 1; break;
      case 'FATAL': this.dropped.FATAL += 1; break;
      default: this.dropped.INFO += 1;
    }
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
