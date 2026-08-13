// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "VISOR",
  platforms: [
    .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17), .visionOS(.v2),
  ],
  products: [
    .library(
      name: "VISORObservation",
      targets: ["VISORObservation"]),
    .library(
      name: "VISOR",
      targets: ["VISOR"]),
    .library(
      name: "VISORTesting",
      targets: ["VISORTesting"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"604.0.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
  ],
  targets: [
    .target(name: "VISORObservation"),

    .macro(
      name: "VISORMacros",
      dependencies: [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]),

    .target(
      name: "VISOR",
      dependencies: [
        "VISORObservation",
        "VISORMacros",
      ]),

    .target(
      name: "VISORTesting",
      dependencies: ["VISOR"]),

    .testTarget(
      name: "VISORTests",
      dependencies: ["VISOR", "VISORObservation"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),

    .testTarget(
      name: "VISORObservationTests",
      dependencies: ["VISORObservation"]),

    .testTarget(
      name: "VISORTestingTests",
      dependencies: ["VISOR", "VISORObservation", "VISORTesting"]),

    .testTarget(
      name: "VISORMacroTests",
      dependencies: [
        "VISORMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]),

  ])
