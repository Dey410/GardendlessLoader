const MAX_LENGTH = 4096;
const VERSION = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const SLOT = /^[0-9]{1,9}$/;
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SHA1 = /^[a-f0-9]{40}$/;
const UNSAFE_PATH = /[\\\x00-\x1f\x7f]/;

/**
 * pvzge: links that GP-Next's websites open: a Nest one-click install, a
 * Daily Level and a GitHub level. Only these three exact forms pass; GP-Next
 * validates them again before it acts on one.
 */
export class DeepLinks {
  /** The link itself when it is one of the three supported forms, else null. */
  static validate(raw: string): string | null {
    if (raw.length === 0 || raw.length > MAX_LENGTH || !raw.startsWith('pvzge://')) return null;
    for (let index = 0; index < raw.length; index++) {
      const code = raw.charCodeAt(index);
      if (code < 0x21 || code > 0x7e) return null;
    }
    const rest = raw.substring('pvzge://'.length);
    const queryStart = rest.indexOf('?');
    if (rest.includes('#') || queryStart < 0) return null;
    const location = rest.substring(0, queryStart);
    const slash = location.indexOf('/');
    if (slash < 0) return null;
    // An exact host also rules out user info and a port.
    const host = location.substring(0, slash);
    const path = location.substring(slash);
    const query = DeepLinks.parseQuery(rest.substring(queryStart + 1));
    if (query === null) return null;
    let valid = false;
    if (host === 'nest') {
      valid = path === '/import' && DeepLinks.hasKeys(query, ['version']) &&
        VERSION.test(query.get('version') ?? '');
    } else if (host === 'daily-level') {
      const slug = query.get('slug') ?? '';
      valid = path === '/open' && DeepLinks.hasKeys(query, ['date', 'slot', 'slug']) &&
        DeepLinks.isDate(query.get('date') ?? '') && SLOT.test(query.get('slot') ?? '') &&
        slug.length <= 200 && SLUG.test(slug);
    } else if (host === 'github-level') {
      valid = path === '/open' && DeepLinks.hasKeys(query, ['path', 'sha']) &&
        SHA1.test(query.get('sha') ?? '') && DeepLinks.isLevelPath(query.get('path') ?? '');
    }
    return valid ? raw : null;
  }

  /** Each key once, decoded like URLSearchParams; null for a malformed or repeated parameter. */
  private static parseQuery(raw: string): Map<string, string> | null {
    if (raw.length === 0) return null;
    const result = new Map<string, string>();
    for (const pair of raw.split('&')) {
      const separator = pair.indexOf('=');
      if (separator <= 0) return null;
      let key: string;
      let value: string;
      try {
        key = decodeURIComponent(pair.substring(0, separator).replace(/\+/g, ' '));
        value = decodeURIComponent(pair.substring(separator + 1).replace(/\+/g, ' '));
      } catch (_error) {
        return null;
      }
      if (result.has(key)) return null;
      result.set(key, value);
    }
    return result;
  }

  private static hasKeys(query: Map<string, string>, keys: string[]): boolean {
    if (query.size !== keys.length) return false;
    for (const key of keys) {
      if (!query.has(key)) return false;
    }
    return true;
  }

  private static isDate(value: string): boolean {
    const match = DATE.exec(value);
    if (match === null) return false;
    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    if (month < 1 || month > 12 || day < 1) return false;
    const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return day <= days[month - 1];
  }

  private static isLevelPath(value: string): boolean {
    if (value.length === 0 || value.length > 2048 || !value.toLowerCase().endsWith('.json') ||
      UNSAFE_PATH.test(value)) {
      return false;
    }
    for (const part of value.split('/')) {
      if (part.length === 0 || part === '.' || part === '..') return false;
    }
    return true;
  }
}

class DeepLinkEntry {
  readonly url: string;
  readonly receivedAt: number;

  constructor(url: string, receivedAt: number) {
    this.url = url;
    this.receivedAt = receivedAt;
  }
}

/**
 * Validated links wait here, in the app process, until a game page takes
 * them with host:takeDeepLinks. A link nobody takes within ten minutes is
 * dropped so it cannot surprise a later game.
 */
export class DeepLinkInbox {
  private static readonly MAX_LINKS: number = 8;
  private static readonly LIFETIME_MS: number = 10 * 60 * 1000;
  private static entries: DeepLinkEntry[] = [];
  /** Set by the running game; told when a link arrives. */
  static onAvailable: (() => void) | null = null;

  static offer(url: string): void {
    DeepLinkInbox.prune();
    DeepLinkInbox.entries = DeepLinkInbox.entries.filter((entry: DeepLinkEntry): boolean => entry.url !== url);
    DeepLinkInbox.entries.push(new DeepLinkEntry(url, Date.now()));
    while (DeepLinkInbox.entries.length > DeepLinkInbox.MAX_LINKS) DeepLinkInbox.entries.shift();
    const notify = DeepLinkInbox.onAvailable;
    if (notify !== null) notify();
  }

  static drain(): string[] {
    DeepLinkInbox.prune();
    const urls = DeepLinkInbox.entries.map((entry: DeepLinkEntry): string => entry.url);
    DeepLinkInbox.entries = [];
    return urls;
  }

  private static prune(): void {
    const now = Date.now();
    DeepLinkInbox.entries = DeepLinkInbox.entries.filter(
      (entry: DeepLinkEntry): boolean => now - entry.receivedAt <= DeepLinkInbox.LIFETIME_MS);
  }
}
