//
//  ViewModelFactory.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//


// MARK: - ViewModelFactory

package enum ViewModelFactoryDiagnostics {
  package static func missingRouterMessage<VM: ViewModel>(for viewModelType: VM.Type) -> String {
    "Could not create \(describe(viewModelType)): routed ViewModelFactory requires a router, " +
      "but EnvironmentValues.router was nil. Ensure the @LazyViewModel view is rendered " +
      "inside a NavigationContainer, or inject a non-routed factory if this ViewModel does not navigate."
  }

  package static func routerTypeMismatchMessage<VM: ViewModel, Scene: NavigationScene>(
    for viewModelType: VM.Type,
    expected: Router<Scene>.Type,
    received router: AnyObject
  ) -> String {
    "Could not create \(describe(viewModelType)): routed ViewModelFactory expected \(describe(expected)) " +
      "but received \(describe(type(of: router))). Ensure the view is inside " +
      "a NavigationContainer<\(describe(Scene.self))> matching the factory's router type."
  }

  private static func describe(_ type: Any.Type) -> String {
    String(reflecting: type)
  }
}

/// Generic factory that lazily creates ViewModel instances via a stored closure.
///
/// Each ViewModel class annotated with `@ViewModel` generates a nested typealias:
/// ```swift
/// typealias Factory = ViewModelFactory<CameraViewModel>
/// ```
///
/// Usage (composition root):
/// ```swift
/// CameraViewModel.Factory { CameraViewModel(service: liveService) }
/// ```
///
/// - Note: `@Observable` is required for `@Environment` injection even though
///   stored properties are `@ObservationIgnored`.
@MainActor @Observable
public final class ViewModelFactory<VM: ViewModel> {
  // Workaround: Swift 6.2 SIL EarlyPerfInliner crash with -default-isolation MainActor + -O.
  // See Router.swift for details.
  nonisolated deinit { }

  @ObservationIgnored private let _make: (AnyObject?) -> VM

  /// Create a factory that does not need a router.
  public init(_ make: @escaping () -> VM) {
    _make = { _ in make() }
  }

  /// Create a factory that receives a type-erased router at creation time.
  /// Use the typed `ViewModelFactory.routed { }` convenience instead.
  package init(routed make: @escaping (AnyObject) -> VM) {
    _make = { router in
      guard let router else {
        preconditionFailure(
          ViewModelFactoryDiagnostics.missingRouterMessage(for: VM.self))
      }
      return make(router)
    }
  }

  /// Create a ViewModel. The router parameter is for generated code only.
  public func makeViewModel(router: AnyObject? = nil) -> VM {
    _make(router)
  }
}
