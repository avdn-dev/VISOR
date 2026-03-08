//
//  LazyViewModelsMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

// MARK: - Multiple ViewModels Macro

/// Attach to a View struct to enable lazy initialization of multiple view models.
/// Auto-generates @Environment factories, @State backing storage, computed accessors, and body.
/// Property names are derived from ViewModel type names (e.g., `CameraViewModel` -> `cameraViewModel`).
///
/// Usage:
/// ```swift
/// @LazyViewModels(
///   CameraViewModel.self,
///   GalleryViewModel.self
/// )
/// ```
///
/// > Each generated accessor (e.g. `cameraViewModel`) force-unwraps the backing `@State`.
/// > This is safe because the generated `body` guards with a nil check before rendering
/// > `content`, and initialization is guaranteed by the `.task` modifier.
@attached(member, names: arbitrary)
public macro LazyViewModels(_ viewModels: Any...) = #externalMacro(
  module: "VISORMacros",
  type: "LazyViewModelsMacro")
