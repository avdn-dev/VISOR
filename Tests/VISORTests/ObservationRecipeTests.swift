import Testing
import VISOR
import VISORObservation

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class ObservationRecipeLog {
  var entries: [String] = []

  deinit {}
}

@Suite("Observation recipe aggregation")
struct ObservationRecipeTests {
  @Test("One source becomes one lane in declaration order")
  @MainActor
  func oneSourceBecomesOneLane() async throws {
    let channel = ObservationChannel(7)
    let log = ObservationRecipeLog()
    let visitor = _ObservationRecipeVisitor()

    visitor.add(
      source: channel.source,
      projections: [{ value in log.entries.append("first projection \(value)") }],
      initialReactions: [{ value in log.entries.append("first reaction \(value)") }])
    visitor.add(
      source: channel.source,
      projections: [{ value in log.entries.append("second projection \(value)") }],
      initialReactions: [{ value in log.entries.append("second reaction \(value)") }])

    #expect(visitor.recipes.count == 1)

    let session = _ObservationSession(recipes: visitor.recipes)
    try await session._visorStart()

    #expect(log.entries == [
      "first projection 7",
      "second projection 7",
      "first reaction 7",
      "second reaction 7",
    ])
    #expect(channel.source._visorActiveSubscriptionCount == 1)

    await session._visorStop()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }
}
