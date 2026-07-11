//
//  GenerateSpyMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

// MARK: - GenerateSpy Macro

/// Attach to a protocol to auto-generate a `Spy<Name>` test double with call recording.
///
/// Known Swift types receive sensible defaults. Custom property types use implicitly unwrapped
/// optionals; custom method return types use optionals guarded by `fatalError`. Both crash with
/// a descriptive message if accessed before configuration. Use ``DefaultValue(_:)`` for properties
/// or ``DefaultReturn(_:)`` for method returns.
///
/// ```swift
/// @GenerateSpy
/// protocol DataService {
///   func fetch() async throws -> [Item]
///   func save(_ item: Item) async throws
/// }
/// // Generates: SpyDataService with callCount, receivedArgs, Call enum
/// ```
///
/// Pass ``TestDoubleTrait/sendable`` to generate a nonisolated, synchronised spy with checked
/// `Sendable` conformance. All stored property, argument, return, error, and implementation closure
/// values must be `Sendable`. Generic arguments explicitly constrained to `Sendable` are recorded
/// as `any Sendable`; unconstrained generic values that require storage are rejected.
@attached(peer, names: prefixed(Spy))
public macro GenerateSpy(_ traits: TestDoubleTrait...) = #externalMacro(
  module: "VISORMacros",
  type: "GenerateSpyMacro")
