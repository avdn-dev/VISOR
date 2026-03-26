//
//  ViewModelStateMacro.swift
//  VISOR
//
//  Generates a memberwise init and Equatable conformance for @Observable State classes.
//  Scans the ORIGINAL stored vars (before @Observable transforms them).
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ViewModelStateMacro

public struct ViewModelStateMacro: MemberMacro, ExtensionMacro {

  // MARK: - Shared: collect stored property info from original declarations

  private struct StoredProp {
    let name: String
    let type: String
    let defaultExpr: String?
  }

  private static func collectStoredProperties(from declaration: some DeclGroupSyntax) -> [StoredProp] {
    var props: [StoredProp] = []

    for member in declaration.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
      guard varDecl.bindingSpecifier.text == "var" else { continue }

      for binding in varDecl.bindings {
        // Skip computed properties
        guard binding.accessorBlock == nil else { continue }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }

        let name = identifier.identifier.text

        // Get type from annotation, or infer from default literal
        let type: String
        if let typeAnnotation = binding.typeAnnotation {
          type = typeAnnotation.type.trimmedDescription
        } else if let initExpr = binding.initializer?.value {
          // Infer type from literal defaults
          let exprText = initExpr.trimmedDescription
          if exprText == "true" || exprText == "false" { type = "Bool" }
          else if exprText.first?.isNumber == true && exprText.contains(".") { type = "Double" }
          else if exprText.first?.isNumber == true { type = "Int" }
          else if exprText.hasPrefix("\"") { type = "String" }
          else if exprText == "nil" { continue } // can't infer Optional<T>
          else { continue } // unknown literal type
        } else {
          continue
        }

        let defaultExpr = binding.initializer?.value.trimmedDescription

        props.append(StoredProp(name: name, type: type, defaultExpr: defaultExpr))
      }
    }

    return props
  }

  // MARK: - MemberMacro (generates init)

  public static func expansion(
    of _: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard declaration.is(ClassDeclSyntax.self) else { return [] }

    let props = collectStoredProperties(from: declaration)
    guard !props.isEmpty else { return [] }

    let access = accessLevel(of: declaration)
    let prefix = access.isEmpty ? "" : "\(access) "

    // Generate designated memberwise init.
    // Assigns to _name (the @Observable backing store) to avoid triggering
    // observation during init. @Observable renames var x → _x.
    let initParams = props.map { p in
      if let def = p.defaultExpr {
        return "\(p.name): \(p.type) = \(def)"
      }
      return "\(p.name): \(p.type)"
    }.joined(separator: ", ")

    let initAssignments = props.map { p in
      "self._\(p.name) = \(p.name)"
    }.joined(separator: "\n        ")

    var members: [DeclSyntax] = []

    let designatedInit: DeclSyntax = """
      \(raw: prefix)init(\(raw: initParams)) {
          \(raw: initAssignments)
      }
      """
    members.append(designatedInit)

    // If any param lacks a default, also generate convenience init()
    let propsWithoutDefaults = props.filter { $0.defaultExpr == nil }
    if !propsWithoutDefaults.isEmpty {
      var convenienceArgs: [String] = []
      var canGenerateConvenience = true

      for p in props {
        if p.defaultExpr != nil {
          // Has a default — omit from call (uses parameter default)
        } else {
          if let syntheticDefault = defaultValue(for: p.type) {
            convenienceArgs.append("\(p.name): \(syntheticDefault)")
          } else {
            canGenerateConvenience = false
            break
          }
        }
      }

      if canGenerateConvenience {
        let argList = convenienceArgs.joined(separator: ", ")
        let convenienceInit: DeclSyntax = """
          \(raw: prefix)convenience init() {
              self.init(\(raw: argList))
          }
          """
        members.append(convenienceInit)
      }
    }

    return members
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

    let props = collectStoredProperties(from: declaration)
    guard !props.isEmpty else { return [] }

    let access = accessLevel(of: declaration)
    let prefix = access.isEmpty ? "" : "\(access) "

    let comparisons = props
      .map { "lhs.\($0.name) == rhs.\($0.name)" }
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
