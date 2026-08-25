import Observation
import Testing
import VISOR
import VISORObservation

// MARK: - RecipeSnapshot

public struct RecipeSnapshot: Sendable {
  public init(count: Int, label: String) {
    self.count = count
    self.label = label
  }

  public let count: Int
  public let label: String

}

// MARK: - RecipeService

@MainActor
public final class RecipeService {

  // MARK: Lifecycle

  public init(_ snapshot: RecipeSnapshot) {
    channel = ObservationChannel(snapshot)
  }

  deinit { }

  // MARK: Public

  public var source: ObservationSource<RecipeSnapshot> {
    channel.source
  }

  // MARK: Private

  private let channel: ObservationChannel<RecipeSnapshot>

}

// MARK: - SourceRecipeViewModel

@MainActor
@Observable
@ViewModel
public final class SourceRecipeViewModel {

  // MARK: Lifecycle

  public init(service: RecipeService) {
    self.service = service
    aliasService = service
  }

  deinit { }

  // MARK: Public

  public final class State {

    // MARK: Lifecycle

    public init() { }

    deinit { }

    // MARK: Public

    @Bound(
      source: \SourceRecipeViewModel.service.source,
      selecting: \RecipeSnapshot.count,
    )
    public private(set) var count = 0

    @Bound(
      source: \SourceRecipeViewModel.aliasService.source,
      selecting: \RecipeSnapshot.label,
    )
    public private(set) var label = "unprojected"

    public private(set) var reactedCount = -1
    public private(set) var labelSeenByReaction = "unreacted"

  }

  public let state = State()
  public let service: RecipeService
  public let aliasService: RecipeService

  // MARK: Private

  @Reaction(
    source: \SourceRecipeViewModel.service.source,
    selecting: \RecipeSnapshot.count,
  )
  private func countChanged(_ count: Int) {
    updateState(\.reactedCount, to: count)
    updateState(\.labelSeenByReaction, to: state.label)
  }

}

// MARK: - ViewModelV11RuntimeTests

@Suite("V11 ViewModel runtime expansion")
@MainActor
struct ViewModelV11RuntimeTests {
  @Test
  func `Generated recipes merge aliased sources and project before reacting`() async throws {
    let service = RecipeService(RecipeSnapshot(count: 7, label: "ready"))
    let viewModel = SourceRecipeViewModel(service: service)
    let recipes = viewModel._visorMakeObservationRecipes()

    #expect(recipes.count == 1)

    let session = _ObservationSession(recipes: recipes)
    try await session._visorStart()

    #expect(viewModel.state.count == 7)
    #expect(viewModel.state.label == "ready")
    #expect(viewModel.state.reactedCount == 7)
    #expect(viewModel.state.labelSeenByReaction == "ready")
    #expect(service.source._visorActiveSubscriptionCount == 1)

    await session._visorStop()
    #expect(service.source._visorActiveSubscriptionCount == 0)
  }
}
