import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import { FlutterPage } from '@ohos/flutter_ohos'
import { GamepadPlugin } from '../plugins/GamepadPlugin';

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";

  build() {
    Column() {
      // The stick reaches ArkUI only as focus axis events, which API 15
      // added; they bubble up here from Flutter's focused view.
      if (deviceInfo.sdkApiVersion >= 15) {
        Column() {
          FlutterPage({ viewId: this.viewId })
        }
        .onFocusAxisEvent((event: FocusAxisEvent) => {
          GamepadPlugin.attached?.stick(event);
        })
      } else {
        FlutterPage({ viewId: this.viewId })
      }
    }
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
