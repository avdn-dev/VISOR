import Observation
import os
import SwiftUI
import Testing
import VISOR

// MARK: - GatewayNonEquatableValue

struct GatewayNonEquatableValue { }

// MARK: - GatewayMutationError

enum GatewayMutationError: Error, Equatable {
  case expected
}

// MARK: - GatewayMutableValue

struct GatewayMutableValue: Equatable {
  var rawValue: Int

  mutating func leaveUnchanged() {
    rawValue += 0
  }

  mutating func incrementThenThrow() throws {
    rawValue += 1
    throw GatewayMutationError.expected
  }

  mutating func throwWithoutChanging() throws {
    throw GatewayMutationError.expected
  }
}

// MARK: - GatewayIdentityReference

final class GatewayIdentityReference { }

// MARK: - GatewayEquatableReference

final class GatewayEquatableReference: Equatable {

  // MARK: Lifecycle

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  // MARK: Internal

  var rawValue: Int

  static func ==(
    lhs: GatewayEquatableReference,
    rhs: GatewayEquatableReference,
  ) -> Bool {
    lhs.rawValue == rhs.rawValue
  }
}

// MARK: - GatewayState

@MainActor
@VISOR._ViewModelState
final class GatewayState {

  // MARK: Lifecycle

  init(identifier: String = "initial") {
    self.identifier = identifier
  }

  // MARK: Internal

  struct Settings: Equatable {
    var revision = 0
  }

  var count = 0
  var settings = Settings()
  var nonEquatableValue = GatewayNonEquatableValue()
  var mutableValue = GatewayMutableValue(rawValue: 0)
  var identityReference = GatewayIdentityReference()
  var equatableReference = GatewayEquatableReference(rawValue: 0)
  var identifier: String

  func incrementHiddenRevision() {
    hiddenRevision += 1
  }

  // MARK: Private

  private var hiddenRevision = 0

}

// MARK: - GatewayNotificationProbe

nonisolated private final class GatewayNotificationProbe: Sendable {

  // MARK: Internal

  var count: Int {
    storage.withLock { $0 }
  }

  func record() {
    storage.withLock { $0 += 1 }
  }

  // MARK: Private

  private let storage = OSAllocatedUnfairLock(initialState: 0)

}

@MainActor
private func installGatewayNotificationProbe<Value>(
  reading value: () -> Value
) -> GatewayNotificationProbe {
  let probe = GatewayNotificationProbe()
  withObservationTracking {
    _ = value()
  } onChange: {
    probe.record()
  }
  return probe
}

// MARK: - GatewayRecorder

@MainActor
private final class GatewayRecorder: _StateMutationRecorder {
  private(set) var fields = [String]()

  func record(
    fieldID _: ObjectIdentifier,
    fieldName: String,
    newValue _: Any,
  ) {
    fields.append(fieldName)
  }
}

// MARK: - StateGatewayTests

@Suite("V11 State gateway foundation")
@MainActor
struct StateGatewayTests {
  @Test
  func `Routed and direct writes share one generated accessor`() {
    let state = GatewayState(identifier: "fixture")
    let recorder = GatewayRecorder()
    state._visorMutationRecorder = recorder

    state.count = 1
    state.count = 1
    state[\.count] = 2
    state[\.settings].revision += 1

    @Bindable var boundState = state
    $boundState[\.count].wrappedValue = 3

    let bindableState = Bindable(state)
    bindableState[\.count].wrappedValue = 4

    state.incrementHiddenRevision()

    #expect(state.count == 4)
    #expect(state.settings.revision == 1)
    #expect(state.identifier == "fixture")
    #expect(
      recorder.fields == [
        "count",
        "count",
        "count",
        "settings",
        "count",
        "count",
        "hiddenRevision",
      ]
    )
  }

  @Test
  func `Generated State remains observable without a recorder`() {
    let state = GatewayState()
    let changeCount = OSAllocatedUnfairLock(initialState: 0)

    withObservationTracking {
      _ = state.count
    } onChange: {
      changeCount.withLock { $0 += 1 }
    }

    state.count = 1

    #expect(changeCount.withLock { $0 } == 1)
  }

  @Test
  func `Generated descriptor baselines use untracked backing storage`() {
    let state = GatewayState()
    let changeCount = OSAllocatedUnfairLock(initialState: 0)

    withObservationTracking {
      for field in GatewayState._visorAllFields {
        _ = field.read(from: state)
      }
    } onChange: {
      changeCount.withLock { $0 += 1 }
    }

    state.count = 1

    #expect(changeCount.withLock { $0 } == 0)
  }

  @Test
  func `Generated setters isolate fields and preserve value semantics`() {
    let state = GatewayState()

    var probe = installGatewayNotificationProbe {
      state.count
    }
    state.settings.revision += 1
    #expect(probe.count == 0)

    probe = installGatewayNotificationProbe {
      state.count
    }
    state.count = 1
    #expect(probe.count == 1)

    probe = installGatewayNotificationProbe {
      state.count
    }
    state.count = 1
    #expect(probe.count == 0)

    probe = installGatewayNotificationProbe {
      state.nonEquatableValue
    }
    state.nonEquatableValue = GatewayNonEquatableValue()
    #expect(probe.count == 1)
  }

  @Test
  func `Reference setters preserve identity and Equatable semantics`() {
    let state = GatewayState()

    var probe = installGatewayNotificationProbe {
      state.identityReference
    }
    state.identityReference = state.identityReference
    #expect(probe.count == 0)

    probe = installGatewayNotificationProbe {
      state.identityReference
    }
    state.identityReference = GatewayIdentityReference()
    #expect(probe.count == 1)

    probe = installGatewayNotificationProbe {
      state.equatableReference
    }
    state.equatableReference = GatewayEquatableReference(rawValue: 0)
    #expect(probe.count == 0)

    probe = installGatewayNotificationProbe {
      state.equatableReference
    }
    state.equatableReference = GatewayEquatableReference(rawValue: 1)
    #expect(probe.count == 1)
  }

  @Test
  func `Modify access notifies on normal and throwing completion`() {
    let state = GatewayState()

    var probe = installGatewayNotificationProbe {
      state.mutableValue
    }
    state.mutableValue.rawValue += 1
    #expect(probe.count == 1)
    #expect(state.mutableValue.rawValue == 1)

    probe = installGatewayNotificationProbe {
      state.mutableValue
    }
    state.mutableValue.leaveUnchanged()
    #expect(probe.count == 1)
    #expect(state.mutableValue.rawValue == 1)

    probe = installGatewayNotificationProbe {
      state.mutableValue
    }
    #expect(throws: GatewayMutationError.expected) {
      try state.mutableValue.incrementThenThrow()
    }
    #expect(probe.count == 1)
    #expect(state.mutableValue.rawValue == 2)

    probe = installGatewayNotificationProbe {
      state.mutableValue
    }
    #expect(throws: GatewayMutationError.expected) {
      try state.mutableValue.throwWithoutChanging()
    }
    #expect(probe.count == 1)
    #expect(state.mutableValue.rawValue == 2)
  }
}
