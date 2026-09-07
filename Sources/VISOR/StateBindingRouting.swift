import SwiftUI

// MARK: - _StateBindingRoutes

/// Per-State action routes emitted by `@ViewModel` for `@StateBinding` cases.
/// Public only so downstream macro expansions can reference the runtime.
@MainActor
public final class _StateBindingRoutes<Root: AnyObject> {

  // MARK: Lifecycle

  public init(fields: Set<String>) {
    self.fields = fields
  }

  // MARK: Public

  /// Returns true only for the first connection. A State cannot be shared
  /// between action owners, even after the original owner has deinitialised.
  public func connect(owner: AnyObject) -> Bool {
    if isConnected {
      precondition(self.owner === owner, "A bound State cannot have multiple ViewModel owners")
      return false
    }
    self.owner = owner
    isConnected = true
    return true
  }

  public func register<Value>(
    _ field: _StateField<Root, Value>,
    action: @escaping @MainActor (Value) -> Void,
  ) {
    actions[field.identity] = action
  }

  // MARK: Internal

  func propose<Value>(_ value: Value, for field: _StateField<Root, Value>) -> Bool {
    guard fields.contains(field.name) else { return false }
    guard let action = actions[field.identity] as? @MainActor (Value) -> Void else {
      preconditionFailure("Use viewModel.bindableState to connect @StateBinding routes before writing an annotated selector")
    }
    action(value)
    return true
  }

  // MARK: Private

  private let fields: Set<String>
  private weak var owner: AnyObject?
  private var isConnected = false
  private var actions = [ObjectIdentifier: Any]()
}

extension ViewModel {
  /// Creates selector bindings over the model's stable State, connecting
  /// generated action routes once. Also supports authored initialisers.
  public var bindableState: Bindable<State> {
    _visorConnectStateBindings()
    return Bindable(state)
  }
}
