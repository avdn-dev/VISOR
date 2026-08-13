import ConsumerServices
import SwiftUI
import VISOR

/// Downstream compile proof for the generated Stage E SwiftUI owner.
@MainActor
@LazyViewModel(
  SourceBackedViewModel.self,
  observationPolicy: .pauseInBackground)
public struct LazySourceBackedScreen: View {
  private let makeViewModel: @MainActor () -> SourceBackedViewModel

  public init(
    service: SyncingService,
    statusService: StatusService = StatusService()
  ) {
    makeViewModel = {
      SourceBackedViewModel(
        service: service,
        statusService: statusService)
    }
  }

  public var content: some View {
    Text("Revision \(state.revision)")
  }
}
