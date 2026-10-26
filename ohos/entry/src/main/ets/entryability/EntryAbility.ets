import { AbilityConstant, Want } from '@kit.AbilityKit';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { ExternalBrowserPlugin } from '../plugins/ExternalBrowserPlugin';
import { GamepadPlugin } from '../plugins/GamepadPlugin';
import { AppLoggerPlugin } from '../plugins/AppLoggerPlugin';
import { GameHostPlugin } from '../plugins/GameHostPlugin';
import { ResourceZipImporterPlugin } from '../plugins/ResourceZipImporterPlugin';
import { ShortcutPlugin } from '../plugins/ShortcutPlugin';
import { LaunchRequests } from '../plugins/LaunchRequests';

export default class EntryAbility extends FlutterAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    const requested = LaunchRequests.receive(want);
    await super.onCreate(want, launchParam);
    if (requested && LaunchRequests.gameRunning) {
      // The game reads the active slot: a ZIP waits until the player returns
      // to the launcher, and a shortcut only brings the game back.
      LaunchRequests.shortcut = null;
      await this.context.startAbility({
        bundleName: 'io.github.dey410.gardendlessloader',
        abilityName: 'GameAbility',
      });
      await this.context.terminateSelf();
    }
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParams);
    if (LaunchRequests.receive(want)) {
      LaunchRequests.announce();
    }
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.addPlugin(new ExternalBrowserPlugin())
    this.addPlugin(new AppLoggerPlugin())
    this.addPlugin(new GameHostPlugin())
    this.addPlugin(new ResourceZipImporterPlugin())
    this.addPlugin(new ShortcutPlugin())
    this.addPlugin(new GamepadPlugin())
  }
}
