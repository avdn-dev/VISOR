//
//  DefaultReturnMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 4/6/2026.
//

/// Provides a custom default return value for a protocol method in generated stub and spy classes.
///
/// Use this when the return type has no auto-detectable default (e.g. custom enums),
/// or when you want to override the generated default.
/// The expression must be fully qualified — `.idle` alone can't infer the type in attribute context.
///
/// ```swift
/// @GenerateStub
/// protocol ThemeProviding: AnyObject {
///   @DefaultReturn(Theme.system) func currentTheme() -> Theme
/// }
/// ```
@attached(peer)
public macro DefaultReturn<T>(_ defaultReturn: T) = #externalMacro(
  module: "VISORMacros", type: "DefaultValueMacro")
