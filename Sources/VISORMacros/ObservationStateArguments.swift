import SwiftParser
import SwiftSyntax

enum ObservationStateSequenceNaming: Equatable {
  case snapshots
  case values
  case named(String)

  func memberName(for stateName: String) -> String {
    switch self {
    case .snapshots:
      "\(stateName)Snapshots"
    case .values:
      "\(stateName)Values"
    case .named(let name):
      name
    }
  }

  var attributeArgument: String? {
    switch self {
    case .snapshots:
      nil
    case .values:
      "observedAs: .values"
    case .named(let name):
      "observedAs: .named(\"\(name)\")"
    }
  }
}

struct ObservationStateArguments: Equatable {
  let initialValueExpression: String?
  let sequenceNaming: ObservationStateSequenceNaming

  static func parse(from attribute: AttributeSyntax) -> Result<Self, ObservationStateArgumentError> {
    guard let arguments = attribute.arguments else {
      return .success(Self(initialValueExpression: nil, sequenceNaming: .snapshots))
    }
    guard let expressions = arguments.as(LabeledExprListSyntax.self) else {
      return .failure(.invalidArguments)
    }

    var initialValueExpression: String?
    var sequenceNaming: ObservationStateSequenceNaming = .snapshots
    var foundSequenceNaming = false

    for expression in expressions {
      switch expression.label?.text {
      case "initial":
        guard initialValueExpression == nil else {
          return .failure(.invalidArguments)
        }
        initialValueExpression = expression.expression.trimmedDescription

      case "observedAs":
        guard !foundSequenceNaming else {
          return .failure(.invalidArguments)
        }
        foundSequenceNaming = true
        switch parseSequenceNaming(from: expression.expression) {
        case .success(let naming):
          sequenceNaming = naming
        case .failure(let error):
          return .failure(error)
        }

      default:
        return .failure(.invalidArguments)
      }
    }

    return .success(Self(
      initialValueExpression: initialValueExpression,
      sequenceNaming: sequenceNaming))
  }
}

enum ObservationStateArgumentError: Error, Equatable {
  case invalidArguments
  case invalidCustomName
}

private func parseSequenceNaming(
  from expression: ExprSyntax
) -> Result<ObservationStateSequenceNaming, ObservationStateArgumentError> {
  if let member = expression.as(MemberAccessExprSyntax.self), member.base == nil {
    switch member.declName.baseName.text {
    case "snapshots":
      return .success(.snapshots)
    case "values":
      return .success(.values)
    default:
      return .failure(.invalidArguments)
    }
  }

  guard
    let call = expression.as(FunctionCallExprSyntax.self),
    let member = call.calledExpression.as(MemberAccessExprSyntax.self),
    member.base == nil,
    member.declName.baseName.text == "named",
    call.arguments.count == 1,
    let argument = call.arguments.first,
    argument.label == nil,
    let literal = argument.expression.as(StringLiteralExprSyntax.self),
    literal.segments.count == 1,
    let segment = literal.segments.first?.as(StringSegmentSyntax.self)
  else {
    return .failure(.invalidArguments)
  }

  let name = segment.content.text
  guard isValidSwiftIdentifier(name) else {
    return .failure(.invalidCustomName)
  }
  return .success(.named(name))
}

private func isValidSwiftIdentifier(_ name: String) -> Bool {
  guard !name.isEmpty else { return false }
  let source = Parser.parse(source: "var \(name): Int")
  guard
    !source.hasError,
    source.statements.count == 1,
    let declaration = source.statements.first?.item.as(VariableDeclSyntax.self),
    declaration.bindings.count == 1,
    let identifier = declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self)
  else {
    return false
  }
  return identifier.identifier.text == name
}
