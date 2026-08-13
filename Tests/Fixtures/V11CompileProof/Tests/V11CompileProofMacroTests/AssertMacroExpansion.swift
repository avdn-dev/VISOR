import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
@_spi(XCTestFailureLocation) import SwiftSyntaxMacrosGenericTestSupport
import Testing

typealias DiagnosticSpec = SwiftSyntaxMacrosGenericTestSupport.DiagnosticSpec
typealias FixItSpec = SwiftSyntaxMacrosGenericTestSupport.FixItSpec

func assertMacroExpansion(
  _ originalSource: String,
  expandedSource expectedExpandedSource: String,
  diagnostics: [DiagnosticSpec] = [],
  macros: [String: Macro.Type],
  applyFixIts: [String]? = nil,
  fixedSource expectedFixedSource: String? = nil,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
  SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
    originalSource,
    expandedSource: expectedExpandedSource,
    diagnostics: diagnostics,
    macroSpecs: macros.mapValues { MacroSpec(type: $0) },
    applyFixIts: applyFixIts,
    fixedSource: expectedFixedSource,
    indentationWidth: .spaces(2),
    failureHandler: { failure in
      Issue.record(
        Comment(rawValue: failure.message),
        sourceLocation: sourceLocation)
    },
    fileID: #fileID,
    filePath: #filePath,
    line: #line,
    column: #column)
}
