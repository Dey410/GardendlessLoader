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
import { appLogStore, AppLogEvent } from '../logging/AppLogStore';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/app_logger';

export class AppLoggerPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'AppLoggerPlugin';
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
    appLogStore.initialize(binding.getAbility().context as common.Context);
  }

  onDetachedFromAbility(): void {}

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'initialize') {
      result.success({ appSessionId: appLogStore.getSessionId() });
      return;
    }
    if (call.method === 'emit') {
      appLogStore.emit(call.args as AppLogEvent);
      result.success(null);
      return;
    }
    if (call.method === 'snapshot') {
      const args = call.args as Record<string, Object>;
      appLogStore.flush().then((): void => {
        result.success(appLogStore.snapshot((args['limit'] as number) ?? 500));
      });
      return;
    }
    if (call.method === 'flush') {
      appLogStore.flush().then((): void => result.success(null));
      return;
    }
    if (call.method === 'deleteHistory') {
      appLogStore.deleteHistory().then((): void => result.success(null));
      return;
    }
    if (call.method === 'endSession') {
      appLogStore.endSession().then((): void => result.success(null));
      return;
    }
    result.notImplemented();
  }
}
