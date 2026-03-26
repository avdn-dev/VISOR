//
//  SpyableMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

// MARK: - Spyable Macro

/// Attach to a protocol to auto-generate a `Spy<Name>` test double with call recording.
///
/// Known Swift types receive sensible defaults. Custom property types use implicitly unwrapped
/// optionals; custom method return types use optionals guarded by `fatalError`. Both crash with
/// a descriptive message if accessed before configuration. Use ``StubbableDefault(_:)`` for
/// explicit defaults.
///
/// ```swift
/// @Spyable
/// protocol DataService {
///   func fetch() async throws -> [Item]
///   func save(_ item: Item) async throws
/// }
/// // Generates: SpyDataService with callCount, receivedArgs, Call enum
/// ```
@attached(peer, names: prefixed(Spy))
public macro Spyable() = #externalMacro(
  module: "VISORMacros",
  type: "SpyableMacro")
