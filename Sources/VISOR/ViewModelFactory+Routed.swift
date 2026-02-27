//
//  ViewModelFactory+Routed.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

extension ViewModelFactory {
  /// Create a routed factory that receives a typed Router at VM creation time.
  /// The Router is automatically bridged from the NavigationContainer's environment.
  ///
  /// Usage (composition root):
  /// ```swift
  /// let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  ///     GalleryViewModel(router: router, galleryService: galleryService)
  /// }
  /// ```
  public static func routed<Scene: NavigationScene>(
    _ make: @escaping (Router<Scene>) -> VM
  ) -> ViewModelFactory<VM> {
    ViewModelFactory(routed: { router in
      guard let router = router as? Router<Scene> else {
        preconditionFailure(
          "ViewModelFactory expected Router<\(Scene.self)> but received \(type(of: router)). Ensure the view is inside a NavigationContainer<\(Scene.self)>.")
      }
      return make(router)
    })
  }
}
