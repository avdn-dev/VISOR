//
//  StubbableMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

// MARK: - Stubbable Macro

/// Attach to a protocol to auto-generate a `Stub<Name>` preview/test stub class.
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
