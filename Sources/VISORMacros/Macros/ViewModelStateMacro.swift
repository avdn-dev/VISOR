import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ViewModelStateMacro

public struct ViewModelStateMacro:
  MemberMacro,
  MemberAttributeMacro,
  ExtensionMacro
{
  public static func expansion(
    of _: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard let state = declaration.as(ClassDeclSyntax.self) else { return [] }
    if !state.conditionalDeinitialisers.isEmpty {
      for deinitialiser in state.conditionalDeinitialisers {
        context.diagnose(Diagnostic(
          node: Syntax(deinitialiser),
          message: VISORDiagnostic.conditionalDeinitialiserUnsupported,
        ))
      }
      return []
    }
    guard !state.hasRejectedStateField else { return [] }

    let stateName = state.name.text
    let fields = state.memberBlock.members.compactMap {
      stateFieldSpec(from: $0.decl)
    }
    let prefix = state.modifiers.stateFieldAccessPrefix

    let fieldDescriptors: [DeclSyntax] = fields.map { field in
      let keyPath = "\\\(stateName).\(field.name)"
      return """
        private static let _visorField_\(raw: field.name) = VISOR._StateField(
          "\(raw: field.name)",
          keyPath: \(raw: keyPath))
        """
    }

    let selectorMembers = fields.compactMap { field -> String? in
      guard field.accessPrefix != "private " else { return nil }
      return "\(field.accessPrefix)let \(field.name) = \(stateName)._visorField_\(field.name)"
    }.joined(separator: "\n")

    let selectors: DeclSyntax = """
      @MainActor
      \(raw: prefix)struct _VISORSelectors {
        \(raw: selectorMembers)

        \(raw: prefix)init() {}
      }
      """
    let recorder: DeclSyntax = """
      \(raw: prefix)var _visorMutationRecorder: (any VISOR._StateMutationRecorder)?
      """
    let registrar: DeclSyntax = """
      private let _$observationRegistrar = Observation.ObservationRegistrar()
      """
    let access: DeclSyntax = """
      nonisolated func access<Member>(keyPath: KeyPath<\(raw: stateName), Member>) {
        _$observationRegistrar.access(self, keyPath: keyPath)
      }
      """
    let withMutation: DeclSyntax = """
      nonisolated func withMutation<Member, MutationResult>(
        keyPath: KeyPath<\(raw: stateName), Member>,
        _ mutation: () throws -> MutationResult
      ) rethrows -> MutationResult {
        try _$observationRegistrar.withMutation(
          of: self,
          keyPath: keyPath,
          mutation)
      }
      """
    let selectorRoot: DeclSyntax = """
      @MainActor
      \(raw: prefix)static let _visorSelectors = _VISORSelectors()
      """
    let allFieldMembers = fields.map { field in
      "VISOR._AnyStateField(_visorField_\(field.name), untrackedRead: { $0._\(field.name) })"
    }.joined(separator: ",\n")
    let allFields: DeclSyntax = """
      @MainActor
      \(raw: prefix)static let _visorAllFields: [VISOR._AnyStateField<\(raw: stateName)>] = [
        \(raw: allFieldMembers)
      ]
      """
    let genericComparison: DeclSyntax = """
      private nonisolated func _visorShouldNotifyObservers<Value>(
        _ lhs: Value,
        _ rhs: Value
      ) -> Bool { true }
      """
    let equatableComparison: DeclSyntax = """
      private nonisolated func _visorShouldNotifyObservers<Value: Equatable>(
        _ lhs: Value,
        _ rhs: Value
      ) -> Bool { lhs != rhs }
      """
    let referenceComparison: DeclSyntax = """
      private nonisolated func _visorShouldNotifyObservers<Value: AnyObject>(
        _ lhs: Value,
        _ rhs: Value
      ) -> Bool { lhs !== rhs }
      """
    let equatableReferenceComparison: DeclSyntax = """
      private nonisolated func _visorShouldNotifyObservers<
        Value: Equatable & AnyObject
      >(
        _ lhs: Value,
        _ rhs: Value
      ) -> Bool { lhs != rhs }
      """

    let deinitialiser: [DeclSyntax] = state.hasExplicitDeinitialiser
      ? []
      : ["deinit {}"]

    return [registrar, access, withMutation, recorder] + fieldDescriptors + [
      selectors,
      selectorRoot,
      allFields,
      genericComparison,
      equatableComparison,
      referenceComparison,
      equatableReferenceComparison,
    ] + deinitialiser
  }

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [AttributeSyntax] {
    guard let state = declaration.as(ClassDeclSyntax.self) else { return [] }
    if !state.conditionalDeinitialisers.isEmpty {
      return []
    }
    if
      let variable = member.as(VariableDeclSyntax.self),
      let diagnostic = variable.unsupportedStateFieldDiagnostic()
    {
      context.diagnose(Diagnostic(node: Syntax(variable), message: diagnostic))
      return []
    }
    guard let field = stateFieldSpec(from: member) else { return [] }

    if
      field.declaration.modifiers.hasPublicStateGetter,
      !field.declaration.modifiers.hasPrivateStateSetter
    {
      let setterModifier = field.declaration.modifiers.first {
        $0.detail?.detail.text == "set"
      }
      let changes: [FixIt.Change]
      if let setterModifier {
        changes = [
          .replace(
            oldNode: Syntax(setterModifier),
            newNode: Syntax(setterModifier.with(\.name, .keyword(.private))),
          )
        ]
      } else {
        let position = field.declaration.bindingSpecifier.position
        changes = [
          .replaceText(
            range: position..<position,
            with: "private(set) ",
            in: Syntax(field.declaration),
          )
        ]
      }
      context.diagnose(Diagnostic(
        node: Syntax(field.declaration),
        message: StateFieldPolicyDiagnostic.unrestrictedPublicSetter,
        fixIts: [
          FixIt(
            message: StateFieldFixIt.restrictStateSetter,
            changes: changes,
          )
        ],
      ))
      return []
    }

    guard !state.hasRejectedStateField else { return [] }

    return ["@VISOR._ViewModelStateField"]
  }

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext,
  ) throws -> [ExtensionDeclSyntax] {
    guard
      let state = declaration.as(ClassDeclSyntax.self),
      state.conditionalDeinitialisers.isEmpty,
      !state.hasRejectedStateField
    else {
      return []
    }
    return [
      try ExtensionDeclSyntax(
        "extension \(type): nonisolated Observation.Observable {}"
      ),
      try ExtensionDeclSyntax(
        "extension \(type): VISOR._ViewModelState {}"
      ),
    ]
  }
}

// MARK: - StateFieldPolicyDiagnostic

private enum StateFieldPolicyDiagnostic: String, DiagnosticMessage {
  case unrestrictedPublicSetter

  var message: String {
    "public VISOR State fields require private(set)"
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: rawValue)
  }

  var severity: DiagnosticSeverity {
    .error
  }
}

// MARK: - ViewModelStateFieldMacro

public struct ViewModelStateFieldMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard
      let field = stateFieldSpec(
        from: declaration,
        allowingObservationIgnored: true,
      )
    else { return [] }
    return ["""
      private var _\(raw: field.name)\(raw: field.typeText)\(raw: field.initialiserText)
      """]
  }

  public static func expansion(
    of _: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext,
  ) throws -> [AccessorDeclSyntax] {
    guard
      let field = stateFieldSpec(
        from: declaration,
        allowingObservationIgnored: true,
      )
    else { return [] }
    let name = field.name

    let initialiser: AccessorDeclSyntax = """
      @storageRestrictions(initializes: _\(raw: name))
      init(initialValue) {
        _\(raw: name) = initialValue
      }
      """
    let getter: AccessorDeclSyntax = """
      get {
        access(keyPath: \\.\(raw: name))
        return _\(raw: name)
      }
      """
    let setter: AccessorDeclSyntax = """
      set {
        guard _visorMutationRecorder != nil else {
          if _visorShouldNotifyObservers(_\(raw: name), newValue) {
            withMutation(keyPath: \\.\(raw: name)) {
              _\(raw: name) = newValue
            }
          } else {
            _\(raw: name) = newValue
          }
          return
        }

        if _visorShouldNotifyObservers(_\(raw: name), newValue) {
          withMutation(keyPath: \\.\(raw: name)) {
            _\(raw: name) = newValue
          }
        } else {
          _\(raw: name) = newValue
        }
        let resultingValue = _\(raw: name)
        _visorRecordMutation(
          Self._visorField_\(raw: name),
          newValue: resultingValue)
      }
      """
    let modify: AccessorDeclSyntax = """
      _modify {
        access(keyPath: \\.\(raw: name))

        guard _visorMutationRecorder != nil else {
          _$observationRegistrar.willSet(self, keyPath: \\.\(raw: name))
          defer {
            _$observationRegistrar.didSet(self, keyPath: \\.\(raw: name))
          }
          yield &_\(raw: name)
          return
        }

        _$observationRegistrar.willSet(self, keyPath: \\.\(raw: name))
        defer {
          _$observationRegistrar.didSet(self, keyPath: \\.\(raw: name))
          _visorRecordMutation(
            Self._visorField_\(raw: name),
            newValue: _\(raw: name))
        }
        yield &_\(raw: name)
      }
      """
    return [initialiser, getter, setter, modify]
  }
}
