// swift-tools-version: 6.2

import PackageDescription

let visorTestDoubles = Target.Dependency.product(
  name: "VISORTestDoubles",
  package: "visor",
)

let package = Package(
  name: "V11RootTestDoublesExternalProof",
  platforms: [
    .macOS(.v14)
  ],
  dependencies: [
    .package(path: "../../..")
  ],
  targets: [
    .target(
      name: "PackageTestDoubleModels",
      dependencies: [visorTestDoubles],
    ),
    .testTarget(
      name: "PackageTestDoubleConsumerTests",
      dependencies: ["PackageTestDoubleModels"],
    ),
    .target(
      name: "MainActorTestDoubleModels",
      dependencies: [visorTestDoubles],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
    .testTarget(
      name: "MainActorTestDoubleBoundaryTests",
      dependencies: ["MainActorTestDoubleModels"],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
    .target(
      name: "RootTestDoubleModels",
      dependencies: [visorTestDoubles],
      packageAccess: false,
    ),
    .testTarget(
      name: "RootTestDoubleBoundaryTests",
      dependencies: ["RootTestDoubleModels"],
      packageAccess: false,
    ),
  ],
)
