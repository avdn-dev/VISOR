import SwiftDiagnostics
import SwiftSyntax

struct UnsupportedStateFieldDiagnostic: DiagnosticMessage {
  enum Kind: String {
    case accessorObservers
    case attribute
    case ignoredIsolationModifier
    case isolationModifier
    case multipleBindings
    case nonIdentifierPattern
    case reservedName
    case storageModifier
    case writableComputed
  }

  let kind: Kind
  let detail: String?
  let fieldName: String?

  var message: String {
    switch kind {
    case .accessorObservers:
      "VISOR State field '\(fieldName ?? "<unknown>")' cannot declare willSet or didSet"
    case .attribute:
      "@\(detail ?? "<unknown>") is unsupported on VISOR State field '\(fieldName ?? "<unknown>")'"
    case .ignoredIsolationModifier:
      "VISOR State field '\(fieldName ?? "<unknown>")' cannot combine " +
        "@ObservationIgnored with \(detail ?? "nonisolated")"
    case .isolationModifier:
      "VISOR State field '\(fieldName ?? "<unknown>")' cannot be declared " +
        (detail ?? "nonisolated")
    case .multipleBindings:
      "declare each VISOR State field in a separate var declaration"
    case .nonIdentifierPattern:
      "VISOR State fields require a single identifier pattern"
    case .reservedName:
      "'\(fieldName ?? "<unknown>")' uses VISOR's reserved _visor prefix"
    case .storageModifier:
      "'\(detail ?? "<unknown>")' is unsupported on VISOR State field '\(fieldName ?? "<unknown>")'"
    case .writableComputed:
      "writable computed VISOR State field '\(fieldName ?? "<unknown>")' is unsupported"
    }
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: kind.rawValue)
  }

  var severity: DiagnosticSeverity { .error }
}

enum StateFieldFixIt: String, FixItMessage {
  case restrictStateSetter

  var message: String {
    switch self {
    case .restrictStateSetter:
      "restrict the State field setter"
    }
  }

  var fixItID: MessageID {
    MessageID(domain: "VISOR", id: rawValue)
  }
}

extension AttributeListSyntax {
  func visorAttribute(named name: String) -> AttributeSyntax? {
    compactMap { $0.as(AttributeSyntax.self) }.first { attribute in
      attribute.attributeName.trimmedDescription
        .split(separator: ".")
        .last == Substring(name)
    }
  }

  func visorContains(named name: String) -> Bool {
    visorAttribute(named: name) != nil
  }

  func unsupportedStateAttribute(
    allowingGeneratedAttribute: Bool = false
  ) -> AttributeSyntax? {
    compactMap { $0.as(AttributeSyntax.self) }.first { attribute in
      let name = attribute.attributeName.trimmedDescription
        .split(separator: ".")
        .last
      if ["ObservationIgnored", "Bound"].contains(name) {
        return false
      }
      if allowingGeneratedAttribute && name == "_ViewModelStateField" {
        return false
      }
      return true
    }
  }
}

extension DeclModifierListSyntax {
  var stateFieldAccessPrefix: String {
    let getterModifiers = filter { $0.detail?.detail.text != "set" }
    if getterModifiers.contains(where: {
      $0.name.text == "public" || $0.name.text == "open"
    }) {
      return "public "
    }
    if getterModifiers.contains(where: { $0.name.text == "package" }) {
      return "package "
    }
    if getterModifiers.contains(where: { $0.name.text == "fileprivate" }) {
      return "fileprivate "
    }
    if getterModifiers.contains(where: { $0.name.text == "private" }) {
      return "private "
    }
    return ""
  }

  var hasStateTypeStorageModifier: Bool {
    contains { $0.name.text == "static" || $0.name.text == "class" }
  }

  var hasPublicStateGetter: Bool {
    contains { modifier in
      modifier.detail?.detail.text != "set" &&
        (modifier.name.text == "public" || modifier.name.text == "open")
    }
  }

  var hasPrivateStateSetter: Bool {
    contains {
      $0.name.text == "private" && $0.detail?.detail.text == "set"
    }
  }
}

private extension PatternBindingSyntax {
  var isGetOnlyStateProperty: Bool {
    guard let accessorBlock else { return false }
    switch accessorBlock.accessors {
    case .getter:
      return true
    case let .accessors(accessors):
      return accessors.allSatisfy {
        $0.accessorSpecifier.text == "get"
      }
    }
  }

  var hasStateAccessorObservers: Bool {
    guard
      let accessorBlock,
      case let .accessors(accessors) = accessorBlock.accessors
    else {
      return false
    }
    return accessors.contains {
      ["willSet", "didSet"].contains($0.accessorSpecifier.text)
    }
  }
}

extension VariableDeclSyntax {
  private var stateIsolationModifier: DeclModifierSyntax? {
    modifiers.first { $0.name.text == "nonisolated" }
  }

  private var isIgnoredStateDeclaration: Bool {
    bindingSpecifier.text == "let" ||
      modifiers.hasStateTypeStorageModifier ||
      attributes.visorContains(named: "ObservationIgnored") ||
      (bindings.count == 1 && bindings.first?.isGetOnlyStateProperty == true)
  }

  func unsupportedStateFieldDiagnostic(
    allowingGeneratedAttribute: Bool = false
  ) -> UnsupportedStateFieldDiagnostic? {
    if
      bindingSpecifier.text == "var",
      !modifiers.hasStateTypeStorageModifier,
      attributes.visorContains(named: "ObservationIgnored"),
      bindings.count == 1,
      let binding = bindings.first,
      !binding.isGetOnlyStateProperty,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let modifier = stateIsolationModifier
    {
      return UnsupportedStateFieldDiagnostic(
        kind: .ignoredIsolationModifier,
        detail: modifier.trimmedDescription,
        fieldName: identifier.identifier.text)
    }

    guard !isIgnoredStateDeclaration else { return nil }
    guard bindings.count == 1, let binding = bindings.first else {
      return UnsupportedStateFieldDiagnostic(
        kind: .multipleBindings,
        detail: nil,
        fieldName: nil)
    }
    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
      return UnsupportedStateFieldDiagnostic(
        kind: .nonIdentifierPattern,
        detail: nil,
        fieldName: nil)
    }
    let fieldName = identifier.identifier.text

    if fieldName.hasPrefix("_visor") {
      return UnsupportedStateFieldDiagnostic(
        kind: .reservedName,
        detail: nil,
        fieldName: fieldName)
    }

    if binding.hasStateAccessorObservers {
      return UnsupportedStateFieldDiagnostic(
        kind: .accessorObservers,
        detail: nil,
        fieldName: fieldName)
    }
    if binding.accessorBlock != nil {
      return UnsupportedStateFieldDiagnostic(
        kind: .writableComputed,
        detail: nil,
        fieldName: fieldName)
    }
    if let modifier = stateIsolationModifier {
      return UnsupportedStateFieldDiagnostic(
        kind: .isolationModifier,
        detail: modifier.trimmedDescription,
        fieldName: fieldName)
    }
    if let modifier = modifiers.first(where: {
      ["lazy", "weak", "unowned"].contains($0.name.text)
    }) {
      return UnsupportedStateFieldDiagnostic(
        kind: .storageModifier,
        detail: modifier.name.text,
        fieldName: fieldName)
    }
    if let attribute = attributes.unsupportedStateAttribute(
      allowingGeneratedAttribute: allowingGeneratedAttribute
    ) {
      return UnsupportedStateFieldDiagnostic(
        kind: .attribute,
        detail: attribute.attributeName.trimmedDescription
          .split(separator: ".").last.map(String.init),
        fieldName: fieldName)
    }
    return nil
  }

  var hasUnrestrictedPublicStateSetter: Bool {
    stateFieldSpec(from: self) != nil &&
      modifiers.hasPublicStateGetter &&
      !modifiers.hasPrivateStateSetter
  }
}

extension ClassDeclSyntax {
  var hasRejectedStateField: Bool {
    memberBlock.members.contains { member in
      guard let variable = member.decl.as(VariableDeclSyntax.self) else {
        return false
      }
      return variable.unsupportedStateFieldDiagnostic() != nil ||
        variable.hasUnrestrictedPublicStateSetter
    }
  }
}

struct StateFieldSpec {
  let declaration: VariableDeclSyntax
  let binding: PatternBindingSyntax
  let name: String

  var accessPrefix: String { declaration.modifiers.stateFieldAccessPrefix }
  var typeText: String {
    binding.typeAnnotation.map { ": \($0.type.trimmedDescription)" } ?? ""
  }
  var initialiserText: String {
    binding.initializer.map { " = \($0.value.trimmedDescription)" } ?? ""
  }
}

func stateFieldSpec(
  from declaration: some DeclSyntaxProtocol,
  allowingObservationIgnored: Bool = false
) -> StateFieldSpec? {
  guard
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.text == "var",
    !variable.modifiers.hasStateTypeStorageModifier,
    variable.unsupportedStateFieldDiagnostic(
      allowingGeneratedAttribute: allowingObservationIgnored) == nil,
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    binding.accessorBlock == nil,
    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
    !identifier.identifier.text.hasPrefix("_visor"),
    allowingObservationIgnored ||
      !variable.attributes.visorContains(named: "ObservationIgnored")
  else {
    return nil
  }

  return StateFieldSpec(
    declaration: variable,
    binding: binding,
    name: identifier.identifier.text)
}
