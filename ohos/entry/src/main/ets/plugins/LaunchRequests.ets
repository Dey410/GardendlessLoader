import { Want } from '@kit.AbilityKit';

const ACTION_VIEW_DATA = 'ohos.want.action.viewData';

/**
 * Launch requests from outside the launcher: a ZIP another app opens with
 * the loader and home-screen shortcuts. The launcher ability is closed while
 * the game runs, so a ZIP waits here, in the app process, until the launcher
 * imports or discards it.
 */
export class LaunchRequests {
  static zipUri: string | null = null;
  static shortcut: string | null = null;
  static gameRunning: boolean = false;
  static onZip: ((name: string) => void) | null = null;
  static onShortcut: ((shortcut: string) => void) | null = null;

  /** Keeps what a want asks for; returns whether it asked for anything. */
  static receive(want: Want): boolean {
    const uri = want.uri;
    if (want.action === ACTION_VIEW_DATA && uri !== undefined && uri.length > 0) {
      LaunchRequests.zipUri = uri;
      return true;
    }
    const raw = want.parameters?.['shortcut'];
    const shortcut = typeof raw === 'string' ? raw : null;
    if (shortcut !== null) {
      LaunchRequests.shortcut = shortcut;
      return true;
    }
    return false;
  }

  /** Tells the running launcher about what it just received. */
  static announce(): void {
    const uri = LaunchRequests.zipUri;
    const onZip = LaunchRequests.onZip;
    if (uri !== null && onZip !== null) {
      onZip(LaunchRequests.zipName(uri));
    }
    const shortcut = LaunchRequests.shortcut;
    const onShortcut = LaunchRequests.onShortcut;
    if (shortcut !== null && onShortcut !== null) {
      LaunchRequests.shortcut = null;
      onShortcut(shortcut);
    }
  }

  static zipName(uri: string): string {
    return decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
  }
}
