// swift-tools-version: 6.2

import PackageDescription

let visor = Target.Dependency.product(
  name: "VISOR",
  package: "visor",
)
let visorObservation = Target.Dependency.product(
  name: "VISORObservation",
  package: "visor",
)

let package = Package(
  name: "V11RootGatewayExternalProof",
  platforms: [
    .macOS(.v14)
  ],
  dependencies: [
    .package(path: "../../..")
  ],
  targets: [
    .target(
      name: "RootGatewayModelsNonisolated",
      dependencies: [
        "RootObservationConsumer",
        visor,
      ],
      packageAccess: false,
    ),
    .target(
      name: "RootGatewayModelsMainActor",
      dependencies: [
        "RootObservationConsumer",
        visor,
      ],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
    .target(
      name: "RootGatewayAccessControlProbe",
      dependencies: [
        "RootGatewayModelsNonisolated",
        visor,
      ],
      packageAccess: false,
    ),
    .target(
      name: "RootObservationConsumer",
      dependencies: [visor, visorObservation],
      packageAccess: false,
    ),
    .target(
      name: "RootObservationAccessControlProbe",
      dependencies: [
        "RootGatewayModelsNonisolated",
        "RootObservationConsumer",
        visor,
        visorObservation,
      ],
      packageAccess: false,
    ),
    .testTarget(
      name: "RootGatewayNonisolatedTests",
      dependencies: [
        "RootGatewayModelsNonisolated",
        "RootObservationConsumer",
        visor,
      ],
      packageAccess: false,
    ),
    .testTarget(
      name: "RootGatewayMainActorTests",
      dependencies: [
        "RootGatewayModelsMainActor",
        "RootObservationConsumer",
        visor,
      ],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
    .testTarget(
      name: "RootObservationConsumerTests",
      dependencies: ["RootObservationConsumer", visorObservation],
      packageAccess: false,
    ),
  ],
)
