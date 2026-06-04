//
//  DefaultValueMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

/// Provides a custom default value for a protocol property in generated stub and spy classes.
///
/// Use this when the property type has no auto-detectable default (e.g. custom enums).
/// The expression must be fully qualified — `.idle` alone can't infer the type in attribute context.
///
/// ```swift
/// @GenerateStub
/// protocol AnimationExtractionInteractor: AnyObject {
///   @DefaultValue(ExtractionStatus.idle) var status: ExtractionStatus { get }
/// }
/// ```
@attached(peer)
public macro DefaultValue<T>(_ defaultValue: T) = #externalMacro(
  module: "VISORMacros", type: "DefaultValueMacro")
