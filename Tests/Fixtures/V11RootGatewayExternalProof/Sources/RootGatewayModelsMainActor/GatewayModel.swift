import Observation
import VISOR

nonisolated public struct GatewaySettings: Equatable {
  public var revision: Int

  public init(revision: Int = 0) {
    self.revision = revision
  }
}

@VISOR._ViewModelState
public final class MainActorGatewayState {
  public private(set) var count = 0
  public private(set) var settings = GatewaySettings()
  public private(set) var identifier: String

  public init(identifier: String = "initial") {
    self.identifier = identifier
  }

  public func setCountDirectly(_ value: Int) {
    count = value
  }

  public func incrementSettingsDirectly() {
    settings.revision += 1
  }
}
