import Foundation
import Observation
import os
import SwiftUI
import Testing
import VISOR
import VISORObservation
import VISORTesting

// MARK: - RouterPathObservationTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct RouterPathObservationTests {
  @Test
  func `A new Router exposes one stable empty path source`() {
    // Given
    let router = Router<TestScene>()

    // When
    let first = router.navigationPathValues
    let second = router.navigationPathValues

    // Then
    #expect(first.currentSnapshot().isEmpty)
    #expect(router.navigationPath.isEmpty)
    #expect(first._visorIdentity == second._visorIdentity)
  }

  @Test
  func `Iteration starts with the current path and publishes an empty path without ending`() async throws {
    // Given
    let router = Router<TestScene>()
    let source = router.navigationPathValues
    router.navigationPath = [.nested]

    // When
    let values = source.makeAsyncIterator()
    let baseline = try await values.next()

    // Then
    #expect(baseline == [.nested])

    // When
    router.navigationPath = []

    // Then
    #expect(source.currentSnapshot().isEmpty)
    #expect(try await values.next() == [])

    // When
    router.navigationPath = [.detail(id: "after-clear")]

    // Then
    #expect(try await values.next() == [.detail(id: "after-clear")])
  }

  @Test
  func `SwiftUI path binding writes preserve Apple Observation and publish synchronously`() {
    // Given
    let router = Router<TestScene>()
    router.navigationPath = [.nested, .detail(id: "1")]
    let source = router.navigationPathValues
    let changes = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = router.navigationPath
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    @Bindable var bindableRouter = router

    // When
    $bindableRouter.navigationPath.wrappedValue.removeLast()

    // Then
    #expect(changes.withLock { $0 } == 1)
    #expect(router.navigationPath == [.nested])
    #expect(source.currentSnapshot() == [.nested])
  }

  @Test
  func `In-place path edits publish without changing retained snapshots`() {
    // Given
    let router = Router<TestScene>()
    router.navigationPath = [.nested]
    let source = router.navigationPathValues
    let previousPath = source.currentSnapshot()

    // When
    router.navigationPath.append(.detail(id: "1"))

    // Then
    #expect(source.currentSnapshot() == [.nested, .detail(id: "1")])
    #expect(previousPath == [.nested])

    // When
    router.navigationPath[0] = .detail(id: "replacement")

    // Then
    #expect(source.currentSnapshot() == [.detail(id: "replacement"), .detail(id: "1")])
    #expect(previousPath == [.nested])
  }

  @Test
  func `Repeated path assignments publish revisions without notifying unchanged SwiftUI state`() async throws {
    // Given
    let router = Router<TestScene>()
    router.navigationPath = [.nested]
    let values = router.navigationPathValues.makeAsyncIterator()
    let changes = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = router.navigationPath
    } onChange: {
      changes.withLock { $0 += 1 }
    }

    // When
    let baseline = try await values.next()

    // Then
    #expect(baseline == [.nested])

    // When
    router.navigationPath = [.nested]

    // Then
    #expect(try await values.next() == [.nested])
    #expect(changes.withLock { $0 } == 0)

    // When
    router.navigationPath = []

    // Then
    #expect(try await values.next() == [])
    #expect(changes.withLock { $0 } == 1)
  }

  @Test
  func `Busy consumers receive the latest path without replaying intermediate destinations`() async throws {
    // Given
    let router = Router<TestScene>()
    let values = router.navigationPathValues.makeAsyncIterator()

    // When
    let baseline = try await values.next()

    // Then
    #expect(baseline == [])

    // When
    router.navigationPath = [.nested]
    router.navigationPath = []
    router.navigationPath = [.detail(id: "latest")]

    // Then
    #expect(try await values.next() == [.detail(id: "latest")])
  }

  @Test
  func `Push and pop publish only on the active Router node`() {
    // Given
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    let modal = child.childRouter()
    root.navigationPath = [.detail(id: "root")]
    child.navigationPath = [.detail(id: "child")]
    modal.activate()

    // When
    let accepted = root.push(.nested)

    // Then
    #expect(accepted)
    #expect(modal.navigationPathValues.currentSnapshot() == [.nested])
    #expect(child.navigationPathValues.currentSnapshot() == [.detail(id: "child")])
    #expect(root.navigationPathValues.currentSnapshot() == [.detail(id: "root")])

    // When
    let popped = root.popToRoot()

    // Then
    #expect(popped)
    #expect(modal.navigationPathValues.currentSnapshot().isEmpty)
    #expect(child.navigationPathValues.currentSnapshot() == [.detail(id: "child")])
    #expect(root.navigationPathValues.currentSnapshot() == [.detail(id: "root")])
  }

  @Test
  func `Selecting and pushing publishes the destination branch and preserves duplicate pushes`() {
    // Given
    let root = Router<TestScene>.preview(root: .home)
    let home = root.childRouter(for: .home)
    let settings = root.childRouter(for: .settings)
    settings.navigationPath = [.nested]

    // When
    home.selectAndPush(root: .settings, destination: .nested)

    // Then
    #expect(root.selectedRootValues.currentSnapshot() == .settings)
    #expect(settings.navigationPathValues.currentSnapshot() == [.nested, .nested])
    #expect(root.navigationPathValues.currentSnapshot().isEmpty)
    #expect(home.navigationPathValues.currentSnapshot().isEmpty)

    // When
    root.select(root: .home)

    // Then
    #expect(settings.navigationPathValues.currentSnapshot() == [.nested, .nested])
    #expect(root.childRouter(for: .settings) === settings)
  }

  @Test
  func `Only accepted deep links publish a path`() throws {
    // Given
    let router = Router<TestScene>()
    let source = router.navigationPathValues
    try router.configureDeepLinks(scheme: "test", parsers: [
      .matching(components: ["detail"], destination: .push(.nested))
    ])
    let url = try #require(URL(string: "test://detail"))

    // When
    let inactiveOutcome = router.openDeepLink(url)

    // Then
    #expect(inactiveOutcome == .inactive)
    #expect(source.currentSnapshot().isEmpty)

    // When
    router.activate()
    let acceptedOutcome = router.openDeepLink(url)

    // Then
    #expect(acceptedOutcome == .handled(.push(.nested)))
    #expect(source.currentSnapshot() == [.nested])
  }

  @Test
  func `Bindings and reactions share the path source and fence navigation changes`() async throws {
    // Given
    let router = Router<TestScene>()
    router.activate()
    let model = RouterPathObservationModel(router: router)

    // When
    try await observe(model) { test in
      // Then
      #expect(model.state.path.isEmpty)
      #expect(model.state.reactedPath.isEmpty)
      #expect(model.state.reactionCount == 1)
      #expect(router.navigationPathValues._visorActiveSubscriptionCount == 1)

      // When
      let accepted = try await test.perform { router.push(.nested) }

      // Then
      #expect(accepted)
      test.expect(\.path, hasExactChanges: [[.nested]])
      test.expect(\.reactedPath, hasExactChanges: [[.nested]])
      test.expect(\.reactionCount, hasExactChanges: [2])

      // When
      let popped = try await test.perform { router.popToRoot() }

      // Then
      #expect(popped)
      test.expect(\.path, hasExactChanges: [[]])
      test.expect(\.reactedPath, hasExactChanges: [[]])
      test.expect(\.reactionCount, hasExactChanges: [3])
    }
    #expect(router.navigationPathValues._visorActiveSubscriptionCount == 0)
  }

  @Test
  func `Restarting observation reconciles the latest path without replaying inactive edits`() async throws {
    // Given
    let router = Router<TestScene>()
    let model = RouterPathObservationModel(router: router)

    // When
    try await observe(model) { _ in
      // Then
      #expect(model.state.path.isEmpty)
      #expect(model.state.reactionCount == 1)
    }

    // When
    router.navigationPath = [.nested]
    router.navigationPath = [.detail(id: "latest")]

    // Then
    #expect(model.state.path.isEmpty)
    #expect(router.navigationPathValues._visorActiveSubscriptionCount == 0)

    // When
    try await observe(model) { _ in
      // Then
      #expect(model.state.path == [.detail(id: "latest")])
      #expect(model.state.reactedPath == [.detail(id: "latest")])
      #expect(model.state.reactionCount == 2)
    }
  }

  @Test
  func `Retaining a path source does not retain its Router`() throws {
    // Given
    var router: Router<TestScene>? = Router()
    router?.navigationPath = [.nested]
    weak let releasedRouter = router
    let source = try #require(router).navigationPathValues

    // When
    router = nil

    // Then
    #expect(releasedRouter == nil)
    #expect(source.currentSnapshot() == [.nested])
  }
}
