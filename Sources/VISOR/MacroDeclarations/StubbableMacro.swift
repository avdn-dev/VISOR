//
//  StubbableMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

// MARK: - Stubbable Macro

/// Attach to a protocol to auto-generate a `Stub<Name>` preview/test stub class.
///
/// Known Swift types (`Bool`, `Int`, `String`, collections, optionals, etc.) receive sensible defaults.
/// Properties with custom types that have no known default use implicitly unwrapped optionals;
/// methods with custom return types use optionals guarded by `fatalError`. Both crash with a
/// descriptive message if accessed before configuration. Use ``StubbableDefault(_:)`` to supply
/// explicit defaults and silence the compiler note.
///
/// ```swift
/// @Stubbable
/// protocol DataService {
///   var items: [Item] { get }
///   func fetch() async throws -> [Item]
/// }
/// // Generates: StubDataService with canned defaults
/// ```
@attached(peer, names: prefixed(Stub))
public macro Stubbable() = #externalMacro(
  module: "VISORMacros",
  type: "StubbableMacro")
