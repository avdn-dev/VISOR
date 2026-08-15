import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ObservationStateMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    if observationStateRequirement(
      from: declaration,
      in: context,
      diagnose: false) != nil
    {
      return []
    }

    guard let property = observationStateProperty(
      from: declaration,
      in: context,
      diagnose: false
    ) else {
      return []
    }

    let channel: DeclSyntax = """
      \(raw: property.channelModifiers)let _\(raw: property.name)Channel:
        VISORObservation.ObservationChannel<\(raw: property.type)> =
        VISORObservation.ObservationChannel(\(raw: property.initialValue))
      """
    let source: DeclSyntax = """
      \(raw: property.sourceModifiers)var \(raw: property.name)Source:
        VISORObservation.ObservationSource<\(raw: property.type)> {
        _\(raw: property.name)Channel.source
      }
      """

    return [channel, source]
  }

  public static func expansion(
    of _: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    if observationStateRequirement(
      from: declaration,
      in: context,
      diagnose: false) != nil
    {
      return []
    }

    guard let property = observationStateProperty(
      from: declaration,
      in: context,
      diagnose: true
    ) else {
      return []
    }

    let initialiser: AccessorDeclSyntax = """
      @storageRestrictions(accesses: _\(raw: property.name)Channel)
      init(initialValue) {
        _\(raw: property.name)Channel.publish(initialValue)
      }
      """
    let getter: AccessorDeclSyntax = """
      get {
        _\(raw: property.name)Channel.source.currentSnapshot()
      }
      """
    let setter: AccessorDeclSyntax = """
      set {
        _\(raw: property.name)Channel.publish(newValue)
      }
      """

    return [initialiser, getter, setter]
  }
}

private func observationStateRequirement(
  from declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  diagnose: Bool
) -> Bool? {
  guard context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true else {
    return nil
  }
  guard
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.tokenKind == .keyword(.var),
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    binding.pattern.is(IdentifierPatternSyntax.self),
    binding.typeAnnotation != nil,
    binding.initializer == nil,
    binding.accessorBlock != nil,
    !variable.modifiers.contains(where: {
      $0.name.tokenKind == .keyword(.static)
        || $0.name.tokenKind == .keyword(.class)
    })
  else {
    if diagnose {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: ObservationStateDiagnostic.invalidDeclaration))
    }
    return nil
  }

  return true
}

private struct ObservationStateProperty {
  let name: String
  let type: String
  let initialValue: String
  let sourceModifiers: String

  var channelModifiers: String {
    sourceModifiers.contains("nonisolated ")
      ? "nonisolated private "
      : "private "
  }
}

private func observationStateProperty(
  from declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  diagnose: Bool
) -> ObservationStateProperty? {
  let owner = context.lexicalContext.first
  let hasReferenceOwner = owner?.is(ClassDeclSyntax.self) == true
    || owner?.is(ActorDeclSyntax.self) == true
  guard
    hasReferenceOwner,
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.tokenKind == .keyword(.var),
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
    let type = binding.typeAnnotation?.type.trimmedDescription,
    let initialValue = binding.initializer?.value.trimmedDescription,
    binding.accessorBlock == nil,
    !variable.modifiers.contains(where: {
      $0.name.tokenKind == .keyword(.static)
        || $0.name.tokenKind == .keyword(.class)
    })
  else {
    if diagnose {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: ObservationStateDiagnostic.invalidDeclaration))
    }
    return nil
  }

  let sourceModifiers = variable.modifiers.compactMap { modifier -> String? in
    guard modifier.detail == nil else { return nil }
    switch modifier.name.tokenKind {
    case .keyword(.public), .keyword(.package), .keyword(.fileprivate),
      .keyword(.private), .keyword(.nonisolated):
      return "\(modifier.trimmedDescription) "
    case .keyword(.open):
      return "public "
    default:
      return nil
    }
  }.joined()

  return ObservationStateProperty(
    name: name,
    type: type,
    initialValue: initialValue,
    sourceModifiers: sourceModifiers)
}

private enum ObservationStateDiagnostic: String, DiagnosticMessage {
  case invalidDeclaration

  var message: String {
    "@ObservationState requires one non-static protocol property requirement or stored var with an explicit type and initial value inside a class or actor"
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: rawValue)
  }

  var severity: DiagnosticSeverity { .error }
}
