//
//  assertMacroExpansionSwiftTesting.swift
//  VISOR
//
//  Created by Matthew Yuen on 3/4/2026.
//

#if compiler(<6.4)
import Testing
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
@_spi(XCTestFailureLocation) import SwiftSyntaxMacrosGenericTestSupport

// Re-export the spec types from `SwiftSyntaxMacrosGenericTestSupport`.
public typealias NoteSpec = SwiftSyntaxMacrosGenericTestSupport.NoteSpec
public typealias FixItSpec = SwiftSyntaxMacrosGenericTestSupport.FixItSpec
public typealias DiagnosticSpec = SwiftSyntaxMacrosGenericTestSupport.DiagnosticSpec

/// Assert that expanding the given macros in the original source produces
/// the given expanded source code.
///
/// - Parameters:
///   - originalSource: The original source code, which is expected to contain
///     macros in various places (e.g., `#stringify(x + y)`).
///   - expectedExpandedSource: The source code that we expect to see after
///     performing macro expansion on the original source.
///   - diagnostics: The diagnostics when expanding any macro
///   - macros: The macros that should be expanded, provided as a dictionary
///     mapping macro names (e.g., `"stringify"`) to implementation types
///     (e.g., `StringifyMacro.self`).
///   - testModuleName: The name of the test module to use.
///   - testFileName: The name of the test file name to use.
///   - indentationWidth: The indentation width used in the expansion.
///
/// - SeeAlso: ``assertMacroExpansionSwiftTesting(_:expandedSource:diagnostics:macroSpecs:applyFixIts:fixedSource:testModuleName:testFileName:indentationWidth:file:line:)``
///   to also specify the list of conformances passed to the macro expansion.
public func assertMacroExpansionSwiftTesting(
  _ originalSource: String,
  expandedSource expectedExpandedSource: String,
  diagnostics: [DiagnosticSpec] = [],
  macros: [String: Macro.Type],
  applyFixIts: [String]? = nil,
  fixedSource expectedFixedSource: String? = nil,
  testModuleName: String = "TestModule",
  testFileName: String = "test.swift",
  indentationWidth: Trivia = .spaces(4),
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  let specs = macros.mapValues { MacroSpec(type: $0) }
  VISORMacroTests.assertMacroExpansionSwiftTesting(
    originalSource,
    expandedSource: expectedExpandedSource,
    diagnostics: diagnostics,
    macroSpecs: specs,
    applyFixIts: applyFixIts,
    fixedSource: expectedFixedSource,
    testModuleName: testModuleName,
    testFileName: testFileName,
    indentationWidth: indentationWidth,
    sourceLocation: sourceLocation,
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

/// Assert that expanding the given macros in the original source produces
/// the given expanded source code.
///
/// - Parameters:
///   - originalSource: The original source code, which is expected to contain
///     macros in various places (e.g., `#stringify(x + y)`).
///   - expectedExpandedSource: The source code that we expect to see after
///     performing macro expansion on the original source.
///   - diagnostics: The diagnostics when expanding any macro
///   - macroSpecs: The macros that should be expanded, provided as a dictionary
///     mapping macro names (e.g., `"CodableMacro"`) to specification with macro type
///     (e.g., `CodableMacro.self`) and a list of conformances macro provides
///     (e.g., `["Decodable", "Encodable"]`).
///   - applyFixIts: If specified, filters the Fix-Its that are applied to generate `fixedSource` to only those whose message occurs in this array. If `nil`, all Fix-Its from the diagnostics are applied.
///   - fixedSource: If specified, asserts that the source code after applying Fix-Its matches this string.
///   - testModuleName: The name of the test module to use.
///   - testFileName: The name of the test file name to use.
///   - indentationWidth: The indentation width used in the expansion.
public func assertMacroExpansionSwiftTesting(
  _ originalSource: String,
  expandedSource expectedExpandedSource: String,
  diagnostics: [DiagnosticSpec] = [],
  macroSpecs: [String: MacroSpec],
  applyFixIts: [String]? = nil,
  fixedSource expectedFixedSource: String? = nil,
  testModuleName: String = "TestModule",
  testFileName: String = "test.swift",
  indentationWidth: Trivia = .spaces(4),
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
    originalSource,
    expandedSource: expectedExpandedSource,
    diagnostics: diagnostics,
    macroSpecs: macroSpecs,
    applyFixIts: applyFixIts,
    fixedSource: expectedFixedSource,
    testModuleName: testModuleName,
    testFileName: testFileName,
    indentationWidth: indentationWidth,
    failureHandler: {
      Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation)
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

#endif // compiler(<6.4)
