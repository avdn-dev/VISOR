// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "V11CompileProof",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "VISORObservation", targets: ["VISORObservation"]),
    .library(name: "VISOR", targets: ["VISOR"]),
    .library(name: "VISORTestDoubles", targets: ["VISORTestDoubles"]),
    .library(name: "VISORTesting", targets: ["VISORTesting"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      "602.0.0"..<"604.0.0"),
  ],
  targets: [
    .macro(
      name: "V11CompileProofMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]),
    .target(name: "VISORObservation"),
    .target(
      name: "VISOR",
      dependencies: [
        "VISORObservation",
        "V11CompileProofMacros",
      ]),
    .target(name: "VISORTestDoubles"),
    .target(
      name: "VISORTesting",
      dependencies: ["VISOR"]),
    .target(
      name: "ConsumerServices",
      dependencies: ["VISORObservation", "VISORTestDoubles"]),
    .target(
      name: "ConsumerModelsNonisolated",
      dependencies: ["ConsumerServices", "VISOR"]),
    .target(
      name: "ConsumerModelsMainActor",
      dependencies: ["ConsumerServices", "VISOR"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .target(
      name: "StageBSelectorProbe",
      dependencies: [
        "ConsumerModelsNonisolated",
        "VISORTesting",
      ]),
    .testTarget(
      name: "NonisolatedConsumerTests",
      dependencies: [
        "ConsumerModelsNonisolated",
        "ConsumerServices",
        "VISOR",
        "VISORTesting",
      ]),
    .testTarget(
      name: "MainActorConsumerTests",
      dependencies: [
        "ConsumerModelsMainActor",
        "ConsumerServices",
        "VISORTesting",
      ],
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .testTarget(
      name: "V11CompileProofMacroTests",
      dependencies: [
        "V11CompileProofMacros",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]),
    .testTarget(
      name: "VISORObservationRuntimeTests",
      dependencies: ["VISOR", "VISORObservation"]),
    .testTarget(
      name: "VISOROwnerTests",
      dependencies: [
        "ConsumerModelsNonisolated",
        "ConsumerServices",
        "VISOR",
      ]),
  ])
