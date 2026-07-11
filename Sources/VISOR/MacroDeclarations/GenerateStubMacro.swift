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
/// descriptive message if accessed before configuration. Use ``DefaultValue(_:)`` for properties
/// or ``DefaultReturn(_:)`` for method returns to silence the compiler note.
///
/// ```swift
/// @GenerateStub
/// protocol DataService {
///   var items: [Item] { get }
///   func fetch() async throws -> [Item]
/// }
/// // Generates: StubDataService with canned defaults
/// ```
///
/// Pass ``TestDoubleTrait/sendable`` to generate a nonisolated, synchronised stub with checked
/// `Sendable` conformance. All generated stored values must be `Sendable`. Generic methods remain
/// supported when generation does not need to store a value containing their generic parameters.
@attached(peer, names: prefixed(Stub))
public macro GenerateStub(_ traits: TestDoubleTrait...) = #externalMacro(
  module: "VISORMacros",
  type: "GenerateStubMacro")
