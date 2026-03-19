// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "VISOR",
  platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17), .visionOS(.v2)],
  products: [
    .library(
      name: "VISOR",
      targets: ["VISOR"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
  ],
  targets: [
    .macro(
      name: "VISORMacros",
      dependencies: [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]),

    .target(
      name: "VISOR",
      dependencies: ["VISORMacros"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),

    .testTarget(
      name: "VISORTests",
      dependencies: ["VISOR"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),

    .testTarget(
      name: "VISORMacroTests",
      dependencies: [
        "VISORMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]),
  ])
