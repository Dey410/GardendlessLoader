import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { ExternalBrowserPlugin } from '../plugins/ExternalBrowserPlugin';
import { GameHostPlugin } from '../plugins/GameHostPlugin';
import { ResourceZipImporterPlugin } from '../plugins/ResourceZipImporterPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.addPlugin(new ExternalBrowserPlugin())
    this.addPlugin(new GameHostPlugin())
    this.addPlugin(new ResourceZipImporterPlugin())
  }
}
