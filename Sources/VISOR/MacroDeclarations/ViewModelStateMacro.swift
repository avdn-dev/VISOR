//
//  ViewModelStateMacro.swift
//  VISOR
//
//  Attach to the nested `@Observable final class State` inside a `@ViewModel` class.
//  Generates a memberwise init (with defaults preserved) and `Equatable` conformance.
//

/// Generates a memberwise `init` and `Equatable` conformance for an `@Observable` State class.
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
///         @Bound(\ItemsVM.service.isAuthenticated) var isAuthenticated: Bool
///         var items: Loadable<[Item]> = .loading
///     }
///     private let service: ItemsService
/// }
/// ```
///
/// **What it generates:**
/// - A designated memberwise `init` with parameter defaults matching property defaults.
/// - A convenience `init()` when some properties lack defaults (using known-type defaults).
/// - An `Equatable` extension comparing all stored properties (skipped if you define `==` yourself).
@attached(member, names: named(init))
@attached(extension, conformances: Equatable, names: named(==))
public macro ViewModelState() = #externalMacro(module: "VISORMacros", type: "ViewModelStateMacro")
