//
//  GenerateStubMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

// MARK: - GenerateStub Macro

/// Attach to a protocol to auto-generate a `Stub<Name>` preview/test stub class.
///
/// Known Swift types (`Bool`, `Int`, `String`, collections, optionals, etc.) receive sensible defaults.
/// Properties with custom types that have no known default use implicitly unwrapped optionals;
/// methods with custom return types use optionals guarded by `fatalError`. Both crash with a
/// descriptive message if accessed before configuration. Use ``DefaultValue(_:)`` to supply
/// explicit property defaults and silence the compiler note.
///
/// ```swift
/// @GenerateStub
/// protocol DataService {
///   var items: [Item] { get }
///   func fetch() async throws -> [Item]
/// }
/// // Generates: StubDataService with canned defaults
/// ```
@attached(peer, names: prefixed(Stub))
public macro GenerateStub() = #externalMacro(
  module: "VISORMacros",
  type: "GenerateStubMacro")
