//
//  TestDoubleTrait.swift
//  VISOR
//

/// Options that specialise generated stub and spy behaviour.
nonisolated public enum TestDoubleTrait: Sendable {
  /// Generates a nonisolated, synchronised test double with checked `Sendable` conformance.
  ///
  /// The generated storage requires every stored value to conform to `Sendable`, and spy
  /// implementation closures are generated as `@Sendable`.
  case sendable
}
