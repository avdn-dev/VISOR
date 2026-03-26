//
//  ViewModelStateMacro.swift
//  VISOR
//
//  Generates Equatable conformance for @Observable State classes.
//  Scans the ORIGINAL stored vars (before @Observable transforms them).
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ViewModelStateMacro

public struct ViewModelStateMacro: ExtensionMacro {

  // MARK: - Shared: collect stored property names

  /// Collects all stored var names for Equatable comparison.
  /// Works on every stored var regardless of type inference.
  private static func collectStoredPropertyNames(from declaration: some DeclGroupSyntax) -> [String] {
    var names: [String] = []
    for member in declaration.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
      guard varDecl.bindingSpecifier.text == "var" else { continue }
      for binding in varDecl.bindings {
        guard binding.accessorBlock == nil else { continue }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
        names.append(identifier.identifier.text)
      }
    }
    return names
  }

  // MARK: - ExtensionMacro (generates Equatable conformance)

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(ClassDeclSyntax.self) else { return [] }

    // Check if user already defined Equatable conformance
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
      let hasUserEquatable = classDecl.memberBlock.members.contains { member in
        guard let funcDecl = member.decl.as(FunctionDeclSyntax.self),
              funcDecl.name.text == "==",
              funcDecl.modifiers.contains(where: { $0.name.text == "static" })
        else { return false }
        return true
      }
      if hasUserEquatable { return [] }

      // Also check if the class already declares Equatable conformance
      if let inheritanceClause = classDecl.inheritanceClause {
        let inheritsEquatable = inheritanceClause.inheritedTypes.contains { inherited in
          inherited.type.trimmedDescription.contains("Equatable")
        }
        if inheritsEquatable { return [] }
      }
    }

    let names = collectStoredPropertyNames(from: declaration)
    guard !names.isEmpty else { return [] }

    let access = accessLevel(of: declaration)
    let prefix = access.isEmpty ? "" : "\(access) "

    let comparisons = names
      .map { "lhs.\($0) == rhs.\($0)" }
      .joined(separator: "\n            && ")

    let equatableExt: DeclSyntax = """
      extension \(type.trimmed): @preconcurrency Equatable {
          \(raw: prefix)static func == (lhs: \(type.trimmed), rhs: \(type.trimmed)) -> Bool {
              \(raw: comparisons)
          }
      }
      """
    return [equatableExt.cast(ExtensionDeclSyntax.self)]
  }
}
