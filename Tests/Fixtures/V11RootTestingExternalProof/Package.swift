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
let visorTesting = Target.Dependency.product(
  name: "VISORTesting",
  package: "visor",
)

let package = Package(
  name: "V11RootTestingExternalProof",
  platforms: [
    .macOS(.v14)
  ],
  dependencies: [
    .package(path: "../../..")
  ],
  targets: [
    .target(
      name: "RootTestingSupport",
      dependencies: [visorObservation],
      packageAccess: false,
    ),
    .target(
      name: "RootTestingModelsNonisolated",
      dependencies: ["RootTestingSupport", visor],
      packageAccess: false,
    ),
    .target(
      name: "RootTestingModelsMainActor",
      dependencies: ["RootTestingSupport", visor],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
    .target(
      name: "RootTestingSelectorProbe",
      dependencies: [
        "RootTestingModelsNonisolated",
        visor,
        visorTesting,
      ],
      packageAccess: false,
    ),
    .testTarget(
      name: "RootTestingNonisolatedTests",
      dependencies: [
        "RootTestingModelsNonisolated",
        "RootTestingSupport",
        visorTesting,
      ],
      packageAccess: false,
    ),
    .testTarget(
      name: "RootTestingMainActorTests",
      dependencies: [
        "RootTestingModelsMainActor",
        "RootTestingSupport",
        visorTesting,
      ],
      packageAccess: false,
      swiftSettings: [.defaultIsolation(MainActor.self)],
    ),
  ],
)
