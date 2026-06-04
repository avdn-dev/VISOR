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
  static let defaultValue = "DefaultValue"
  static let defaultReturn = "DefaultReturn"
  static let observable = "Observable"
}

// MARK: - Property Declaration Helper

/// Generates `var` declarations for each protocol property with appropriate defaults.
/// Unknown custom types use implicitly unwrapped optionals (IUO) as a placeholder.
func generatePropertyDeclarations(_ properties: [ProtocolPropertyInfo], access: String = "") -> [String] {
  let prefix = access.isEmpty ? "" : "\(access) "
  return properties.map { prop in
    if let customDefault = prop.defaultValueExpression {
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
/// Used by generated stubs and spies to initialise generated properties.
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

func returnDefaultValue(for method: ProtocolMethodInfo) -> String? {
  guard let returnType = method.returnType else { return nil }
  return method.defaultReturnExpression ?? defaultValue(for: returnType)
}

// MARK: - Unknown Type Detection

/// Returns `true` when any property or method return type has no known default and would
/// produce an IUO property or an optional return-value variable.
func hasUnknownTypeDefaults(properties: [ProtocolPropertyInfo], methods: [ProtocolMethodInfo]) -> Bool {
  for prop in properties where prop.defaultValueExpression == nil {
    if defaultValue(for: prop.type) == nil { return true }
  }
  for method in methods where method.defaultReturnExpression == nil {
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
        return label.capitalisedFirst
      }
      return param.type.filter(\.isLetter).capitalisedFirst
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
/// Used by generated stubs and spies to avoid duplicated codegen logic.
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
      if let innerDefault = returnDefaultValue(for: method) {
        lines.append("  \(prefix)var \(resultVarName): Result<\(returnType), any Error> = .success(\(innerDefault))")
      } else {
        lines.append("  \(prefix)var \(resultVarName): Result<\(returnType), any Error>?")
      }
    } else {
      lines.append("  \(prefix)var \(resultVarName): Result<Void, any Error> = .success(())")
    }
  } else if let returnType = method.returnType {
    let retVarName = "\(methodPrefix)ReturnValue"
    if let defaultVal = returnDefaultValue(for: method) {
      lines.append("  \(prefix)var \(retVarName): \(returnType) = \(defaultVal)")
    } else {
      lines.append("  \(prefix)var \(retVarName): \(returnType)?")
    }
  }

  return lines
}

// MARK: - Method Fallback Helper

enum MethodFallbackStyle {
  case expression
  case explicitReturn
}

func generateFallbackBodyLines(
  method: ProtocolMethodInfo,
  methodPrefix: String,
  style: MethodFallbackStyle)
  -> [String]
{
  if method.isThrowing {
    if method.returnType != nil {
      let needsGuard = returnDefaultValue(for: method) == nil
      if needsGuard {
        return [
          "    guard let result = \(methodPrefix)Result else { fatalError(\"Configure \\(String(describing: \(methodPrefix)Result)) before calling \(method.name)()\") }",
          "    return try result.get()"
        ]
      }

      switch style {
      case .expression:
        return ["    try \(methodPrefix)Result.get()"]
      case .explicitReturn:
        return ["    return try \(methodPrefix)Result.get()"]
      }
    }

    return ["    try \(methodPrefix)Result.get()"]
  }

  if method.returnType != nil {
    let needsGuard = returnDefaultValue(for: method) == nil
    if needsGuard {
      return [
        "    guard let value = \(methodPrefix)ReturnValue else { fatalError(\"Configure \\(String(describing: \(methodPrefix)ReturnValue)) before calling \(method.name)()\") }",
        "    return value"
      ]
    }

    switch style {
    case .expression:
      return ["    \(methodPrefix)ReturnValue"]
    case .explicitReturn:
      return ["    return \(methodPrefix)ReturnValue"]
    }
  }

  return []
}

// MARK: - Implementation Closure Helpers

/// Builds the closure type string for a method's implementation closure.
///
/// Examples:
/// - `func reset()` → `(() -> Void)?`
/// - `func save(_ item: Item) throws` → `((Item) throws -> Void)?`
/// - `func search(query: String, limit: Int) async throws -> [Result]` → `((String, Int) async throws -> [Result])?`
func implementationClosureType(for method: ProtocolMethodInfo) -> String {
  let paramsStr = method.parameters.map { stripEscaping(from: $0.type) }.joined(separator: ", ")

  var effects = ""
  if method.isAsync { effects += " async" }
  if method.isThrowing { effects += " throws" }

  let returnStr = method.returnType ?? "Void"

  return "((\(paramsStr))\(effects) -> \(returnStr))?"
}

/// Strips the `@escaping` attribute from a function type string.
/// Used when a parameter's type is placed inside a nested function type
/// or enum associated value where `@escaping` is not valid.
func stripEscaping(from typeString: String) -> String {
  typeString
    .split(separator: " ", omittingEmptySubsequences: true)
    .filter { $0 != "@escaping" }
    .joined(separator: " ")
}

/// Strips the `inout` specifier from a type string.
/// Used for enum associated values and storage properties where `inout` is invalid.
func stripInout(from typeString: String) -> String {
  var result = typeString
  if result.hasPrefix("inout ") {
    result = String(result.dropFirst(6))
  }
  return result
}

/// Returns `true` when `typeString` represents a function type (contains `->`).
func isFunctionType(_ typeString: String) -> Bool {
  typeString.contains("->")
}

/// Returns the invocation arguments for an implementation closure — internal
/// parameter names in source order, comma-separated. Inout parameters are
/// prefixed with `&` so they compile when forwarded to the closure.
func implementationInvocationArguments(for method: ProtocolMethodInfo) -> String {
  method.parameters.map { $0.isInout ? "&\($0.internalName)" : $0.internalName }.joined(separator: ", ")
}

/// Returns collision-free implementation-closure storage names.
///
/// The normal API remains `<methodPrefix>Implementation`. If the protocol already
/// has a property or method with that name, use a predictable fallback so the
/// generated spy still conforms without redeclarations.
func implementationStorageNames(
  for methods: [ProtocolMethodInfo],
  methodPrefixes: [String],
  properties: [ProtocolPropertyInfo]
) -> [String] {
  var reservedNames = Set(properties.map(\.name))
  reservedNames.formUnion(methods.map(\.name))

  return methodPrefixes.map { methodPrefix in
    let preferredName = "\(methodPrefix)Implementation"
    guard reservedNames.contains(preferredName) else {
      reservedNames.insert(preferredName)
      return preferredName
    }

    let fallbackBase = "\(preferredName)Closure"
    var candidate = fallbackBase
    var suffix = 2
    while reservedNames.contains(candidate) {
      candidate = "\(fallbackBase)\(suffix)"
      suffix += 1
    }

    reservedNames.insert(candidate)
    return candidate
  }
}

/// Generates the `@ObservationIgnored` implementation-closure storage property
/// for a spy method.
func generateImplementationStorage(
  method: ProtocolMethodInfo,
  implementationName: String,
  access: String
) -> [String] {
  let prefix = access.isEmpty ? "" : "\(access) "
  let closureType = implementationClosureType(for: method)
  return [
    "  @ObservationIgnored",
    "  \(prefix)var \(implementationName): \(closureType)"
  ]
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
  var capitalisedFirst: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
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
    if start == startIndex && end == endIndex { return self }
    return String(self[start..<end])
  }
}
