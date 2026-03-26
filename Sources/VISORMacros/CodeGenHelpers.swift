//
//  CodeGenHelpers.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import SwiftSyntax

// MARK: - Attribute Name Constants

enum AttributeName {
  static let bound = "Bound"
  static let polled = "Polled"
  static let reaction = "Reaction"
  static let stubbableDefault = "StubbableDefault"
  static let observable = "Observable"
}

// MARK: - Property Declaration Helper

/// Generates `var` declarations for each protocol property with appropriate defaults.
/// Unknown custom types use implicitly unwrapped optionals (IUO) as a placeholder.
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

/// Returns a sensible default literal for known Swift types, or `nil` for custom types.
/// Used by `@Stubbable` and `@Spyable` to initialise generated stub/spy properties.
func defaultValue(for type: String) -> String? {
  let trimmed = type.trimmingWhitespace

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

// MARK: - Unknown Type Detection

/// Returns `true` when any property or method return type has no known default and would
/// produce an IUO property or an optional return-value variable.
func hasUnknownTypeDefaults(properties: [ProtocolPropertyInfo], methods: [ProtocolMethodInfo]) -> Bool {
  for prop in properties where prop.stubbableDefault == nil {
    if defaultValue(for: prop.type) == nil { return true }
  }
  for method in methods {
    if let rt = method.returnType, defaultValue(for: rt) == nil { return true }
  }
  return false
}

// MARK: - Method Name Disambiguation

/// Computes unique property-name prefixes for each method in the list.
/// Methods with unique base names keep their original name as prefix.
/// Methods that share a base name are disambiguated by appending camelCased parameter labels.
///
/// Example: `func load(byId:)` and `func load(matching:)` produce `loadById` and `loadMatching`.
/// For unlabeled parameters (`_`), the parameter type name is used (stripped of punctuation)
/// so generated names depend only on the public API surface.
///
/// If labels alone still collide (same name and labels, different return types),
/// the return type is appended: `loadIdReturningItem` vs `loadIdReturningItems`.
func uniqueMethodPrefixes(for methods: [ProtocolMethodInfo]) -> [String] {
  var nameCounts: [String: Int] = [:]
  for m in methods { nameCounts[m.name, default: 0] += 1 }

  // Phase 1: disambiguate by parameter labels
  var prefixes = methods.map { method -> String in
    guard nameCounts[method.name, default: 0] > 1 else { return method.name }
    let suffix = method.parameters.map { param in
      if let label = param.externalLabel {
        return label.capitalizedFirst
      }
      return param.type.filter(\.isLetter).capitalizedFirst
    }.joined()
    return suffix.isEmpty ? method.name : "\(method.name)\(suffix)"
  }

  // Phase 2: if prefixes still collide, append return type
  var prefixCounts: [String: Int] = [:]
  for p in prefixes { prefixCounts[p, default: 0] += 1 }

  for (i, prefix) in prefixes.enumerated() where prefixCounts[prefix, default: 0] > 1 {
    let retSuffix = methods[i].returnType?.filter(\.isLetter) ?? "Void"
    prefixes[i] = "\(prefix)Returning\(retSuffix)"
  }

  return prefixes
}

// MARK: - Return Storage Helper

/// Generates `var` declarations for a method's return value or `Result` storage.
///
/// - Throwing methods get a `Result<ReturnType, any Error>` variable.
/// - Non-throwing methods with a return type get a `ReturnValue` variable.
/// - Void non-throwing methods produce no declarations.
///
/// Used by both `@Stubbable` and `@Spyable` to avoid duplicated codegen logic.
func generateReturnStorage(
  method: ProtocolMethodInfo,
  methodPrefix: String,
  access: String
) -> [String] {
  let prefix = access.isEmpty ? "" : "\(access) "
  var lines: [String] = []

  if method.isThrowing {
    let resultVarName = "\(methodPrefix)Result"
    if let returnType = method.returnType {
      if let innerDefault = defaultValue(for: returnType) {
        lines.append("  \(prefix)var \(resultVarName): Result<\(returnType), any Error> = .success(\(innerDefault))")
      } else {
        lines.append("  \(prefix)var \(resultVarName): Result<\(returnType), any Error>?")
      }
    } else {
      lines.append("  \(prefix)var \(resultVarName): Result<Void, any Error> = .success(())")
    }
  } else if let returnType = method.returnType {
    let retVarName = "\(methodPrefix)ReturnValue"
    if let defaultVal = defaultValue(for: returnType) {
      lines.append("  \(prefix)var \(retVarName): \(returnType) = \(defaultVal)")
    } else {
      lines.append("  \(prefix)var \(retVarName): \(returnType)?")
    }
  }

  return lines
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
  let asyncSuffix = method.isAsync ? " async" : ""
  let throwsSuffix = method.isThrowing ? " throws" : ""
  let returnSuffix = method.returnType.map { " -> \($0)" } ?? ""
  return "\(prefix)func \(method.name)(\(params))\(asyncSuffix)\(throwsSuffix)\(returnSuffix)"
}

// MARK: - Access Level Helper

/// Returns the access-level keyword for any declaration group (class, struct, enum, etc.)
/// or empty string for `internal` (Swift's default, omitted to reduce noise).
func accessLevel(of declaration: some DeclGroupSyntax) -> String {
  for modifier in declaration.modifiers {
    switch modifier.name.text {
    case "open", "public", "package", "fileprivate", "private":
      return modifier.name.text
    default:
      continue
    }
  }
  return ""
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
    guard !isEmpty else { return self }
    var result = self
    result.replaceSubrange(startIndex...startIndex, with: self[startIndex].uppercased())
    return result
  }

  var lowercasedFirst: String {
    guard !isEmpty else { return self }
    var result = self
    result.replaceSubrange(startIndex...startIndex, with: self[startIndex].lowercased())
    return result
  }

  var trimmingWhitespace: String {
    let start = firstIndex(where: { !$0.isWhitespace }) ?? startIndex
    let end = lastIndex(where: { !$0.isWhitespace }).map(index(after:)) ?? endIndex
    return String(self[start..<end])
  }
}
