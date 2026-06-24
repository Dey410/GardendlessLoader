import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let gameFileExporterChannelName =
    "io.github.dey410.gardendlessloader/game_file_exporter"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerGameFileExporter()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerGameFileExporter() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: gameFileExporterChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.shareExportedFile(call: call, result: result)
    }
  }

  private func shareExportedFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "Missing export file path",
        details: nil
      ))
      return
    }

    let fileUrl = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      result(FlutterError(
        code: "file_not_found",
        message: "Export file does not exist",
        details: path
      ))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let rootController = self?.topViewController() else {
        result(FlutterError(
          code: "missing_view_controller",
          message: "Unable to present export sheet",
          details: nil
        ))
        return
      }

      let activityController = UIActivityViewController(
        activityItems: [fileUrl],
        applicationActivities: nil
      )
      if let popover = activityController.popoverPresentationController {
        let fallbackRect = CGRect(x: 1, y: 1, width: 1, height: 1)
        popover.sourceView = rootController.view
        popover.sourceRect = self?.shareSourceRect(from: args) ?? fallbackRect
        popover.permittedArrowDirections = []
      }

      rootController.present(activityController, animated: true) {
        result(nil)
      }
    }
  }

  private func shareSourceRect(from args: [String: Any]) -> CGRect {
    let x = args["originX"] as? Double ?? 1
    let y = args["originY"] as? Double ?? 1
    let width = max(args["originWidth"] as? Double ?? 1, 1)
    let height = max(args["originHeight"] as? Double ?? 1, 1)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func topViewController() -> UIViewController? {
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
