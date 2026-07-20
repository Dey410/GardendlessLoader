import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import window from '@ohos.window';

export default class GameAbility extends UIAbility {
  private sessionJson: string = '';

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const raw = want.parameters?.['gameSession'];
    this.sessionJson = typeof raw === 'string' ? raw : '';
    webview.WebviewController.initializeWebEngine();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const storage = LocalStorage.getShared();
    storage.setOrCreate<string>('gameSession', this.sessionJson);
    windowStage.loadContent('pages/GamePage', storage).catch((error: Error) => {
      console.error(`Unable to load native GamePage: ${error.message}`);
      this.context.terminateSelf();
    });
  }
}
