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

  @Test(arguments: [
    ("Swift.Optional<String>", "nil"),
    ("Swift.Bool", "false"),
    ("Swift.Int64", "0"),
    ("Swift.Double", "0.0"),
    ("CoreGraphics.CGFloat", "0.0"),
    ("Foundation.Decimal", "0"),
    ("Swift.String", "\"\""),
    ("Foundation.Data", "Data()"),
    ("Swift.Array<String>", "[]"),
    ("Swift.Dictionary<String, Int>", "[:]"),
    ("Swift.Set<String>", "[]"),
    ("Swift.Void", "()"),
    ("_Concurrency.AsyncStream<Int>", "AsyncStream { $0.finish() }"),
  ])
  func `Recognises canonical qualified spellings for known defaults`(
    input: String,
    expected: String)
  {
    #expect(defaultValue(for: input) == expected)
  }

  @Test(arguments: [
    "Feature.Bool",
    "Feature.Array<Int>",
    "Feature.Optional<Int>",
    "Flag",
  ])
  func `Does not infer defaults for arbitrary modules or aliases`(
    input: String)
  {
    #expect(defaultValue(for: input) == nil)
  }

  @Test
  func `Disambiguates same-label overloads by parameter type`() {
    let prefixes = uniqueMethodPrefixes(for: [
      testMethod(name: "send", parameterType: "String", returnType: nil),
      testMethod(name: "send", parameterType: "Int", returnType: nil),
    ])

    #expect(prefixes == [
      "sendValueReturningVoidWithString",
      "sendValueReturningVoidWithInt",
    ])
  }

  @Test
  func `Uses deterministic ordinals when sanitised types still collide`() {
    let prefixes = uniqueMethodPrefixes(for: [
      testMethod(name: "consume", parameterType: "Int", returnType: nil, externalLabel: nil),
      testMethod(name: "consume", parameterType: "[Int]", returnType: nil, externalLabel: nil),
    ])

    #expect(prefixes == [
      "consumeIntReturningVoidWithIntOverload1",
      "consumeIntReturningVoidWithIntOverload2",
    ])
  }
}

private func testMethod(
  name: String,
  parameterType: String,
  returnType: String?,
  externalLabel: String? = "value")
  -> ProtocolMethodInfo
{
  ProtocolMethodInfo(
    name: name,
    genericParameterClause: "",
    genericWhereClause: nil,
    genericParameterNames: [],
    explicitlySendableGenericParameterNames: [],
    parameters: [ParameterInfo(
      externalLabel: externalLabel,
      internalName: "value",
      type: parameterType,
      isInout: false)],
    isAsync: false,
    isConcurrent: false,
    throwsEffect: .none,
    returnType: returnType,
    defaultReturnExpression: nil)
}

#endif
