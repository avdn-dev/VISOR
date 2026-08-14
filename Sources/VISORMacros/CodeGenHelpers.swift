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
  static let reaction = "Reaction"
  static let defaultValue = "DefaultValue"
  static let defaultReturn = "DefaultReturn"
  static let observable = "Observable"
}

// MARK: - Default Value Helper

/// Returns a sensible default literal for known Swift types, or `nil` for custom types.
/// Used by generated stubs and spies to initialise generated properties.
func defaultValue(for type: String) -> String? {
  let trimmed = storageValueType(from: type)

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

func methodReferencesGenericParameters(_ method: ProtocolMethodInfo, in type: String?) -> Bool {
  !genericParameterNamesReferenced(by: method, in: type).isEmpty
}

func genericParameterNamesReferenced(
  by method: ProtocolMethodInfo,
  in type: String?)
  -> [String]
{
  guard let type, !method.genericParameterNames.isEmpty else { return [] }
  return method.genericParameterNames.filter { genericName in
    type.containsTypeIdentifier(genericName)
  }
}

func methodSignatureReferencesGenericParameters(_ method: ProtocolMethodInfo) -> Bool {
  if methodReferencesGenericParameters(method, in: method.returnType) { return true }
  if methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType) { return true }
  return method.parameters.contains { methodReferencesGenericParameters(method, in: $0.type) }
}

// MARK: - Unknown Type Detection

/// Returns `true` when any property or method return type has no known default and would
/// produce an IUO property or an optional return-value variable.
func hasUnknownTypeDefaults(properties: [ProtocolPropertyInfo], methods: [ProtocolMethodInfo]) -> Bool {
  for prop in properties where prop.defaultValueExpression == nil {
    if defaultValue(for: prop.type) == nil { return true }
  }
  for method in methods where method.defaultReturnExpression == nil {
    if method.canForwardRethrowingBodyResult { continue }
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

  // Phase 2: if prefixes still collide, append return type.
  var prefixCounts: [String: Int] = [:]
  for p in prefixes { prefixCounts[p, default: 0] += 1 }

  for (i, prefix) in prefixes.enumerated() where prefixCounts[prefix, default: 0] > 1 {
    let retSuffix = methods[i].returnType?.filter(\.isLetter) ?? "Void"
    prefixes[i] = "\(prefix)Returning\(retSuffix)"
  }

  // Phase 3: overloads can share labels and return types while differing by
  // parameter type. Include every parameter type before using an ordinal.
  prefixCounts = [:]
  for p in prefixes { prefixCounts[p, default: 0] += 1 }
  for (i, prefix) in prefixes.enumerated() where prefixCounts[prefix, default: 0] > 1 {
    let parameterSuffix = methods[i].parameters
      .map { $0.type.filter(\.isLetter).capitalisedFirst }
      .joined()
    prefixes[i] = "\(prefix)With\(parameterSuffix.isEmpty ? "NoArguments" : parameterSuffix)"
  }

  // Type spellings can still collapse after punctuation is removed (for
  // example `Int` and `[Int]`). A source-order ordinal is deterministic and
  // guarantees a unique final generated API.
  prefixCounts = [:]
  for p in prefixes { prefixCounts[p, default: 0] += 1 }
  var prefixOrdinals: [String: Int] = [:]
  for index in prefixes.indices where prefixCounts[prefixes[index], default: 0] > 1 {
    let prefix = prefixes[index]
    prefixOrdinals[prefix, default: 0] += 1
    prefixes[index] = "\(prefix)Overload\(prefixOrdinals[prefix, default: 0])"
  }

  return prefixes
}

// MARK: - Method Fallback Helper

enum MethodFallbackStyle {
  case expression
  case explicitReturn
}

func generateFallbackBodyLines(
  method: ProtocolMethodInfo,
  returnStorageName: String?,
  style: MethodFallbackStyle)
  -> [String]
{
  if method.isRethrowing {
    if let forwardingCall = method.rethrowingBodyForwardingCall {
      if method.returnType != nil {
        return ["    return \(forwardingCall)"]
      }
      return ["    \(forwardingCall)"]
    }

    if method.returnType != nil {
      return ["    fatalError(\"No generated default for \(method.name)(); provide a manual implementation for this method\")"]
    }

    return []
  }

  if methodReferencesGenericParameters(method, in: method.returnType)
    || methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType)
  {
    return ["    fatalError(\"No generated default for \(method.name)(); provide a manual implementation for this method\")"]
  }

  if method.isThrowing {
    guard let returnStorageName else {
      return ["    fatalError(\"No generated default for \(method.name)(); provide a manual implementation for this method\")"]
    }
    if method.returnType != nil {
      let needsGuard = returnDefaultValue(for: method) == nil
      if needsGuard {
        return [
          "    guard let result = \(returnStorageName) else { fatalError(\"Configure \(returnStorageName) before calling \(method.name)()\") }",
          "    return try result.get()"
        ]
      }

      switch style {
      case .expression:
        return ["    try \(returnStorageName).get()"]
      case .explicitReturn:
        return ["    return try \(returnStorageName).get()"]
      }
    }

    return ["    try \(returnStorageName).get()"]
  }

  if method.returnType != nil {
    guard let returnStorageName else {
      return ["    fatalError(\"No generated default for \(method.name)(); provide a manual implementation for this method\")"]
    }
    let needsGuard = returnDefaultValue(for: method) == nil
    if needsGuard {
      return [
        "    guard let value = \(returnStorageName) else { fatalError(\"Configure \(returnStorageName) before calling \(method.name)()\") }",
        "    return value"
      ]
    }

    switch style {
    case .expression:
      return ["    \(returnStorageName)"]
    case .explicitReturn:
      return ["    return \(returnStorageName)"]
    }
  }

  return []
}

// MARK: - Implementation Closure Helpers

func supportsImplementationClosure(for method: ProtocolMethodInfo) -> Bool {
  !method.isRethrowing && !methodSignatureReferencesGenericParameters(method)
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

/// Returns a type spelling that can be used for stored values.
///
/// Parameter ownership and isolation specifiers are valid on function parameters or results,
/// but not on stored properties or enum associated values. Function-type attributes such as
/// `@Sendable` remain part of the stored type.
func storageValueType(from typeString: String) -> String {
  var result = stripEscaping(from: typeString).trimmingWhitespace
  let leadingSpecifiers = ["inout", "sending", "borrowing", "consuming", "isolated"]

  var removedSpecifier = true
  while removedSpecifier {
    removedSpecifier = false
    for specifier in leadingSpecifiers where result.hasPrefix("\(specifier) ") {
      result = String(result.dropFirst(specifier.count + 1)).trimmingWhitespace
      removedSpecifier = true
      break
    }
  }

  return result
}

enum StorageSnapshotStrategy: Equatable, Sendable {
  case none
  case copy
  case consume
}

func storageSnapshotStrategy(for typeString: String) -> StorageSnapshotStrategy {
  let trimmed = typeString.trimmingWhitespace
  if ["sending", "consuming"].contains(where: { trimmed.hasPrefix("\($0) ") }) {
    return .consume
  }
  if ["borrowing", "isolated"].contains(where: { trimmed.hasPrefix("\($0) ") }) {
    return .copy
  }
  return .none
}

/// Returns `true` when `typeString` represents a function type (contains `->`).
func isFunctionType(_ typeString: String) -> Bool {
  typeString.contains("->")
}

func isEscapingFunctionType(_ typeString: String) -> Bool {
  isFunctionType(typeString) && typeString.contains("@escaping")
}

func isNonEscapingFunctionType(_ typeString: String) -> Bool {
  isFunctionType(typeString) && !isEscapingFunctionType(typeString)
}

/// Returns the type spelling to use for a generated initialiser parameter.
/// Stored closure dependencies need `@escaping` because the generated body
/// assigns the parameter into `self`.
func initParameterType(for type: TypeSyntax) -> String {
  let typeString = type.trimmedDescription
  guard type.isTopLevelFunctionType else { return typeString }
  return typeString.addingEscapingToTopLevelFunctionType()
}

func spyStorageType(for param: ParameterInfo, method: ProtocolMethodInfo) -> String? {
  let strippedType = stripEscaping(from: stripInout(from: param.type))
  guard !isNonEscapingFunctionType(param.type) else { return nil }
  return methodReferencesGenericParameters(method, in: strippedType) ? "Any" : strippedType
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
  let throwsSuffix = method.throwsEffect.keyword.map { " \($0)" } ?? ""
  let returnSuffix = method.returnType.map { " -> \($0)" } ?? ""
  let whereSuffix = method.genericWhereClause.map { " \($0)" } ?? ""
  return "\(prefix)func \(method.name)\(method.genericParameterClause)(\(params))\(asyncSuffix)\(throwsSuffix)\(returnSuffix)\(whereSuffix)"
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

  func containsTypeIdentifier(_ identifier: String) -> Bool {
    var current = startIndex
    while current < endIndex {
      guard self[current...].hasPrefix(identifier) else {
        formIndex(after: &current)
        continue
      }

      let range = current..<index(current, offsetBy: identifier.count)
      let before = range.lowerBound == startIndex ? nil : self[index(before: range.lowerBound)]
      let after = range.upperBound == endIndex ? nil : self[range.upperBound]
      let hasIdentifierBoundaryBefore = before.map { !$0.isIdentifierCharacter } ?? true
      let hasIdentifierBoundaryAfter = after.map { !$0.isIdentifierCharacter } ?? true
      if hasIdentifierBoundaryBefore && hasIdentifierBoundaryAfter {
        return true
      }

      formIndex(after: &current)
    }

    return false
  }

  func firstRange(of needle: String) -> Range<String.Index>? {
    var current = startIndex
    while current < endIndex {
      if self[current...].hasPrefix(needle) {
        return current..<index(current, offsetBy: needle.count)
      }
      formIndex(after: &current)
    }
    return nil
  }

  func addingEscapingToTopLevelFunctionType() -> String {
    contains("@escaping") ? self : "@escaping \(self)"
  }
}

private extension Character {
  var isIdentifierCharacter: Bool {
    isLetter || isNumber || self == "_"
  }
}

private extension TypeSyntax {
  var isTopLevelFunctionType: Bool {
    if self.is(FunctionTypeSyntax.self) { return true }

    if let attributedType = self.as(AttributedTypeSyntax.self) {
      return attributedType.baseType.isTopLevelFunctionType
    }

    if let tupleType = self.as(TupleTypeSyntax.self),
       tupleType.elements.count == 1,
       let element = tupleType.elements.first
    {
      return element.type.isTopLevelFunctionType
    }

    return false
  }
}

private extension ProtocolMethodInfo {
  var rethrowingBodyForwardingCall: String? {
    guard isRethrowing else { return nil }

    for parameter in parameters {
      let type = stripInvocationOnlyFunctionAttributes(from: parameter.type)
      guard isZeroArgumentFunction(type),
            canForwardFunctionReturnType(functionReturnType(in: type), for: returnType)
      else {
        continue
      }

      let tryPrefix = type.contains("throws") ? "try " : ""
      let awaitPrefix = type.contains("async") ? "await " : ""
      return "\(tryPrefix)\(awaitPrefix)\(parameter.internalName)()"
    }

    return nil
  }

  var canForwardRethrowingBodyResult: Bool {
    rethrowingBodyForwardingCall != nil
  }
}

private func stripInvocationOnlyFunctionAttributes(from type: String) -> String {
  type
    .split(separator: " ", omittingEmptySubsequences: true)
    .filter { $0 != "@escaping" && $0 != "@Sendable" }
    .joined(separator: " ")
}

private func isZeroArgumentFunction(_ type: String) -> Bool {
  guard let arrowRange = type.firstRange(of: "->") else { return false }
  let leftSide = String(type[..<arrowRange.lowerBound]).trimmingWhitespace
  return leftSide.hasPrefix("()")
}

private func functionReturnType(in type: String) -> String? {
  guard let arrowRange = type.firstRange(of: "->") else { return nil }
  return String(type[arrowRange.upperBound...]).trimmingWhitespace
}

private func canForwardFunctionReturnType(_ functionReturnType: String?, for methodReturnType: String?) -> Bool {
  guard let functionReturnType else { return false }

  if let methodReturnType {
    return functionReturnType == methodReturnType
  }

  return functionReturnType == "Void" || functionReturnType == "()"
}
