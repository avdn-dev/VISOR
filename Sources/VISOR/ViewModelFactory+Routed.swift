//
//  ViewModelFactory+Routed.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

extension ViewModelFactory {
  /// Create a routed factory that receives a typed Router at VM creation time.
  /// The Router is automatically bridged from the RouterHost's environment.
  ///
  /// Usage (composition root):
  /// ```swift
  /// let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  ///     GalleryViewModel(router: router, galleryService: galleryService)
  /// }
  /// ```
  ///
  /// - Important: The consuming `@LazyViewModel` view must be beneath a
  ///   `RouterHost` whose `NavigationScene` matches `Scene`. A missing or
  ///   differently typed Router is a composition error that fails a precondition.
  public static func routed<Scene: NavigationScene>(
    _ make: @escaping (Router<Scene>) -> VM
  ) -> ViewModelFactory<VM> {
    ViewModelFactory(routed: { router in
      guard let router = router as? Router<Scene> else {
        preconditionFailure(
          ViewModelFactoryDiagnostics.routerTypeMismatchMessage(
            for: VM.self,
            expected: Router<Scene>.self,
            received: router))
      }
      return make(router)
    })
  }
}
