import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { GameFileExporterPlugin } from '../plugins/GameFileExporterPlugin';
import { GpNextFileImporterPlugin } from '../plugins/GpNextFileImporterPlugin';
import { ResourceZipImporterPlugin } from '../plugins/ResourceZipImporterPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.addPlugin(new GameFileExporterPlugin())
    this.addPlugin(new GpNextFileImporterPlugin())
    this.addPlugin(new ResourceZipImporterPlugin())
  }
}
