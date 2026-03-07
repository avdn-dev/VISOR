import Foundation
import VISOR
import Observation
import Testing

// MARK: - Test ViewModels

@Observable
@MainActor
private final class FactoryTestVM: ViewModel {
  struct State: Equatable {
    var value = 0
  }
  var state = State()
  let initialValue: Int

  init(value: Int = 0) {
    self.initialValue = value
  }
}

@Observable
@MainActor
private final class RoutedTestVM: ViewModel {
  struct State: Equatable {}
  var state = State()
  let routerID: ObjectIdentifier

  init(routerID: ObjectIdentifier) {
    self.routerID = routerID
  }
}

// MARK: - ViewModelFactory Tests

@Suite("ViewModelFactory")
@MainActor
struct ViewModelFactoryTests {

  @Test
  func `init stores closure`() {
    var callCount = 0
    let factory = ViewModelFactory<FactoryTestVM> {
      callCount += 1
      return FactoryTestVM()
    }

    _ = factory.makeViewModel()
    _ = factory.makeViewModel()
    #expect(callCount == 2)
  }

  @Test
  func `makeViewModel invokes closure and returns result`() {
    let factory = ViewModelFactory { FactoryTestVM(value: 99) }
    let result = factory.makeViewModel()
    #expect(result.initialValue == 99)
  }

  @Test
  func `makeViewModel creates fresh instance each call`() {
    let factory = ViewModelFactory { FactoryTestVM(value: 1) }
    let a = factory.makeViewModel()
    let b = factory.makeViewModel()
    #expect(a !== b)
  }

  // MARK: - Routed Factory Tests

  @Test
  func `non-routed factory ignores router context`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let result = factory.makeViewModel(router: NSObject())
    #expect(result.initialValue == 0)
  }

  @Test
  func `non-routed factory works with nil router context`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let result = factory.makeViewModel(router: nil)
    #expect(result.initialValue == 0)
  }

  @Test
  func `routed factory receives context`() {
    let sentinel = NSObject()
    let factory = ViewModelFactory<RoutedTestVM>(routed: { context in
      RoutedTestVM(routerID: ObjectIdentifier(context))
    })
    let result = factory.makeViewModel(router: sentinel)
    #expect(result.routerID == ObjectIdentifier(sentinel))
  }

  @Test
  func `routed factory with typed convenience receives router`() {
    let router = Router<TestScene>()
    let factory: ViewModelFactory<RoutedTestVM> = .routed { (r: Router<TestScene>) in
      RoutedTestVM(routerID: ObjectIdentifier(r))
    }
    let result = factory.makeViewModel(router: router)
    #expect(result.routerID == ObjectIdentifier(router))
  }

  // MARK: - Closure Captures External State

  @Test
  func `factory closure captures external state`() {
    var counter = 0
    let factory = ViewModelFactory<FactoryTestVM> {
      counter += 1
      return FactoryTestVM(value: counter)
    }
    let first = factory.makeViewModel()
    let second = factory.makeViewModel()
    #expect(first.initialValue == 1)
    #expect(second.initialValue == 2)
  }

  // MARK: - Non-Routed with Multiple Router Contexts

  @Test
  func `non-routed factory with multiple different router contexts`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let a = factory.makeViewModel(router: NSObject())
    let b = factory.makeViewModel(router: nil)
    #expect(a.initialValue == 0)
    #expect(b.initialValue == 0)
  }

  // MARK: - Routed Convenience with Correct Typed Router

  @Test
  func `routed convenience with correct typed Router`() {
    let router = Router<TestScene>(level: 0)
    let factory: ViewModelFactory<RoutedTestVM> = .routed { (r: Router<TestScene>) in
      RoutedTestVM(routerID: ObjectIdentifier(r))
    }
    let vm = factory.makeViewModel(router: router)
    #expect(vm.routerID == ObjectIdentifier(router))
  }
}
