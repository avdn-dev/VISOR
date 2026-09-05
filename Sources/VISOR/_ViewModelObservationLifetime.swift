//
//  _ViewModelObservationLifetime.swift
//  VISOR
//
//  Created by avdn-dev on 05.09.2026.
//

/// Owns one observation root for the host's SwiftUI identity, including periods
/// when navigation or tab selection covers that host. The root captures the
/// observation owner, never this lifetime, so removing the host cancels it.
@MainActor
final class _ViewModelObservationLifetime<VM: ViewModel> {

  // MARK: Lifecycle

  init(viewModel: VM, initiallyEnabled: Bool) {
    let owner = _ViewModelObservationOwner<VM>(initiallyEnabled: initiallyEnabled)
    self.owner = owner
    root = Task {
      await owner._visorRun(
        viewModel: viewModel
      )
    }
  }

  deinit {
    root.cancel()
  }

  // MARK: Internal

  let owner: _ViewModelObservationOwner<VM>

  // MARK: Private

  private let root: Task<Void, Never>

}
