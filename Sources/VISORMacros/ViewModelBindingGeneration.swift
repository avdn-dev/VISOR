import SwiftDiagnostics
import SwiftSyntax

/// Generate typed descriptors without spelling or inferring the user's field
/// types. Swift infers them from State key paths, including initialiser-only
/// stored declarations. Only validated action bindings produce descriptors;
/// forwarders never capture an instance or erase actions.
func viewModelBindingMembers(
  viewModel: ClassDeclSyntax,
  bindings: [StateBindingSpec],
  accessPrefix: String,
) -> [DeclSyntax] {
  let model = viewModel.name.text
  var members: [DeclSyntax] = bindings.map { binding in
    let name = binding.fieldName
    let argument = binding.label.map { "\($0): value" } ?? "value"
    return DeclSyntax(stringLiteral: """
      private static let _visorBinding_\(name) = VISOR._ViewModelBinding(
        for: \(model).self,
        keyPath: \\State.\(name)
      ) { model, value in
        _ = model.handle(.\(binding.caseName)(\(argument)))
      }
      """)
  }
  let selectors = bindings.map { binding in
    "\(binding.accessPrefix)let \(binding.fieldName) = \(model)._visorBinding_\(binding.fieldName)"
  }.joined(separator: "\n")
  members.append(contentsOf: [
    DeclSyntax(stringLiteral: """
      @MainActor
      \(accessPrefix)struct _VISORBindingSelectors {
        \(selectors)
        \(accessPrefix)init() {}
      }
      """),
    DeclSyntax(stringLiteral:
      "\(accessPrefix)static let _visorBindingSelectors = _VISORBindingSelectors()"),
    DeclSyntax(stringLiteral: """
      @ObservationIgnored
      private lazy var _visorBindings = VISOR.ViewModelBindings(self)
      """),
    DeclSyntax(stringLiteral: """
      \(accessPrefix)var bindings: VISOR.ViewModelBindings<\(model)> { _visorBindings }
      """),
  ])
  return members
}

// MARK: - BindingNamespaceDiagnostic

/// A focused diagnostic rather than a duplicate generated declaration.
struct BindingNamespaceDiagnostic: DiagnosticMessage {
  let macroName: String
  let name: String

  var message: String {
    "@\(macroName) could not generate '\(name)' because this type already declares that member; rename the existing member"
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: "bindingNamespaceCollision")
  }

  var severity: DiagnosticSeverity {
    macroName == "LazyViewModel" ? .warning : .error
  }
}
