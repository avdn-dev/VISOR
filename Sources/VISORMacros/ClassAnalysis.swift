import SwiftSyntax

extension StructDeclSyntax {
  var hasContentProperty: Bool {
    hasMemberNamed("content")
  }

  func hasMemberNamed(_ name: String) -> Bool {
    memberBlock.members.contains { member in
      if let variable = member.decl.as(VariableDeclSyntax.self) {
        return variable.bindings.contains { binding in
          binding.pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text == name
        }
      }
      if let function = member.decl.as(FunctionDeclSyntax.self) {
        return function.name.text == name
      }
      return false
    }
  }
}

// MARK: - ClassAnalysis

/// The class-level facts needed by the v11 ViewModel macro.
struct ClassAnalysis {

  // MARK: Lifecycle

  init(_ declaration: ClassDeclSyntax) {
    for member in declaration.memberBlock.members {
      if
        let enumDeclaration = member.decl.as(EnumDeclSyntax.self),
        enumDeclaration.name.text == "Action"
      {
        hasActionEnum = true
        continue
      }

      guard
        let function = member.decl.as(FunctionDeclSyntax.self),
        function.name.text == "handle"
      else {
        continue
      }
      let parameters = function.signature.parameterClause.parameters
      guard
        parameters.count == 1,
        let parameter = parameters.first,
        parameter.type.trimmedDescription == "Action"
      else {
        continue
      }
      if parameter.firstName.text == "_" {
        hasHandleMethod = true
      } else {
        handleHasWrongLabel = true
      }
    }
  }

  // MARK: Internal

  var hasActionEnum = false
  var hasHandleMethod = false
  var handleHasWrongLabel = false

}
