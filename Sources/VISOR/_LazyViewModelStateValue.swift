import Observation

/// An empty state holder that SwiftUI can construct without view inputs.
/// Public only for the generated view's storage bridge.
@MainActor
public protocol _LazyViewModelStateValue: AnyObject, Observable {
  init()
}
