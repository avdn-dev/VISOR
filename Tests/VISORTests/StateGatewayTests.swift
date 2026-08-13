import Observation
import SwiftUI
import Testing
import VISOR
import os

struct GatewayNonEquatableValue {
  var rawValue: Int
}

enum GatewayMutationError: Error, Equatable {
  case expected
}

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

final class GatewayIdentityReference {
  var rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }
}

final class GatewayEquatableReference: Equatable {
  var rawValue: Int

  init(rawValue: Int) {
    self.rawValue = rawValue
  }

  static func == (
    lhs: GatewayEquatableReference,
    rhs: GatewayEquatableReference
  ) -> Bool {
    lhs.rawValue == rhs.rawValue
  }
}

@MainActor
@VISOR._ViewModelState
final class GatewayState {
  var count = 0
  var settings = Settings()
  var nonEquatableValue = GatewayNonEquatableValue(rawValue: 0)
  var mutableValue = GatewayMutableValue(rawValue: 0)
  var identityReference = GatewayIdentityReference(rawValue: 0)
  var equatableReference = GatewayEquatableReference(rawValue: 0)
  var identifier: String
  private var hiddenRevision = 0

  struct Settings: Equatable {
    var revision = 0
  }

  init(identifier: String = "initial") {
    self.identifier = identifier
  }

  func incrementHiddenRevision() {
    hiddenRevision += 1
  }
}

nonisolated private final class GatewayNotificationProbe: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: 0)

  var count: Int {
    storage.withLock { $0 }
  }

  func record() {
    storage.withLock { $0 += 1 }
  }
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

@MainActor
private final class GatewayRecorder: _StateMutationRecorder {
  private(set) var fields: [String] = []

  func record(
    fieldID _: ObjectIdentifier,
    fieldName: String,
    oldValue _: Any,
    newValue _: Any
  ) {
    fields.append(fieldName)
  }
}

@Suite("V11 State gateway foundation")
@MainActor
struct StateGatewayTests {
  @Test("Routed and direct writes share one generated accessor")
  func routedAndDirectWrites() {
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
      ])
  }

  @Test("Generated State remains observable without a recorder")
  func observationWithoutRecorder() {
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

  @Test("Generated descriptor baselines use untracked backing storage")
  func untrackedDescriptorReads() {
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

  @Test("Generated setters isolate fields and preserve value semantics")
  func setterObservationParity() {
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
    state.nonEquatableValue = GatewayNonEquatableValue(rawValue: 0)
    #expect(probe.count == 1)
  }

  @Test("Reference setters preserve identity and Equatable semantics")
  func referenceSetterObservationParity() {
    let state = GatewayState()

    var probe = installGatewayNotificationProbe {
      state.identityReference
    }
    state.identityReference = state.identityReference
    #expect(probe.count == 0)

    probe = installGatewayNotificationProbe {
      state.identityReference
    }
    state.identityReference = GatewayIdentityReference(rawValue: 0)
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

  @Test("Modify access notifies on normal and throwing completion")
  func modifyObservationParity() {
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
