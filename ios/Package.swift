// swift-tools-version: 5.9

// Retired legacy SwiftPM test package.
//
// The original GardendlessNativeGameHost package tested the pre-shredder iOS
// implementation, whose source files have been removed from the working tree
// after user confirmation. Native core tests now live in:
//   ios/GardendlessKit/Package.swift

import PackageDescription

let package = Package(
  name: "GardendlessNativeGameHost",
  products: [
    .library(name: "GardendlessLegacy", targets: ["GardendlessLegacy"]),
  ],
  targets: [
    .target(name: "GardendlessLegacy", path: "Sources/GardendlessLegacy"),
  ]
)
