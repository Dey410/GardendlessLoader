import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let gameFileExporterChannelName =
    "io.github.dey410.gardendlessloader/game_file_exporter"
  private var pendingExportResult: FlutterResult?

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
      guard call.method == "exportFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.exportFile(call: call, result: result)
    }
  }

  private func exportFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

      if self?.pendingExportResult != nil {
        result(FlutterError(
          code: "export_in_progress",
          message: "Another export is already in progress",
          details: nil
        ))
        return
      }

      let documentPicker = self?.makeDocumentPicker(for: fileUrl)
      guard let documentPicker else {
        result(FlutterError(
          code: "missing_document_picker",
          message: "Unable to create export picker",
          details: nil
        ))
        return
      }
      documentPicker.delegate = self
      documentPicker.modalPresentationStyle = .formSheet
      if let popover = documentPicker.popoverPresentationController {
        let fallbackRect = CGRect(x: 1, y: 1, width: 1, height: 1)
        popover.sourceView = rootController.view
        popover.sourceRect = self?.sourceRect(from: args) ?? fallbackRect
        popover.permittedArrowDirections = []
      }

      self?.pendingExportResult = result
      rootController.present(documentPicker, animated: true)
    }
  }

  private func makeDocumentPicker(for fileUrl: URL) -> UIDocumentPickerViewController {
    if #available(iOS 14.0, *) {
      return UIDocumentPickerViewController(
        forExporting: [fileUrl],
        asCopy: true
      )
    }
    return UIDocumentPickerViewController(
      url: fileUrl,
      in: .exportToService
    )
  }

  private func sourceRect(from args: [String: Any]) -> CGRect {
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

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingExportResult?(FlutterError(
      code: "export_cancelled",
      message: "Export was cancelled",
      details: nil
    ))
    pendingExportResult = nil
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    pendingExportResult?(nil)
    pendingExportResult = nil
  }
}
