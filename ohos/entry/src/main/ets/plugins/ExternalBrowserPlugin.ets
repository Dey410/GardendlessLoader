import common from '@ohos.app.ability.common';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/external_browser';

export class ExternalBrowserPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'ExternalBrowserPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'open') {
      result.notImplemented();
      return;
    }
    const url = call.argument('url') as string;
    if (url == null || (!url.startsWith('https://') && !url.startsWith('http://'))) {
      result.error('invalid_external_url', '只允许打开 HTTP(S) 链接', null);
      return;
    }
    const context = this.context;
    if (context == null) {
      result.error('external_open_failed', '无法获取 Ability 上下文', null);
      return;
    }
    context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('external_open_failed', error.message, null));
  }
}
