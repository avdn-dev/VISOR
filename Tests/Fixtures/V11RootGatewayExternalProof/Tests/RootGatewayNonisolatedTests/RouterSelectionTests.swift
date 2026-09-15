import SwiftUI
import Testing
import VISOR
import VISORObservation

// MARK: - RouterSelectionTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct RouterSelectionTests {

  // MARK: Internal

  @Test
  func `Router selection is observable across the public package boundary`() async throws {
    // Given
    let router = Router<Scene>.preview(root: .home)
    let source = selectionSource(for: router)
    let values = source.makeAsyncIterator()
    @Bindable var bindableRouter = router

    // When
    let baseline = try await values.next()

    // Then
    #expect(baseline == .some(.home))

    // When
    $bindableRouter.selectedRoot.wrappedValue = .settings

    // Then
    #expect(source.currentSnapshot() == .settings)
    #expect(try await values.next() == .some(.settings))

    // When
    router.selectedRoot = nil

    // Then
    #expect(source.currentSnapshot() == nil)
    #expect(try await values.next() == .some(nil))
  }

  @Test
  func `Router paths are observable across the public package boundary`() async throws {
    // Given
    let root = Router<Scene>.preview(root: .home)
    let child = root.childRouter(for: .home)
    let source = pathSource(for: child)
    let values = source.makeAsyncIterator()
    @Bindable var bindableRouter = child

    // When
    let baseline = try await values.next()

    // Then
    #expect(baseline == [])

    // When
    child.push(.detail)

    // Then
    #expect(source.currentSnapshot() == [.detail])
    #expect(try await values.next() == [.detail])
    #expect(root.navigationPathValues.currentSnapshot().isEmpty)

    // When
    $bindableRouter.navigationPath.wrappedValue = []

    // Then
    #expect(source.currentSnapshot().isEmpty)
    #expect(try await values.next() == [])
  }

  // MARK: Private

  private nonisolated enum Scene: NavigationScene {
    nonisolated enum Push: PushDestination {
      case detail
    }

    nonisolated enum Root: RootDestination {
      case home
      case settings
    }
  }

  /// A source can be obtained and read without inheriting the Router's actor.
  private nonisolated func selectionSource(
    for router: Router<Scene>
  ) -> ObservationSource<Scene.Root?> {
    router.selectedRootValues
  }

  private nonisolated func pathSource(
    for router: Router<Scene>
  ) -> ObservationSource<[Scene.Push]> {
    router.navigationPathValues
  }
}
