//
//  ProtocolTypealiasTests.swift
//  VISOR
//
//  Created by Matthew Yuen on 3/4/2026.
//

import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "Spyable": SpyableMacro.self,
  "Stubbable": StubbableMacro.self,
  "StubbableDefault": StubbableDefaultMacro.self,
]

final class ProtocolTypealiasTests: XCTestCase {
  
  func testSpyableSingleTypealias() {
    assertMacroExpansion(
      """
      @Spyable
      protocol FooService {
        typealias Foo = String
        func processFoo(_ foo: Foo) -> Foo
      }
      """,
      expandedSource:
      """
      protocol FooService {
        typealias Foo = String
        func processFoo(_ foo: Foo) -> Foo
      }
      
      @Observable
      final class SpyFooService: FooService {
        // -- processFoo --
        var processFooCallCount = 0
        var processFooReceivedFoo: FooService.Foo?
        var processFooReceivedInvocations: [FooService.Foo] = []
        var processFooReturnValue: FooService.Foo?
        func processFoo(_ foo: FooService.Foo) -> FooService.Foo {
          processFooCallCount += 1
          processFooReceivedFoo = foo
          processFooReceivedInvocations.append(foo)
          calls.append(.processFoo(foo: foo))
          guard let value = processFooReturnValue else {
              fatalError("Configure \\(processFooReturnValue) before calling processFoo()")
          }
          return value
        }
        enum Call {
          case processFoo(foo: FooService.Foo)
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        .init(
          message:
            """
            @Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. \
            Use @StubbableDefault to provide explicit defaults.
            """,
          line: 1,
          column: 1,
          severity: .note)
      ],
      macros: testMacros)
  }
  
}

#endif // canImport(VISORMacros)
