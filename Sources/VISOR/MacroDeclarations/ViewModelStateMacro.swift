//
//  ViewModelStateMacro.swift
//  VISOR
//
//  Attach to the nested `@Observable final class State` inside a `@ViewModel` class.
//  Generates `Equatable` conformance comparing all stored properties.
//

/// Generates `Equatable` conformance for an `@Observable` State class.
///
/// Apply alongside `@Observable` on the nested `State` class inside a `@ViewModel`:
///
/// ```swift
/// @Observable
/// @ViewModel
/// final class ItemsVM {
///     @Observable
///     @ViewModelState
///     final class State {
///         var items: Loadable<[Item]> = .loading
///
///         nonisolated init() {}
///     }
///     private let service: ItemsService
/// }
/// ```
///
/// **What it generates:**
/// - An `Equatable` extension comparing all stored properties (skipped if you define `==` yourself).
///
/// **You must declare your own `nonisolated init`.**
/// `#Preview` is a macro and cannot see macro-generated initialisers — a hand-written
/// init ensures State is constructable in previews and tests.
@attached(extension, conformances: Equatable, names: named(==))
public macro ViewModelState() = #externalMacro(module: "VISORMacros", type: "ViewModelStateMacro")
