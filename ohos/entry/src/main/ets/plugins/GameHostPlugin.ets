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

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/game_host';

export class GameHostPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private launching: boolean = false;

  getUniqueClassName(): string {
    return 'GameHostPlugin';
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
    if (call.method !== 'launch') {
      result.notImplemented();
      return;
    }
    if (this.launching) {
      result.error('game_host_launch_busy', '原生游戏宿主正在启动', null);
      return;
    }
    const context = this.context;
    if (context == null) {
      result.error('game_host_unavailable', '无法获取 Ability 上下文', null);
      return;
    }
    const argumentsObject = call.argument as Object;
    const sessionJson = JSON.stringify(argumentsObject);
    if (sessionJson.length > 1024 * 1024) {
      result.error('invalid_game_session', '原生游戏会话过大', null);
      return;
    }
    this.launching = true;
    context.startAbility({
      bundleName: 'io.github.dey410.gardendlessloader',
      abilityName: 'GameAbility',
      parameters: { gameSession: sessionJson },
    }).then(() => {
      result.success(null);
      return context.terminateSelf();
    }).catch((error: Error) => {
      this.launching = false;
      result.error('game_host_launch_failed', error.message ?? error.toString(), null);
    });
  }
}
