import { FlutterPlugin, FlutterPluginBinding, MethodChannel } from '@ohos/flutter_ohos';

const CHANNEL_NAME = 'io.github.dey410.gardendlessloader/gamepad';

/**
 * Sends the launcher the direction the left stick holds: "up", "down",
 * "left", "right" or "none". Flutter receives the D-pad, A and B as keys,
 * but the stick reaches ArkUI only as focus axis events, which the launcher
 * page hands to stick().
 */
export class GamepadPlugin implements FlutterPlugin {
  /** The plugin of the running launcher engine. */
  static attached: GamepadPlugin | null = null;

  private channel: MethodChannel | null = null;
  private x: number = 0;
  private y: number = 0;
  private direction: string = 'none';

  getUniqueClassName(): string {
    return 'GamepadPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    GamepadPlugin.attached = this;
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    GamepadPlugin.attached = null;
    this.channel = null;
  }

  /**
   * The input service scales the stick to -1..1, with y growing downwards.
   * A direction needs 0.6 of the tilt to start and keeps down to 0.4, so it
   * does not flicker at the threshold.
   */
  stick(event: FocusAxisEvent): void {
    this.x = event.axisMap.get(AxisModel.ABS_X) ?? this.x;
    this.y = event.axisMap.get(AxisModel.ABS_Y) ?? this.y;
    const tilt = Math.max(Math.abs(this.x), Math.abs(this.y));
    let direction = 'none';
    if (tilt > (this.direction === 'none' ? 0.6 : 0.4)) {
      direction = Math.abs(this.x) > Math.abs(this.y)
        ? (this.x > 0 ? 'right' : 'left')
        : (this.y > 0 ? 'down' : 'up');
    }
    if (direction !== this.direction) {
      this.direction = direction;
      this.channel?.invokeMethod('input', direction);
    }
  }
}
