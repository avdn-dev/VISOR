//
//  StubbableDefaultMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

/// Provides a custom default value for a protocol property in `@Stubbable` / `@Spyable` generated classes.
///
/// Use this when the property type has no auto-detectable default (e.g. custom enums).
/// The expression must be fully qualified — `.idle` alone can't infer the type in attribute context.
///
/// ```swift
/// @Stubbable
/// protocol AnimationExtractionInteractor: AnyObject {
///   @StubbableDefault(ExtractionStatus.idle) var status: ExtractionStatus { get }
/// }
/// ```
@attached(peer)
public macro StubbableDefault<T>(_ defaultValue: T) = #externalMacro(
  module: "VISORMacros", type: "StubbableDefaultMacro")
