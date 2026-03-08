//
//  CodeGenHelpers.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import Foundation
import SwiftSyntax

// MARK: - Attribute Name Constants

enum AttributeName {
  static let bound = "Bound"
  static let reaction = "Reaction"
  static let stubbableDefault = "StubbableDefault"
  static let observable = "Observable"
}

// MARK: - Property Declaration Helper

func generatePropertyDeclarations(_ properties: [ProtocolPropertyInfo], access: String = "") -> [String] {
  let prefix = access.isEmpty ? "" : "\(access) "
  return properties.map { prop in
    if let customDefault = prop.stubbableDefault {
      return "  \(prefix)var \(prop.name): \(prop.type) = \(customDefault)"
    } else {
      let defaultVal = defaultValue(for: prop.type) ?? "nil"
      let typeStr = defaultVal == "nil" && !prop.type.hasSuffix("?") && !prop.type.hasPrefix("Optional<")
        ? "\(prop.type)!"
        : prop.type
      return "  \(prefix)var \(prop.name): \(typeStr) = \(defaultVal)"
    }
  }
}

// MARK: - Default Value Helper

func defaultValue(for type: String) -> String? {
  let trimmed = type.trimmingCharacters(in: .whitespaces)

  // Optional
  if trimmed.hasSuffix("?") { return "nil" }
  if trimmed.hasPrefix("Optional<") { return "nil" }

  // Bool
  if trimmed == "Bool" { return "false" }

  // Numeric
  let intTypes: Set<String> = ["Int", "Int8", "Int16", "Int32", "Int64",
                                "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
  if intTypes.contains(trimmed) { return "0" }
  if trimmed == "Float" { return "0.0" }
  if trimmed == "Double" { return "0.0" }
  if trimmed == "CGFloat" { return "0.0" }
  if trimmed == "Decimal" { return "0" }

  // String
  if trimmed == "String" { return "\"\"" }

  // Data
  if trimmed == "Data" { return "Data()" }

  // Array
  if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.contains(":") { return "[]" }
  if trimmed.hasPrefix("Array<") { return "[]" }

  // Dictionary
  if trimmed.hasPrefix("[") && trimmed.contains(":") && trimmed.hasSuffix("]") { return "[:]" }
  if trimmed.hasPrefix("Dictionary<") { return "[:]" }

  // Set
  if trimmed.hasPrefix("Set<") { return "[]" }

  // Void
  if trimmed == "Void" || trimmed == "()" { return "()" }

  // AsyncStream
  if trimmed.hasPrefix("AsyncStream<") { return "AsyncStream { $0.finish() }" }

  return nil
}

// MARK: - Method Signature Helper

func buildMethodSignature(_ method: ProtocolMethodInfo, access: String = "") -> String {
  let params = method.parameters.map { param in
    if let label = param.externalLabel {
      if label == param.internalName {
        return "\(label): \(param.type)"
      }
      return "\(label) \(param.internalName): \(param.type)"
    }
    return "_ \(param.internalName): \(param.type)"
  }.joined(separator: ", ")

  let prefix = access.isEmpty ? "" : "\(access) "
  var sig = "\(prefix)func \(method.name)(\(params))"
  if method.isAsync { sig += " async" }
  if method.isThrowing { sig += " throws" }
  if let ret = method.returnType { sig += " -> \(ret)" }
  return sig
}

// MARK: - Protocol Extension Helper

func makeProtocolExtension(
  for type: some TypeSyntaxProtocol,
  conformingTo protocolName: String)
  -> ExtensionDeclSyntax
{
  let extensionDecl: DeclSyntax = """
    extension \(type.trimmed): @MainActor \(raw: protocolName) {}
    """
  return extensionDecl.cast(ExtensionDeclSyntax.self)
}

// MARK: - String Extension

extension String {
  var capitalizedFirst: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }

  var lowercasedFirst: String {
    guard let first else { return self }
    return first.lowercased() + dropFirst()
  }
}
