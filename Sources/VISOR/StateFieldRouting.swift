import Observation
import SwiftUI

private final class StateFieldIdentity {}

@MainActor
/// Generated metadata for one writable ViewModel State field.
///
/// This type is public only because attached macro expansions are type-checked
/// in the consuming module. Application code uses generated selector key paths
/// with ``ViewModel/updateState(_:to:)`` instead of constructing fields.
public struct _StateField<Root: AnyObject, Value> {
  private let identityStorage: StateFieldIdentity
  private let keyPath: ReferenceWritableKeyPath<Root, Value>

  package let name: String

  /// Creates generated metadata for a State field.
  ///
  /// - Parameters:
  ///   - name: The authored State property name used in diagnostics.
  ///   - keyPath: The writable reference key path to that property.
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
/// Type-erased generated metadata for recording a State field.
///
/// This type is public only for external macro expansions.
public struct _AnyStateField<Root: AnyObject> {
  private let readValue: (Root) -> Any

  package let identity: ObjectIdentifier
  package let name: String

  /// Erases one generated State field while retaining its untracked reader.
  ///
  /// - Parameters:
  ///   - field: The typed field metadata to erase.
  ///   - untrackedRead: A generated accessor that avoids Observation tracking.
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
/// Generated mutation-recorder contract used by `VISORTesting`.
///
/// This protocol is public only for external macro expansions.
public protocol _StateMutationRecorder: AnyObject {
  /// Records one completed generated State assignment.
  ///
  /// - Parameters:
  ///   - fieldID: The stable identity of the generated field metadata.
  ///   - fieldName: The authored State property name.
  ///   - oldValue: The value before assignment.
  ///   - newValue: The value after assignment.
  func record(
    fieldID: ObjectIdentifier,
    fieldName: String,
    oldValue: Any,
    newValue: Any)
}

@MainActor
/// Generated requirements implemented by a ViewModel's nested State class.
///
/// This protocol is public only for external macro expansions.
public protocol _ViewModelState: AnyObject {
  /// The generated selector namespace for the State type.
  associatedtype _VISORSelectors

  /// The generated selector namespace value.
  static var _visorSelectors: _VISORSelectors { get }
  /// Type-erased metadata for every generated State field.
  static var _visorAllFields: [_AnyStateField<Self>] { get }
  /// The active test mutation recorder, when the State is reserved by a test.
  var _visorMutationRecorder: (any _StateMutationRecorder)? { get set }
}

extension _ViewModelState {
  /// Reads or writes State through a generated selector key path.
  ///
  /// - Parameter selection: A key path into the generated selector namespace.
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

  /// Records a generated State mutation when a test scope is active.
  ///
  /// - Parameters:
  ///   - field: The generated field metadata.
  ///   - oldValue: The value before assignment.
  ///   - newValue: The value after assignment.
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
  /// Replaces one State field through its generated selector.
  ///
  /// - Parameters:
  ///   - selection: A key path into the generated State selector namespace.
  ///   - value: The replacement value.
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
