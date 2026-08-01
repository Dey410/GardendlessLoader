import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import window from '@ohos.window';
import { appLogStore, AppLogContext, AppLogEvent } from '../logging/AppLogStore';

export default class GameAbility extends UIAbility {
  private sessionJson: string = '';
  private readonly storage: LocalStorage = new LocalStorage();
  private returningToLauncher: boolean = false;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    appLogStore.initialize(this.context);
    this.logStage('ability_on_create_entered');
    try {
      const raw = want.parameters?.['gameSession'];
      this.sessionJson = typeof raw === 'string' ? raw : '';
      this.logStage('session_parameter_received');
      webview.WebviewController.initializeWebEngine();
      this.logStage('web_engine_initialized');
    } catch (error) {
      this.logFailure('game_ability_create_failed', 'ability_on_create', error as Error);
      appLogStore.flush().finally((): void => this.startLauncher());
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    if (this.returningToLauncher) {
      return;
    }
    this.logStage('window_stage_create_entered');
    try {
      this.storage.setOrCreate<string>('gameSession', this.sessionJson);
      this.logStage('local_storage_ready');
    } catch (error) {
      this.logFailure('game_ability_storage_failed', 'local_storage', error as Error);
      appLogStore.flush().finally((): void => this.startLauncher());
      return;
    }
    windowStage.getMainWindow().then((gameWindow: window.Window): void => {
      gameWindow.setWindowLayoutFullScreen(true).catch((error: Error): void => {
        console.error(`Unable to enable full-screen game layout: ${error.message}`);
      });
      gameWindow.setWindowSystemBarEnable([]).catch((error: Error): void => {
        console.error(`Unable to hide game system bars: ${error.message}`);
      });
    }).catch((error: Error): void => {
      console.error(`Unable to configure the game window: ${error.message}`);
    });
    this.logStage('load_content_started');
    try {
      windowStage.loadContent('pages/GamePage', this.storage).then((): void => {
        this.logStage('load_content_succeeded');
      }).catch((error: Error): void => {
        this.logFailure('game_ability_load_content_failed', 'load_content', error);
        appLogStore.flush().finally((): void => this.startLauncher());
      });
    } catch (error) {
      this.logFailure('game_ability_load_content_failed', 'load_content', error as Error);
      appLogStore.flush().finally((): void => this.startLauncher());
    }
  }

  private logStage(stage: string): void {
    const context: AppLogContext = { stage: stage };
    const event: AppLogEvent = {
      source: 'ohos',
      level: 'INFO',
      category: 'game.host',
      event: 'game_ability_stage_changed',
      outcome: 'observed',
      message: stage,
      context: context,
    };
    appLogStore.emit(event);
  }

  private logFailure(code: string, stage: string, error: Error): void {
    const context: AppLogContext = { stage: stage };
    const event: AppLogEvent = {
      source: 'ohos',
      level: 'ERROR',
      category: 'game.host',
      event: code,
      outcome: 'failed',
      code: code,
      message: error.message,
      context: context,
    };
    appLogStore.emit(event);
  }

  private startLauncher(): void {
    if (this.returningToLauncher) {
      return;
    }
    this.returningToLauncher = true;
    this.context.startAbility({
      bundleName: 'io.github.dey410.gardendlessloader',
      abilityName: 'EntryAbility',
    }).finally((): void => {
      this.context.terminateSelf();
    });
  }
}
