// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "V11ExternalCompileProof",
  platforms: [
    .macOS(.v14),
  ],
  dependencies: [
    .package(path: "../V11CompileProof"),
  ],
  targets: [
    .target(
      name: "ExternalServices",
      dependencies: [
        .product(name: "VISORObservation", package: "v11compileproof"),
      ],
      packageAccess: false),
    .target(
      name: "ExternalDoubleConsumer",
      dependencies: [
        .product(name: "VISORTestDoubles", package: "v11compileproof"),
      ],
      packageAccess: false),
    .target(
      name: "ExternalModelsNonisolated",
      dependencies: [
        "ExternalServices",
        .product(name: "VISOR", package: "v11compileproof"),
      ],
      packageAccess: false),
    .target(
      name: "ExternalModelsMainActor",
      dependencies: [
        "ExternalServices",
        .product(name: "VISOR", package: "v11compileproof"),
      ],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .target(
      name: "ExternalAccessControlProbe",
      dependencies: [
        "ExternalModelsNonisolated",
        "ExternalServices",
        .product(name: "VISOR", package: "v11compileproof"),
        .product(name: "VISORObservation", package: "v11compileproof"),
      ],
      packageAccess: false),
    .testTarget(
      name: "ExternalNonisolatedTests",
      dependencies: [
        "ExternalAccessControlProbe",
        "ExternalDoubleConsumer",
        "ExternalModelsNonisolated",
        "ExternalServices",
        .product(name: "VISORTesting", package: "v11compileproof"),
      ],
      packageAccess: false),
    .testTarget(
      name: "ExternalMainActorTests",
      dependencies: [
        "ExternalDoubleConsumer",
        "ExternalModelsMainActor",
        "ExternalServices",
        .product(name: "VISORTesting", package: "v11compileproof"),
      ],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)]),
  ])
