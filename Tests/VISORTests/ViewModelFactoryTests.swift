import Foundation
import VISOR
import Observation
import Testing

// MARK: - Test ViewModels

@Observable
@MainActor
private final class FactoryTestVM: ViewModel, PreviewProviding {
  typealias State = Int
  var state: ViewModelState<Int> = .loading
  let value: Int

  init(value: Int = 0) {
    self.value = value
  }

  static var preview: FactoryTestVM {
    FactoryTestVM(value: 42)
  }
}

@Observable
@MainActor
private final class RoutedTestVM: ViewModel {
  typealias State = Void
  var state: ViewModelState<Void> = .loading
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
    #expect(result.value == 99)
  }

  @Test
  func `makeViewModel creates fresh instance each call`() {
    let factory = ViewModelFactory { FactoryTestVM(value: 1) }
    let a = factory.makeViewModel()
    let b = factory.makeViewModel()
    #expect(a !== b)
  }

  @Test
  func `preview works with PreviewProviding type`() {
    let factory = ViewModelFactory<FactoryTestVM>.preview
    let vm = factory.makeViewModel()
    #expect(vm.value == 42)
  }

  // MARK: - Routed Factory Tests

  @Test
  func `non-routed factory ignores router context`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let result = factory.makeViewModel(router: NSObject())
    #expect(result is FactoryTestVM)
  }

  @Test
  func `non-routed factory works with nil router context`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let result = factory.makeViewModel(router: nil)
    #expect(result is FactoryTestVM)
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
}
