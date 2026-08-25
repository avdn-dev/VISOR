import Observation
import VISOR

// MARK: - GatewaySettings

nonisolated public struct GatewaySettings: Equatable {
  public init(revision: Int = 0) {
    self.revision = revision
  }

  public var revision: Int

}

// MARK: - MainActorGatewayState

@VISOR._ViewModelState
public final class MainActorGatewayState {

  // MARK: Lifecycle

  public init(identifier: String = "initial") {
    self.identifier = identifier
  }

  // MARK: Public

  public private(set) var count = 0
  public private(set) var settings = GatewaySettings()
  public private(set) var identifier: String

  public func setCountDirectly(_ value: Int) {
    count = value
  }

  public func incrementSettingsDirectly() {
    settings.revision += 1
  }
}
