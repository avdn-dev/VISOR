//
//  ViewModelFactory.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import Observation

// MARK: - ViewModelFactory

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
/// Usage (preview via `PreviewProviding`):
/// ```swift
/// .previewFactory(for: CameraViewModel.self)
/// ```
/// - Note: `@Observable` is required for `@Environment` injection even though all
///   stored properties are `@ObservationIgnored`.
@Observable
public final class ViewModelFactory<VM: ViewModel> {
  @ObservationIgnored private let _make: (AnyObject?) -> VM

  /// Create a factory that does not need a router.
  public init(_ make: @escaping () -> VM) {
    _make = { _ in make() }
  }

  /// Create a factory that receives a type-erased router at creation time.
  /// Use the typed `ViewModelFactory.routed { }` convenience instead.
  public init(routed make: @escaping (AnyObject) -> VM) {
    _make = { router in
      guard let router else {
        preconditionFailure(
          "Routed ViewModelFactory requires a router. Ensure the view is inside a NavigationContainer.")
      }
      return make(router)
    }
  }

  /// Create a ViewModel, optionally passing a router for routed factories.
  public func makeViewModel(router: AnyObject? = nil) -> VM {
    _make(router)
  }
}

// MARK: - PreviewProviding

/// Marker protocol enabling `ViewModelFactory<VM>.preview`.
///
/// `@ViewModel` auto-generates conformance and a `static var preview` member.
/// In DEBUG, the preview uses `Stub*` types for dependencies.
/// In release, a fatalError fallback satisfies the conformance (never called).
public protocol PreviewProviding {
  associatedtype PreviewInstance = Self
  static var preview: PreviewInstance { get }
}
