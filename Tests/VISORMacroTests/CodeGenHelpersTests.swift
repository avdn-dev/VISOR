//
//  CodeGenHelpersTests.swift
//  VISOR
//

import Testing

#if canImport(VISORMacros)
@testable import VISORMacros

@Suite("Code Generation Helpers")
struct CodeGenHelpersTests {

  @Test(arguments: [
    ("sending String", "String"),
    ("borrowing String", "String"),
    ("consuming String", "String"),
    ("inout String", "String"),
    ("isolated any Actor", "any Actor"),
    ("@escaping @Sendable () -> Void", "@Sendable () -> Void"),
  ])
  func `Normalises parameter-only specifiers for storage`(
    input: String,
    expected: String)
  {
    #expect(storageValueType(from: input) == expected)
  }

  @Test
  func `Selects ownership-aware storage snapshot strategies`() {
    #expect(storageSnapshotStrategy(for: "sending String") == .consume)
    #expect(storageSnapshotStrategy(for: "consuming String") == .consume)
    #expect(storageSnapshotStrategy(for: "borrowing String") == .copy)
    #expect(storageSnapshotStrategy(for: "isolated any Actor") == .copy)
    #expect(storageSnapshotStrategy(for: "String") == .none)
  }
}

#endif
