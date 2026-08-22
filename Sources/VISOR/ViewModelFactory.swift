//
//  ViewModelFactory.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import Observation

// MARK: - ViewModelFactory

package enum ViewModelFactoryDiagnostics {
  package static func missingRouterMessage<VM: ViewModel>(for viewModelType: VM.Type) -> String {
    "Could not create \(describe(viewModelType)): routed ViewModelFactory requires a router, " +
      "but EnvironmentValues._visorRouter was nil. Ensure the @LazyViewModel view is rendered " +
      "inside a RouterHost, or inject a non-routed factory if this ViewModel does not navigate."
  }

  package static func routerTypeMismatchMessage<VM: ViewModel, Scene: NavigationScene>(
    for viewModelType: VM.Type,
    expected: Router<Scene>.Type,
    received router: AnyObject
  ) -> String {
    "Could not create \(describe(viewModelType)): routed ViewModelFactory expected \(describe(expected)) " +
      "but received \(describe(type(of: router))). Ensure the view is inside " +
      "a RouterHost that provides Router<\(describe(Scene.self))>."
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

  /// Creates a ViewModel from this factory.
  ///
  /// Use this method for non-routed factories. `@LazyViewModel` supplies the
  /// generated Router bridge automatically for factories created with
  /// ``routed(_:)``.
  ///
  /// - Precondition: This factory was created with ``init(_:)``. Calling this
  ///   method on a routed factory fails because no Router is supplied.
  public func makeViewModel() -> VM {
    _make(nil)
  }

  /// Creates a ViewModel with the generated type-erased Router bridge.
  ///
  /// This method is public only because attached macro expansions are
  /// type-checked in the consuming module. Call ``makeViewModel()`` from
  /// application code.
  ///
  /// - Precondition: A routed factory receives a non-nil Router whose
  ///   `NavigationScene` matches the type declared by ``routed(_:)``.
  public func _visorMakeViewModel(router: AnyObject?) -> VM {
    _make(router)
  }
}
