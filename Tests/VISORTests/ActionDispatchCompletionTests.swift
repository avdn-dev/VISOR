import Observation
import Testing
import VISOR
import VISORTesting

// MARK: - CompletionActionModel

@MainActor
@Observable
@ViewModel
private final class CompletionActionModel {
  typealias Completion = ActionCompletion

  final class State {
    private(set) var input = 0
    private(set) var received = [Int]()
  }

  enum Action {
    @StateBinding(\State.input)
    case submit(Int)
    case dismiss
  }

  let operation: ControllableOperation<Int, Never>

  let commands = ConcurrentEffects()

  @discardableResult
  func handle(_ action: Action) -> Completion {
    switch action {
    case .dismiss:
      updateState(\.input, to: 0)
      return .completed

    case .submit(let input):
      updateState(\.input, to: input)
      let invocation = operation.prepare()
      return commands.run(for: self) { [operation] in
        await operation.run(invocation)
      } receive: { model, output in
        model.updateState(\.received, to: model.state.received + [output])
      }.completion
    }
  }

}

// MARK: - ActionDispatchCompletionTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ActionDispatchCompletionTests {

  // MARK: Internal

  @Test
  func `Generic action dispatch commits synchronously and returns joinable work`() async {
    let operation = ControllableOperation<Int, Never>()
    let model = CompletionActionModel(operation: operation)
    let completion = dispatch(.submit(7), to: model)
    #expect(model.state.input == 7)
    #expect(model.state.received.isEmpty)
    operation.resolveAllInvocations(with: .success(42))
    await completion.wait()
    #expect(model.state.received == [42])
    await dispatch(.dismiss, to: model).wait()
    #expect(model.state.input == 0)
  }

  @Test
  func `Binding dispatch discards completion without cancelling accepted work`() async throws {
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(42)) }
    let model = CompletionActionModel(operation: operation)
    try await observe(model) { test in
      try await test.perform {
        model.bindings.input.wrappedValue = 7
        #expect(model.state.input == 7)
        try await operation.waitUntilStarted()
        #expect(operation.cancelledCount == 0)
        operation.resolveAllInvocations(with: .success(42))
        await model.commands.finish()
      }
      #expect(operation.cancelledCount == 0)
      test.expect(\.input, hasExactChanges: [7])
      test.expect(\.received, hasExactChanges: [[42]])
    }
  }

  @Test
  func `Retaining completion does not keep the model or effect owner alive`() async throws {
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(1)) }
    var model: CompletionActionModel? = CompletionActionModel(operation: operation)
    weak let owner = model
    let completion = try #require(model?.handle(.submit(1)))
    try await operation.waitUntilStarted()
    model = nil
    #expect(owner == nil)
    try await operation.waitUntilCancelled()
    operation.resolveAllInvocations(with: .success(1))
    await completion.wait()
    #expect(operation.finishedCount == 1)
  }

  @Test
  func `Action observation automatically joins the returned work before matching`() async throws {
    let operation = ControllableOperation<Int, Never>()
    let model = CompletionActionModel(operation: operation)
    operation.resolveAllInvocations(with: .success(42))
    try await observe(model) { test in
      await test.perform(.submit(7))
      #expect(operation.finishedCount == 1)
      test.expect(\.input, hasExactChanges: [7])
      test.expect(\.received, hasExactChanges: [[42]])
    }
  }

  // MARK: Private

  private func dispatch<Model: ViewModel>(_ action: Model.Action, to model: Model) -> ActionCompletion {
    model.handle(action)
  }
}
