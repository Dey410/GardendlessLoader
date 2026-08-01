export interface GameSessionPayload {
  schemaVersion: number;
  sessionId: string;
  platform: string;
  origin: string;
  resourceRoot: string;
  entryUrl: string;
  activationGeneration: number;
  hasGpNext: boolean;
  gpNextCompatible: boolean;
  gpNextVersion?: string;
  watermarkEnabled: boolean;
  autoCollectSunEnabled: boolean;
  allowedRemoteHosts: string[];
  gpNextRoot: string;
  exportTemporaryRoot: string;
}

export class GameSession {
  static readonly ORIGIN: string = 'https://gardendless.invalid';
  readonly sessionId: string;
  readonly resourceRoot: string;
  readonly entryUrl: string;
  readonly activationGeneration: number;
  readonly hasGpNext: boolean;
  readonly gpNextCompatible: boolean;
  readonly gpNextVersion: string | null;
  readonly watermarkEnabled: boolean;
  readonly autoCollectSunEnabled: boolean;
  readonly allowedRemoteHosts: Set<string>;
  readonly gpNextRoot: string;
  readonly exportTemporaryRoot: string;

  constructor(raw: string) {
    if (raw.length === 0 || raw.length > 1024 * 1024) {
      throw new Error('Invalid game session size');
    }
    const value = JSON.parse(raw) as GameSessionPayload;
    if (value.schemaVersion !== 1 || value.platform !== 'ohos' || value.origin !== GameSession.ORIGIN) {
      throw new Error('Game session schema, platform or origin mismatch');
    }
    if (!value.entryUrl.startsWith(`${GameSession.ORIGIN}/`)) {
      throw new Error('Game entry URL escaped the synthetic origin');
    }
    this.sessionId = this.required(value.sessionId, 'sessionId');
    this.resourceRoot = this.required(value.resourceRoot, 'resourceRoot');
    this.entryUrl = value.entryUrl;
    this.activationGeneration = value.activationGeneration;
    this.hasGpNext = value.hasGpNext;
    this.gpNextCompatible = value.gpNextCompatible;
    this.gpNextVersion = value.gpNextVersion ?? null;
    this.watermarkEnabled = value.watermarkEnabled;
    this.autoCollectSunEnabled = value.autoCollectSunEnabled;
    this.allowedRemoteHosts = new Set<string>();
    for (const host of value.allowedRemoteHosts) {
      const normalized = host.toLowerCase();
      if (!this.isValidRemoteHost(normalized)) {
        throw new Error('Invalid remote host');
      }
      this.allowedRemoteHosts.add(normalized);
    }
    this.gpNextRoot = this.required(value.gpNextRoot, 'gpNextRoot');
    this.exportTemporaryRoot = this.required(value.exportTemporaryRoot, 'exportTemporaryRoot');
  }

  get appRoot(): string {
    const index = this.resourceRoot.lastIndexOf('/');
    if (index <= 0) {
      throw new Error('resourceRoot has no parent');
    }
    return this.resourceRoot.substring(0, index);
  }

  private required(value: string, name: string): string {
    if (value == null || value.length === 0) {
      throw new Error(`${name} is empty`);
    }
    return value;
  }

  private isValidRemoteHost(host: string): boolean {
    if (host.length === 0 || host.length > 253) {
      return false;
    }
    const labels = host.split('.');
    return labels.every((label: string): boolean =>
      label.length > 0 && label.length <= 63 &&
      /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label));
  }
}
