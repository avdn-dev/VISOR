import Observation
import Testing
import VISOR
import VISORTesting

enum ParityError: Error, Equatable {
  case expected
}

struct ParityNonEquatableValue {
  var rawValue: Int
}

struct ParityMutableValue: Equatable {
  var rawValue: Int

  mutating func leaveUnchanged() {
    rawValue += 0
  }

  mutating func incrementThenThrow() throws {
    rawValue += 1
    throw ParityError.expected
  }

  mutating func throwWithoutChanging() throws {
    throw ParityError.expected
  }
}

protocol ParityClassBound: AnyObject {
  var rawValue: Int { get }
}

final class ParityIdentityReference: ParityClassBound {
  var rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }
}

final class ParityEquatableReference: Equatable {
  var rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  static func == (
    lhs: ParityEquatableReference,
    rhs: ParityEquatableReference
  ) -> Bool {
    lhs.rawValue == rhs.rawValue
  }
}

@MainActor
@Observable
private final class ObservationParityOracle {
  var equatableValue = 0
  var nonEquatableValue = ParityNonEquatableValue(rawValue: 0)
  var mutableValue = ParityMutableValue(rawValue: 0)
  var identityReference = ParityIdentityReference(rawValue: 0)
  var equatableReference = ParityEquatableReference(rawValue: 0)
  var optionalIdentityReference: ParityIdentityReference?
  var optionalEquatableReference: ParityEquatableReference?
}

@MainActor
@Observable
@ViewModel
final class ObservationParityViewModel {
  final class State {
    var equatableValue = 0
    var nonEquatableValue = ParityNonEquatableValue(rawValue: 0)
    var mutableValue = ParityMutableValue(rawValue: 0)
    var identityReference = ParityIdentityReference(rawValue: 0)
    var equatableReference = ParityEquatableReference(rawValue: 0)
    var optionalIdentityReference: ParityIdentityReference?
    var optionalEquatableReference: ParityEquatableReference?
    var existentialReference: any ParityClassBound =
      ParityIdentityReference(rawValue: 0)
    var anyObjectReference: AnyObject =
      ParityIdentityReference(rawValue: 0)
    var anyValue: Any = 0
    var referenceContainer: [ParityIdentityReference] = []
  }

  let state = State()
}

@MainActor
private final class NotificationProbe {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

@MainActor
private func installNotificationProbe<Value>(
  reading value: () -> Value
) -> NotificationProbe {
  let probe = NotificationProbe()

  withObservationTracking {
    _ = value()
  } onChange: {
    MainActor.assumeIsolated {
      probe.record()
    }
  }

  return probe
}

private func valueBeforeSetter<Value>(_ value: Value) throws -> Value {
  _ = value
  throw ParityError.expected
}

@MainActor
private func expectDirectReferenceRejection(
  fieldName: String,
  operation: () -> Void
) {
  withKnownIssue(
    "strict history rejects the outer reference for '\(fieldName)'",
    {
      operation()
    },
    matching: { issue in
      issue.comments.contains { comment in
        comment.rawValue ==
          "Strict State history does not support an outer reference value for field '\(fieldName)'"
      }
    })
}

@Suite("Generated State Observation parity")
struct ObservationParityTests {
  @Test
  @MainActor
  func `Value setters match the Observable oracle`() {
    let oracle = ObservationParityOracle()
    let generated = ObservationParityViewModel()

    var oracleProbe = installNotificationProbe {
      oracle.equatableValue
    }
    var generatedProbe = installNotificationProbe {
      generated.state.equatableValue
    }
    oracle.equatableValue = 1
    generated.state.equatableValue = 1
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.equatableValue
    }
    generatedProbe = installNotificationProbe {
      generated.state.equatableValue
    }
    oracle.equatableValue = 1
    generated.state.equatableValue = 1
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.nonEquatableValue
    }
    generatedProbe = installNotificationProbe {
      generated.state.nonEquatableValue
    }
    oracle.nonEquatableValue = .init(rawValue: 0)
    generated.state.nonEquatableValue = .init(rawValue: 0)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)
  }

  @Test
  @MainActor
  func `Reference and optional setters match the Observable oracle`() {
    let oracle = ObservationParityOracle()
    let generated = ObservationParityViewModel()

    var oracleProbe = installNotificationProbe {
      oracle.identityReference
    }
    var generatedProbe = installNotificationProbe {
      generated.state.identityReference
    }
    oracle.identityReference = oracle.identityReference
    generated.state.identityReference = generated.state.identityReference
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.identityReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.identityReference
    }
    oracle.identityReference = .init(rawValue: 0)
    generated.state.identityReference = .init(rawValue: 0)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.equatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.equatableReference
    }
    oracle.equatableReference = .init(rawValue: 0)
    generated.state.equatableReference = .init(rawValue: 0)
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.equatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.equatableReference
    }
    oracle.equatableReference = .init(rawValue: 1)
    generated.state.equatableReference = .init(rawValue: 1)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalIdentityReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalIdentityReference
    }
    oracle.optionalIdentityReference = nil
    generated.state.optionalIdentityReference = nil
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalIdentityReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalIdentityReference
    }
    oracle.optionalIdentityReference = .init(rawValue: 0)
    generated.state.optionalIdentityReference = .init(rawValue: 0)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    let oracleOptionalIdentityReference = oracle.optionalIdentityReference
    let generatedOptionalIdentityReference =
      generated.state.optionalIdentityReference
    oracleProbe = installNotificationProbe {
      oracle.optionalIdentityReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalIdentityReference
    }
    oracle.optionalIdentityReference = oracleOptionalIdentityReference
    generated.state.optionalIdentityReference =
      generatedOptionalIdentityReference
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalIdentityReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalIdentityReference
    }
    oracle.optionalIdentityReference = nil
    generated.state.optionalIdentityReference = nil
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalEquatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalEquatableReference
    }
    oracle.optionalEquatableReference = nil
    generated.state.optionalEquatableReference = nil
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalEquatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalEquatableReference
    }
    oracle.optionalEquatableReference = .init(rawValue: 0)
    generated.state.optionalEquatableReference = .init(rawValue: 0)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalEquatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalEquatableReference
    }
    oracle.optionalEquatableReference = .init(rawValue: 0)
    generated.state.optionalEquatableReference = .init(rawValue: 0)
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.optionalEquatableReference
    }
    generatedProbe = installNotificationProbe {
      generated.state.optionalEquatableReference
    }
    oracle.optionalEquatableReference = .init(rawValue: 1)
    generated.state.optionalEquatableReference = .init(rawValue: 1)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)
  }

  @Test
  @MainActor
  func `Modify completion and unwind match the Observable oracle`() {
    let oracle = ObservationParityOracle()
    let generated = ObservationParityViewModel()

    var oracleProbe = installNotificationProbe {
      oracle.mutableValue
    }
    var generatedProbe = installNotificationProbe {
      generated.state.mutableValue
    }
    oracle.mutableValue.rawValue += 1
    generated.state.mutableValue.rawValue += 1
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.mutableValue
    }
    generatedProbe = installNotificationProbe {
      generated.state.mutableValue
    }
    oracle.mutableValue.leaveUnchanged()
    generated.state.mutableValue.leaveUnchanged()
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.mutableValue
    }
    generatedProbe = installNotificationProbe {
      generated.state.mutableValue
    }
    #expect(throws: ParityError.expected) {
      try oracle.mutableValue.incrementThenThrow()
    }
    #expect(throws: ParityError.expected) {
      try generated.state.mutableValue.incrementThenThrow()
    }
    #expect(oracle.mutableValue.rawValue == 2)
    #expect(generated.state.mutableValue == oracle.mutableValue)
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)

    oracleProbe = installNotificationProbe {
      oracle.mutableValue
    }
    generatedProbe = installNotificationProbe {
      generated.state.mutableValue
    }
    #expect(throws: ParityError.expected) {
      try oracle.mutableValue.throwWithoutChanging()
    }
    #expect(throws: ParityError.expected) {
      try generated.state.mutableValue.throwWithoutChanging()
    }
    #expect(oracleProbe.count == 1)
    #expect(generatedProbe.count == oracleProbe.count)
  }

  @Test
  @MainActor
  func `A throwing right-hand side enters neither setter`() {
    let oracle = ObservationParityOracle()
    let generated = ObservationParityViewModel()
    let oracleProbe = installNotificationProbe {
      oracle.equatableValue
    }
    let generatedProbe = installNotificationProbe {
      generated.state.equatableValue
    }

    #expect(throws: ParityError.expected) {
      oracle.equatableValue = try valueBeforeSetter(1)
    }
    #expect(throws: ParityError.expected) {
      generated.state.equatableValue = try valueBeforeSetter(1)
    }

    #expect(oracle.equatableValue == 0)
    #expect(generated.state.equatableValue == oracle.equatableValue)
    #expect(oracleProbe.count == 0)
    #expect(generatedProbe.count == oracleProbe.count)
  }

  @Test
  @MainActor
  func `Observable re-entrant callback sees the pre-mutation value`() {
    let oracle = ObservationParityOracle()
    var oracleCallbackValues: [Int] = []
    var oracleCallbackCount = 0

    withObservationTracking {
      _ = oracle.equatableValue
    } onChange: {
      MainActor.assumeIsolated {
        oracleCallbackCount += 1
        guard oracleCallbackCount == 1 else { return }
        oracleCallbackValues.append(oracle.equatableValue)
        oracle.equatableValue = 2
      }
    }
    oracle.equatableValue = 1

    #expect(oracleCallbackValues == [0])
    #expect(oracleCallbackCount == 2)
    #expect(oracle.equatableValue == 1)
  }

  @Test
  @MainActor
  func `Generated re-entrant commits complete inside out`() async throws {
    let generated = ObservationParityViewModel()
    var generatedCallbackValues: [Int] = []
    var generatedCallbackCount = 0

    try await observe(generated) { test in
      withObservationTracking {
        _ = generated.state.equatableValue
      } onChange: {
        MainActor.assumeIsolated {
          generatedCallbackCount += 1
          guard generatedCallbackCount == 1 else { return }
          generatedCallbackValues.append(generated.state.equatableValue)
          generated.state.equatableValue = 2
        }
      }

      await test.perform {
        generated.state.equatableValue = 1
      }

      #expect(generatedCallbackValues == [0])
      #expect(generatedCallbackCount == 2)
      #expect(generated.state.equatableValue == 1)
      #expect(test._rawCommitFieldNames == [
        "equatableValue",
        "equatableValue",
      ])
      #expect(test._rawCommitCount(\.equatableValue) == 2)
      test.expect(\.equatableValue, hasExactChanges: [2, 1])
    }
  }

  @Test
  @MainActor
  func `Raw journals record completed access independently of notification`() async throws {
    let generated = ObservationParityViewModel()

    try await observe(generated) { test in
      await test.perform {
        generated.state.equatableValue = 0
      }
      #expect(test._rawCommitCount(\.equatableValue) == 1)
      test.expect(\.equatableValue, hasExactChanges: [])

      await test.perform {
        generated.state.nonEquatableValue = .init(rawValue: 0)
      }
      #expect(test._rawCommitCount(\.nonEquatableValue) == 1)
      test.expect(
        \.nonEquatableValue,
        alwaysSatisfies: { $0.rawValue == 0 })

      await test.perform {
        generated.state.mutableValue.leaveUnchanged()
      }
      #expect(test._rawCommitCount(\.mutableValue) == 1)
      test.expect(\.mutableValue, hasExactChanges: [])

      await test.perform {
        generated.state.mutableValue.rawValue += 1
      }
      #expect(test._rawCommitCount(\.mutableValue) == 1)
      test.expect(
        \.mutableValue,
        hasExactChanges: [.init(rawValue: 1)])

      await #expect(throws: ParityError.expected) {
        try await test.perform {
          try generated.state.mutableValue.incrementThenThrow()
        }
      }
      #expect(test._rawCommitCount(\.mutableValue) == 1)
      test.expect(
        \.mutableValue,
        hasExactChanges: [.init(rawValue: 2)])

      await #expect(throws: ParityError.expected) {
        try await test.perform {
          try generated.state.mutableValue.throwWithoutChanging()
        }
      }
      #expect(test._rawCommitCount(\.mutableValue) == 1)
      test.expect(\.mutableValue, hasExactChanges: [])

      await #expect(throws: ParityError.expected) {
        try await test.perform {
          generated.state.equatableValue = try valueBeforeSetter(1)
        }
      }
      #expect(test._rawCommitCount(\.equatableValue) == 0)
      test.expect(\.equatableValue, hasExactChanges: [])
    }
  }

  @Test
  @MainActor
  func `Strict matchers reject every outer-reference representation`() async throws {
    let generated = ObservationParityViewModel()
    var predicateEvaluations = 0

    try await observe(generated) { test in
      await test.perform {}

      expectDirectReferenceRejection(fieldName: "equatableReference") {
        test.expect(\.equatableReference, hasExactChanges: [])
      }
      expectDirectReferenceRejection(fieldName: "equatableReference") {
        test.expect(
          \.equatableReference,
          alwaysSatisfies: { _ in
            predicateEvaluations += 1
            return true
          })
      }
      expectDirectReferenceRejection(fieldName: "anyObjectReference") {
        test.expect(
          \.anyObjectReference,
          alwaysSatisfies: { _ in
            predicateEvaluations += 1
            return true
          })
      }
      expectDirectReferenceRejection(fieldName: "existentialReference") {
        test.expect(
          \.existentialReference,
          alwaysSatisfies: { _ in
            predicateEvaluations += 1
            return true
          })
      }
      #expect(predicateEvaluations == 0)

      await test.perform {
        generated.state.anyValue = ParityIdentityReference(rawValue: 1)
      }
      expectDirectReferenceRejection(fieldName: "anyValue") {
        test.expect(
          \.anyValue,
          alwaysSatisfies: { _ in
            predicateEvaluations += 1
            return true
          })
      }
      #expect(predicateEvaluations == 0)

      await test.perform {}
      expectDirectReferenceRejection(fieldName: "anyValue") {
        test.expect(
          \.anyValue,
          alwaysSatisfies: { _ in
            predicateEvaluations += 1
            return true
          })
      }
      #expect(predicateEvaluations == 0)

      let stableReference = ParityIdentityReference(rawValue: 2)
      await test.perform {
        generated.state.optionalIdentityReference = stableReference
        generated.state.referenceContainer = [stableReference]
      }

      // Swift cannot prove transitive value semantics. Optional and container
      // histories therefore remain accepted only under the caller's promise
      // that retained values will stay historically stable.
      test.expect(
        \.optionalIdentityReference,
        alwaysSatisfies: { value in
          value == nil || value === stableReference
        })
      test.expect(
        \.referenceContainer,
        alwaysSatisfies: { values in
          values.isEmpty || values.first === stableReference
        })
    }
  }
}
