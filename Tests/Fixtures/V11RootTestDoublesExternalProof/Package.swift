// swift-tools-version: 6.2

import PackageDescription

let visorTestDoubles: Target.Dependency = .product(
  name: "VISORTestDoubles",
  package: "visor")

let package = Package(
  name: "V11RootTestDoublesExternalProof",
  platforms: [
    .macOS(.v14),
  ],
  dependencies: [
    .package(path: "../../.."),
  ],
  targets: [
    .target(
      name: "RootTestDoubleModels",
      dependencies: [visorTestDoubles],
      packageAccess: false),
    .testTarget(
      name: "RootTestDoubleBoundaryTests",
      dependencies: ["RootTestDoubleModels"],
      packageAccess: false),
  ])
