import Observation
import SwiftUI

private final class StateFieldIdentity {}

@MainActor
public struct _StateField<Root: AnyObject, Value> {
  private let identityStorage: StateFieldIdentity
  private let keyPath: ReferenceWritableKeyPath<Root, Value>

  package let name: String

  public init(
    _ name: String,
    keyPath: ReferenceWritableKeyPath<Root, Value>
  ) {
    identityStorage = StateFieldIdentity()
    self.keyPath = keyPath
    self.name = name
  }

  package var identity: ObjectIdentifier {
    ObjectIdentifier(identityStorage)
  }

  package var isDirectReference: Bool {
    Value.self is AnyObject.Type
  }

  package func read(from root: Root) -> Value {
    root[keyPath: keyPath]
  }

  package func write(_ value: Value, to root: Root) {
    root[keyPath: keyPath] = value
  }
}

@MainActor
public struct _AnyStateField<Root: AnyObject> {
  private let readValue: (Root) -> Any

  package let identity: ObjectIdentifier
  package let name: String

  public init<Value>(
    _ field: _StateField<Root, Value>,
    untrackedRead: @escaping (Root) -> Value
  ) {
    identity = field.identity
    name = field.name
    readValue = { root in untrackedRead(root) }
  }

  package func read(from root: Root) -> Any {
    readValue(root)
  }
}

@MainActor
public protocol _StateMutationRecorder: AnyObject {
  func record(
    fieldID: ObjectIdentifier,
    fieldName: String,
    oldValue: Any,
    newValue: Any)
}

@MainActor
public protocol _ViewModelState: AnyObject {
  associatedtype _VISORSelectors

  static var _visorSelectors: _VISORSelectors { get }
  static var _visorAllFields: [_AnyStateField<Self>] { get }
  var _visorMutationRecorder: (any _StateMutationRecorder)? { get set }
}

extension _ViewModelState {
  public subscript<Value>(
    _ selection: KeyPath<_VISORSelectors, _StateField<Self, Value>>
  ) -> Value {
    get {
      let field = Self._visorSelectors[keyPath: selection]
      return field.read(from: self)
    }
    set {
      let field = Self._visorSelectors[keyPath: selection]
      field.write(newValue, to: self)
    }
  }

  public func _visorRecordMutation<Value>(
    _ field: _StateField<Self, Value>,
    oldValue: Value,
    newValue: Value
  ) {
    guard let recorder = _visorMutationRecorder else { return }

    recorder.record(
      fieldID: field.identity,
      fieldName: field.name,
      oldValue: oldValue,
      newValue: newValue)
  }
}

extension ViewModel {
  public func updateState<Value>(
    _ selection: KeyPath<
      State._VISORSelectors,
      _StateField<State, Value>
    >,
    to value: Value
  ) {
    state[selection] = value
  }
}
