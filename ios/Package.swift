// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GardendlessNativeGameHost",
  defaultLocalization: "en",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "GardendlessNativeCore", targets: ["GardendlessNativeCore"]),
  ],
  targets: [
    .target(
      name: "GardendlessNativeCore",
      path: "Runner",
      exclude: [
        "AppDelegate.swift",
        "AppLogStore.swift",
        "Assets.xcassets",
        "Base.lproj",
        "GameNavigationDelegate.swift",
        "GameAudioBridge.swift",
        "GameScriptBridge.swift",
        "GameViewController.swift",
        "GeneratedPluginRegistrant.h",
        "GeneratedPluginRegistrant.m",
        "GpNextNativeCore.swift",
        "Info.plist",
        "NativeSfxEngine.swift",
        "Runner-Bridging-Header.h",
        "SceneDelegate.swift",
        "WebKitHighRefreshRate.h",
      ],
      sources: [
        "GameResourceLocator.swift",
        "GameResourceSchemeHandler.swift",
        "GameSession.swift",
        "JavaScriptArgumentEncoder.swift",
      ]
    ),
    .testTarget(
      name: "GardendlessNativeCoreTests",
      dependencies: ["GardendlessNativeCore"],
      path: "RunnerTests",
      sources: ["RunnerTests.swift"]
    ),
  ]
)
