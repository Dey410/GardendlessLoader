import Flutter
import GameController
import QuartzCore
import UIKit

/// Lets a game controller drive the launcher. Flutter on iOS receives no
/// controller input, so while a controller is connected this reads the
/// controllers every frame and sends Flutter the held direction ("up",
/// "down", "left", "right" or "none") and each press of "a" and "b".
///
/// It only reads their state: the game's WebView keeps its own handlers on
/// the same GCController objects for the Gamepad API.
final class LauncherGamepad {
  private let channel: FlutterMethodChannel
  private weak var launcher: UIViewController?
  private var observers: [NSObjectProtocol] = []
  private var displayLink: CADisplayLink?
  private var direction = "none"
  private var aHeld = false
  private var bHeld = false

  init(launcher: FlutterViewController) {
    self.launcher = launcher
    channel = FlutterMethodChannel(
      name: "io.github.dey410.gardendlessloader/gamepad",
      binaryMessenger: launcher.binaryMessenger
    )
    observers = [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect].map {
      NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) {
        [weak self] _ in self?.updatePolling()
      }
    }
    updatePolling()
  }

  /// Stops reading the controllers once the launcher is gone.
  func stop() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
    displayLink?.invalidate()
    displayLink = nil
  }

  private func updatePolling() {
    if GCController.controllers().isEmpty {
      displayLink?.invalidate()
      displayLink = nil
      report(direction: "none", a: false, b: false)
    } else if displayLink == nil {
      let link = CADisplayLink(target: self, selector: #selector(poll))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common)
      displayLink = link
    }
  }

  @objc private func poll() {
    // A sheet over the launcher, such as the file picker, has the screen.
    let pads = launcher?.presentedViewController == nil
      ? GCController.controllers().compactMap(\.extendedGamepad)
      : []
    report(
      direction: heldDirection(pads),
      a: pads.contains { $0.buttonA.isPressed },
      b: pads.contains { $0.buttonB.isPressed }
    )
  }

  private func report(direction: String, a: Bool, b: Bool) {
    if direction != self.direction {
      self.direction = direction
      channel.invokeMethod("input", arguments: direction)
    }
    if a && !aHeld {
      channel.invokeMethod("input", arguments: "a")
    }
    if b && !bHeld {
      channel.invokeMethod("input", arguments: "b")
    }
    aHeld = a
    bHeld = b
  }

  /// The direction the D-pad or left stick pushes furthest. A stick needs
  /// 0.6 of its tilt to start a direction and keeps it down to 0.4, so it
  /// does not flicker at the threshold.
  private func heldDirection(_ pads: [GCExtendedGamepad]) -> String {
    var held = (tilt: direction == "none" ? Float(0.6) : 0.4, name: "none")
    for pad in pads {
      for input in [pad.dpad, pad.leftThumbstick] {
        let x = input.xAxis.value
        let y = input.yAxis.value
        for (tilt, name) in [(x, "right"), (-x, "left"), (y, "up"), (-y, "down")] where tilt > held.tilt {
          held = (tilt, name)
        }
      }
    }
    return held.name
  }
}
