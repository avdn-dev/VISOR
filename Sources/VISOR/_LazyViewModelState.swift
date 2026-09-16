import SwiftUI

/// Retains generated view state without expanding a property macro inside a
/// member macro. State retains SwiftUI's native initialisation behaviour.
@MainActor
@propertyWrapper
public struct _LazyViewModelState<Value: _LazyViewModelStateValue>: DynamicProperty {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public var wrappedValue: Value {
    value
  }

  // MARK: Private

  @State private var value = Value()
}
