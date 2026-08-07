// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "GardendlessKit",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v14),
    .macOS(.v13),
  ],
  products: [
    .library(name: "GardendlessCore", targets: ["GardendlessCore"]),
    .library(name: "GardendlessResource", targets: ["GardendlessResource"]),
    .library(name: "GardendlessBridge", targets: ["GardendlessBridge"]),
    .library(name: "GardendlessImport", targets: ["GardendlessImport"]),
    .library(name: "GardendlessGPNext", targets: ["GardendlessGPNext"]),
    .library(name: "GardendlessAudio", targets: ["GardendlessAudio"]),
    .library(name: "GardendlessLogging", targets: ["GardendlessLogging"]),
  ],
  targets: [
    .target(
      name: "GardendlessCore",
      path: "Sources/GardendlessCore"
    ),
    .target(
      name: "GardendlessResource",
      dependencies: ["GardendlessCore"],
      path: "Sources/GardendlessResource"
    ),
    .target(
      name: "GardendlessBridge",
      dependencies: ["GardendlessCore"],
      path: "Sources/GardendlessBridge"
    ),
    .target(
      name: "GardendlessImport",
      dependencies: ["GardendlessCore"],
      path: "Sources/GardendlessImport"
    ),
    .target(
      name: "GardendlessGPNext",
      dependencies: ["GardendlessCore"],
      path: "Sources/GardendlessGPNext"
    ),
    .target(
      name: "GardendlessAudio",
      dependencies: ["GardendlessCore", "SfxExceptionGuard"],
      path: "Sources/GardendlessAudio"
    ),
    .target(
      name: "SfxExceptionGuard",
      path: "Sources/SfxExceptionGuard"
    ),
    .target(
      name: "GardendlessLogging",
      path: "Sources/GardendlessLogging"
    ),
    .testTarget(
      name: "GardendlessKitTests",
      dependencies: [
        "GardendlessCore",
        "GardendlessResource",
        "GardendlessBridge",
        "GardendlessImport",
        "GardendlessGPNext",
        "GardendlessAudio",
        "GardendlessLogging",
        "SfxExceptionGuard",
      ],
      path: "Tests/GardendlessKitTests",
      resources: [
        .copy("Fixtures")
      ]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
