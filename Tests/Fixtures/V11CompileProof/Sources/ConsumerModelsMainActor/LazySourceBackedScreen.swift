import ConsumerServices
import SwiftUI
import VISOR

/// Downstream compile proof under MainActor-by-default consumer settings.
@MainActor
@LazyViewModel(
  SourceBackedViewModel.self,
  observationPolicy: .pauseWhenInactive)
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
