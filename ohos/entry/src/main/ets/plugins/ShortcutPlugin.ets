import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { LaunchRequests } from './LaunchRequests';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/shortcuts';

/** Hands home-screen shortcuts from resources/base/profile/shortcuts_config.json to the launcher. */
export class ShortcutPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'ShortcutPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    LaunchRequests.onShortcut = (shortcut: string): void => {
      this.channel?.invokeMethod('perform', shortcut);
    };
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    LaunchRequests.onShortcut = null;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'take') {
      result.notImplemented();
      return;
    }
    const shortcut = LaunchRequests.shortcut;
    LaunchRequests.shortcut = null;
    result.success(shortcut);
  }
}
