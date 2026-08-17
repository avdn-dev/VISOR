import Foundation
import VISOR
import Testing

// MARK: - Test ViewModels

@MainActor
@Observable
@ViewModel
private final class FactoryTestVM {
  final class State {
    var value = 0
  }

  let state = State()
  let initialValue: Int

  init(value: Int = 0) {
    self.initialValue = value
  }
}

// MARK: - ViewModelFactory Tests

@Suite("ViewModelFactory")
@MainActor
struct ViewModelFactoryTests {

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
  func `Non-routed factory ignores router context`() {
    let factory = ViewModelFactory { FactoryTestVM() }
    let result = factory.makeViewModel(router: NSObject())
    #expect(result.initialValue == 0)
  }

  @Test
  func `Routed factory receives context`() {
    let sentinel = NSObject()
    let factory = ViewModelFactory<RoutedTestVM>(routed: { context in
      RoutedTestVM(routerID: ObjectIdentifier(context))
    })
    let result = factory.makeViewModel(router: sentinel)
    #expect(result.routerID == ObjectIdentifier(sentinel))
  }

  @Test
  func `Factory closure is not invoked at construction time`() {
    var callCount = 0
    let factory = ViewModelFactory {
      callCount += 1
      return FactoryTestVM()
    }
    #expect(callCount == 0, "Closure should not run at factory init")

    _ = factory.makeViewModel()
    #expect(callCount == 1, "Closure should run on first makeViewModel()")

    _ = factory.makeViewModel()
    #expect(callCount == 2, "Closure should run each time makeViewModel() is called")
  }

  @Test
  func `Routed factory with typed convenience receives router`() {
    let router = Router<TestScene>()
    let factory: ViewModelFactory<RoutedTestVM> = .routed { (r: Router<TestScene>) in
      RoutedTestVM(routerID: ObjectIdentifier(r))
    }
    let result = factory.makeViewModel(router: router)
    #expect(result.routerID == ObjectIdentifier(router))
  }

  @Test
  func `Missing router diagnostic names ViewModel and environment value`() {
    let message = ViewModelFactoryDiagnostics.missingRouterMessage(for: RoutedTestVM.self)

    #expect(message.contains("RoutedTestVM"))
    #expect(message.contains("EnvironmentValues.router was nil"))
    #expect(message.contains("RouterHost"))
  }

  @Test
  func `Router mismatch diagnostic names ViewModel expected scene and received type`() {
    let message = ViewModelFactoryDiagnostics.routerTypeMismatchMessage(
      for: RoutedTestVM.self,
      expected: Router<TestScene>.self,
      received: NSObject())

    #expect(message.contains("RoutedTestVM"))
    #expect(message.contains("Router"))
    #expect(message.contains("TestScene"))
    #expect(message.contains("NSObject"))
  }

}
