import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import AbilityAware, { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/document_picker';

export class DocumentPickerPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'DocumentPickerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbilityContext();
  }

  onDetachedFromAbility(): void {
    this.abilityContext = null;
  }

  onReattachedToAbilityForConfigChanges(binding: AbilityPluginBinding): void {
    this.onAttachedToAbility(binding);
  }

  onDetachedFromAbilityForConfigChanges(): void {
    this.onDetachedFromAbility();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'pickDocsDirectory') {
      this.pickDocsDirectory(result);
      return;
    }

    result.notImplemented();
  }

  private pickDocsDirectory(result: MethodResult): void {
    const context = this.abilityContext;
    if (context === null) {
      result.error('NO_ABILITY', '无法打开鸿蒙文档选择器：Ability 不可用', null);
      return;
    }

    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;

    const documentPicker = new picker.DocumentViewPicker(context);
    documentPicker.select(options).then((uris: Array<string>) => {
      if (uris.length === 0) {
        result.success(null);
        return;
      }

      const selectedPath = new fileUri.FileUri(uris[0]).path;
      result.success(selectedPath);
    }).catch((error: BusinessError) => {
      result.error(
        'PICK_FAILED',
        `鸿蒙文档选择器打开失败：${error.message}`,
        error.code,
      );
    });
  }
}
