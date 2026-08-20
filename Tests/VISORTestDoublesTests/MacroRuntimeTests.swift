import Foundation
import Observation
import Testing
import VISORObservation
import VISORTestDoubles

@GenerateSpy
@ObservationStateRequirements
protocol ObservationStateService {
    @ObservationState(observedAs: .values)
    var count: Int { get }
}

@GenerateSpy(.sendable)
@ObservationStateRequirements
nonisolated protocol SendableObservationStateService: Sendable {
    @ObservationState(observedAs: .values)
    var count: Int { get }
}

// MARK: - @GenerateStub Runtime Tests


@Suite("Macro Runtime — @GenerateStub")
@MainActor
struct GenerateStubMacroRuntimeTests {

    @Test
    func `@GenerateStub generates class conforming to protocol`() {
        let stub: any ItemService = StubItemService()
        #expect(stub.items.isEmpty)
        #expect(stub.count == 0)
    }

    @Test
    func `Stub properties are mutable`() {
        let stub = StubItemService()
        stub.items = ["a", "b"]
        stub.count = 5
        #expect(stub.items == ["a", "b"])
        #expect(stub.count == 5)
    }

    @Test
    func `Stub method returns configured return value`() async throws {
        let stub = StubItemService()
        let defaultResult = try await stub.fetchItems()
        #expect(defaultResult == ["default"])

        stub.fetchItemsResult = .success(["x", "y"])
        let result = try await stub.fetchItems()
        #expect(result == ["x", "y"])
    }

    @Test
    func `Stub void method does nothing`() async throws {
        let stub = StubItemService()
        // Should not throw
        try await stub.save("item")
    }

    @Test
    func `Stub used as protocol-typed dependency`() async throws {
        let stub = StubItemService()
        stub.fetchItemsResult = .success(["stubbed"])

        let service: any ItemService = stub
        let result = try await service.fetchItems()
        #expect(result == ["stubbed"])
    }

    @Test
    func `Stub method throws configured error`() async {
        struct TestError: Error, Equatable {}
        let stub = StubItemService()
        stub.fetchItemsResult = .failure(TestError())

        await #expect(throws: TestError.self) {
            try await stub.fetchItems()
        }
    }

    @Test
    func `Stub void method throws configured error`() async {
        struct SaveError: Error, Equatable {}
        let stub = StubItemService()
        stub.saveResult = .failure(SaveError())

        await #expect(throws: SaveError.self) {
            try await stub.save("item")
        }
    }

    @Test
    func `Generic rethrowing stub keeps non-throwing calls non-throwing`() async {
        let stub = StubRuntimeStubWorkRunner()

        let value = await stub.run("job.stub") {
            "stubbed"
        }

        #expect(value == "stubbed")
    }

    @Test
    func `Generic rethrowing stub propagates body errors`() async {
        struct StubWorkError: Error, Equatable {}
        let stub = StubRuntimeStubWorkRunner()

        await #expect(throws: StubWorkError.self) {
            let _: String = try await stub.run("job.stub.fail") {
                throw StubWorkError()
            }
        }
    }

    @Test
    func `Typed throwing stub conforms and throws configured errors`() async throws {
        let stub = StubRuntimeTypedThrowingService()
        let service: any RuntimeTypedThrowingService = stub

        try service.perform()
        let defaultResult = try await service.fetchValue()
        #expect(defaultResult == "default value")

        stub.performResult = .failure(.failed)
        #expect(throws: RuntimeOperationError.self) {
            try service.perform()
        }

        stub.fetchValueResult = .failure(.failed)
        await #expect(throws: RuntimeFetchError.self) {
            try await service.fetchValue()
        }
    }

    @Test
    func `Sendable stub remains safe across isolation`() async {
        let stub = StubRuntimeSendableStubService()
        requireSendable(stub)
        #expect(stub.value == 0)

        await Task { @concurrent in
            stub.value = 42
        }.value

        #expect(stub.value == 42)
        #expect(stub.load() == 0)
    }

    @Test
    func `Sendable stub retains generic rethrowing support`() async {
        let stub = StubRuntimeSendableWorkRunner()
        requireSendable(stub)

        let value = await stub.run { "complete" }

        #expect(value == "complete")
    }

    @Test
    func `Sendable stub stores a sending return value without its specifier`() {
        let stub = StubRuntimeSendingReturnService()
        requireSendable(stub)

        #expect(stub.message() == "")

        stub.messageReturnValue = "configured"

        #expect(stub.message() == "configured")
    }
}

// MARK: - @GenerateSpy Runtime Tests


@Suite("Macro Runtime — @GenerateSpy")
@MainActor
struct GenerateSpyMacroRuntimeTests {

    @Test
    func `Observation State assignments publish through generated spies`() async throws {
        let spy = SpyObservationStateService()
        let service: any ObservationStateService = spy
        let values = service.countValues.makeAsyncIterator()

        #expect(try await values.next() == 0)
        spy.count = 1
        #expect(try await values.next() == 1)
    }

    @Test
    func `Sendable Observation State assignments remain coherent across isolation`() async throws {
        let spy = SpySendableObservationStateService()
        let values = spy.countValues.makeAsyncIterator()

        #expect(try await values.next() == 0)
        await Task { @concurrent in
            spy.count = 2
        }.value
        #expect(try await values.next() == 2)

        await withTaskGroup(of: Void.self) { group in
            for count in 3...1_000 {
                group.addTask {
                    spy.count = count
                }
            }
        }

        #expect(spy.countValues.currentSnapshot() == spy.count)
    }

    @Test
    func `@GenerateSpy generates class conforming to protocol`() {
        let spy: any AnalyticsService = SpyAnalyticsService()
        spy.trackEvent("test")
    }

    @Test
    func `Spy tracks call count`() {
        let spy = SpyAnalyticsService()
        #expect(spy.trackEventCallCount == 0)

        spy.trackEvent("a")
        #expect(spy.trackEventCallCount == 1)

        spy.trackEvent("b")
        #expect(spy.trackEventCallCount == 2)
    }

    @Test
    func `Spy tracks single-param received value`() {
        let spy = SpyAnalyticsService()
        spy.trackEvent("login")
        #expect(spy.trackEventReceivedName == "login")
    }

    @Test
    func `Spy tracks single-param invocations array`() {
        let spy = SpyAnalyticsService()
        spy.trackEvent("a")
        spy.trackEvent("b")
        spy.trackEvent("c")
        #expect(spy.trackEventReceivedInvocations == ["a", "b", "c"])
    }

    @Test
    func `Spy tracks multi-param received arguments`() {
        let spy = SpyAnalyticsService()
        spy.trackScreen(name: "Home", category: "main")

        #expect(spy.trackScreenReceivedArguments?.name == "Home")
        #expect(spy.trackScreenReceivedArguments?.category == "main")
    }

    @Test
    func `Spy tracks multi-param invocations array`() {
        let spy = SpyAnalyticsService()
        spy.trackScreen(name: "Home", category: "main")
        spy.trackScreen(name: "Settings", category: "prefs")

        #expect(spy.trackScreenReceivedInvocations.count == 2)
        #expect(spy.trackScreenReceivedInvocations[0].name == "Home")
        #expect(spy.trackScreenReceivedInvocations[1].name == "Settings")
    }

    @Test
    func `Spy returns configured return value`() async throws {
        let spy = SpyAnalyticsService()
        let defaultResult = try await spy.fetchReport()
        #expect(defaultResult == "default report")
        #expect(spy.fetchReportCallCount == 1)

        spy.fetchReportResult = .success("report data")

        let result = try await spy.fetchReport()
        #expect(result == "report data")
        #expect(spy.fetchReportCallCount == 2)
    }

    @Test
    func `Spy Call enum records all calls in order with correct values`() {
        let spy = SpyAnalyticsService()

        spy.trackEvent("launch")
        spy.trackScreen(name: "Home", category: "main")
        spy.trackEvent("tap")

        #expect(spy.calls.count == 3)
        // Check order and content via call counts and received values
        #expect(spy.trackEventReceivedInvocations == ["launch", "tap"])
        #expect(spy.trackScreenReceivedInvocations.count == 1)
        #expect(spy.trackScreenReceivedInvocations[0].name == "Home")
    }

    @Test
    func `Spy method throws configured error`() async {
        struct ReportError: Error, Equatable {}
        let spy = SpyAnalyticsService()
        spy.fetchReportResult = .failure(ReportError())

        await #expect(throws: ReportError.self) {
            try await spy.fetchReport()
        }
        #expect(spy.fetchReportCallCount == 1)
    }

    @Test
    func `Generic rethrowing spy keeps non-throwing calls non-throwing`() async {
        let spy = SpyRuntimeWorkRunner()

        let value = await spy.run("job.one") {
            "finished"
        }

        #expect(value == "finished")
        #expect(spy.runCallCount == 1)
        #expect(spy.runReceivedName == "job.one")
        #expect(spy.runReceivedInvocations == ["job.one"])
    }

    @Test
    func `Generic rethrowing spy propagates body errors`() async {
        struct WorkError: Error, Equatable {}
        let spy = SpyRuntimeWorkRunner()

        await #expect(throws: WorkError.self) {
            let _: String = try await spy.run("job.fail") {
                throw WorkError()
            }
        }

        #expect(spy.runCallCount == 1)
        #expect(spy.runReceivedName == "job.fail")
    }

    @Test
    func `Spy stores method generic arguments as Any`() {
        let spy = SpyRuntimeGenericSink()

        spy.consume(42, tag: "number")
        spy.consume("hello", tag: "text")

        #expect(spy.consumeCallCount == 2)
        #expect(spy.consumeReceivedArguments?.value as? String == "hello")
        #expect(spy.consumeReceivedArguments?.tag == "text")

        let firstInvocation = spy.consumeReceivedInvocations[0]
        let secondInvocation = spy.consumeReceivedInvocations[1]
        #expect(firstInvocation.value as? Int == 42)
        #expect(firstInvocation.tag == "number")
        #expect(secondInvocation.value as? String == "hello")
        #expect(secondInvocation.tag == "text")
    }

    @Test
    func `Rethrowing void spy forwards body and preserves rethrows`() {
        let spy = SpyRuntimeVoidRunner()
        var didRun = false

        spy.run {
            didRun = true
        }

        #expect(didRun)
        #expect(spy.runCallCount == 1)
    }

    @Test
    func `Rethrowing void spy propagates body errors`() {
        struct VoidWorkError: Error, Equatable {}
        let spy = SpyRuntimeVoidRunner()

        #expect(throws: VoidWorkError.self) {
            try spy.run {
                throw VoidWorkError()
            }
        }

        #expect(spy.runCallCount == 1)
    }

    @Test
    func `Typed throwing spy conforms and preserves typed implementation closures`() async throws {
        let spy = SpyRuntimeTypedThrowingService()
        let service: any RuntimeTypedThrowingService = spy

        try service.perform()
        #expect(spy.performCallCount == 1)

        spy.performResult = .failure(.failed)
        #expect(throws: RuntimeOperationError.self) {
            try service.perform()
        }
        #expect(spy.performCallCount == 2)

        let defaultResult = try await service.fetchValue()
        #expect(defaultResult == "default value")

        spy.fetchValueImplementation = { () async throws(RuntimeFetchError) -> String in
            throw RuntimeFetchError.failed
        }
        await #expect(throws: RuntimeFetchError.self) {
            try await service.fetchValue()
        }
        #expect(spy.fetchValueCallCount == 2)
    }

    @Test
    func `Spy call counts participate in Observation tracking`() async {
        let spy = SpyAnalyticsService()

        await confirmation { confirmed in
            withObservationTracking {
                _ = spy.trackEventCallCount
            } onChange: {
                confirmed()
            }

            spy.trackEvent("test")
        }

        #expect(spy.trackEventCallCount == 1)
    }

    @Test
    func `Sendable spy records concurrent calls without losing updates`() async {
        let spy = SpyRuntimeSendableSpyService()
        requireSendable(spy)

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<1_000 {
                group.addTask {
                    _ = await spy.record(value)
                }
                group.addTask {
                    spy.recordReturnValue = value
                    _ = spy.recordReturnValue
                }
            }
        }

        #expect(spy.recordCallCount == 1_000)
        #expect(spy.recordReceivedInvocations.count == 1_000)
        #expect(Set(spy.recordReceivedInvocations) == Set(0..<1_000))
        #expect(spy.calls.count == 1_000)
        #expect((0..<1_000).contains(spy.recordReturnValue))
    }

    @Test
    func `Sendable spy invokes re-entrant implementation outside storage lock`() async {
        let spy = SpyRuntimeSendableSpyService()
        spy.recordImplementation = { value in
            spy.recordReturnValue = value
            return spy.calls.count
        }

        let result = await spy.record(7)

        #expect(result == 1)
        #expect(spy.recordReturnValue == 7)
        #expect(spy.recordCallCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Sendable storage retires replaced references after unlocking`() {
        let stub = StubRuntimeSendableRetirementService()
        var value: RuntimeReentrantRetirementValue? = RuntimeReentrantRetirementValue { [weak stub] in
            _ = stub?.value
        }
        weak let retiredValue = value

        stub.value = value
        value = nil
        stub.value = nil

        #expect(retiredValue == nil)
    }

    @Test
    func `Sendable spy records constrained generics and permits non-retained generics`() {
        let spy = SpyRuntimeSendableGenericSpyService()
        requireSendable(spy)

        spy.consume("inline", tag: "event")
        spy.consumeWhere(42)
        spy.perform { NSObject() }

        #expect(spy.consumeReceivedArguments?.value as? String == "inline")
        #expect(spy.consumeReceivedArguments?.tag == "event")
        #expect(spy.consumeReceivedInvocations.first?.value as? String == "inline")
        #expect(spy.consumeReceivedInvocations.first?.tag == "event")
        #expect(spy.consumeWhereReceivedValue as? Int == 42)
        #expect(spy.consumeWhereReceivedInvocations.first as? Int == 42)
        #expect(spy.performCallCount == 1)
        #expect(spy.calls.count == 3)
    }

    @Test
    func `Sendable spy records ownership-qualified parameters`() {
        let spy = SpyRuntimeOwnershipSpyService()
        requireSendable(spy)

        spy.receiveSendingImplementation = { _ in }
        spy.receiveConsumingImplementation = { _ in }

        spy.receiveSending("sent")
        spy.receiveConsuming("consumed")
        spy.receiveBorrowing("borrowed")

        #expect(spy.receiveSendingReceivedValue == "sent")
        #expect(spy.receiveConsumingReceivedValue == "consumed")
        #expect(spy.receiveBorrowingReceivedValue == "borrowed")
        #expect(spy.calls.count == 3)
    }

    // MARK: - Implementation closures

    @Test
    func `Implementation closure overrides ReturnValue`() {
        let spy = SpyGreeterService()
        spy.greetReturnValue = "default"

        spy.greetImplementation = { name in
            "Hello, \(name)!"
        }

        let result = spy.greet("World")
        #expect(result == "Hello, World!")
    }

    @Test
    func `Implementation closure records calls before delegating`() {
        let spy = SpyGreeterService()

        spy.greetImplementation = { name in
            "Hi, \(name)"
        }

        _ = spy.greet("Alice")
        _ = spy.greet("Bob")

        #expect(spy.greetCallCount == 2)
        #expect(spy.greetReceivedInvocations == ["Alice", "Bob"])
        #expect(spy.greetReceivedName == "Bob")
        #expect(spy.calls.count == 2)
    }

    @Test
    func `Implementation closure falls back to ReturnValue when nil`() {
        let spy = SpyGreeterService()
        spy.greetReturnValue = "fallback"

        let result = spy.greet("Test")
        #expect(result == "fallback")
        #expect(spy.greetCallCount == 1)
    }

    @Test
    func `Void implementation closure records calls`() {
        let spy = SpyGreeterService()

        var resetCount = 0
        spy.resetImplementation = {
            resetCount += 1
        }

        spy.reset()
        spy.reset()

        #expect(resetCount == 2)
        #expect(spy.resetCallCount == 2)
        #expect(spy.calls.count == 2)
    }

    // MARK: Escaping closure parameters

    @Test
    func `Spy with escaping closure tracks calls, arguments and enum`() {
        let spy = SpyCallbackService()

        let cb1: (String) -> Void = { _ in }
        let cb2: (String) -> Void = { _ in }

        spy.register(cb1)
        spy.register(cb2)

        // Call count
        #expect(spy.registerCallCount == 2)
        // Received value — stored property with function type still works after @escaping stripped
        #expect(spy.registerReceivedCallback != nil)
        // Invocations array tracks both
        #expect(spy.registerReceivedInvocations.count == 2)
        // Call enum — associated value with function type works after @escaping stripped
        #expect(spy.calls.count == 2)
    }

    @Test
    func `Spy with escaping closure supports implementation override`() {
        let spy = SpyCallbackService()

        spy.registerImplementation = { callback in
            callback("from impl")
        }

        var received: String?
        spy.register { received = $0 }

        #expect(received == "from impl")
        #expect(spy.registerCallCount == 1)
        // Calls still recorded even with implementation override
        #expect(spy.calls.count == 1)
    }

    // MARK: - Inout parameters

    @Test
    func `Inout method records calls and preserves value without implementation`() {
        let spy = SpyInoutService()
        var value = 99

        spy.update(value: &value)

        #expect(value == 99)
        #expect(spy.updateCallCount == 1)
        #expect(spy.calls.count == 1)
    }

    @Test
    func `Inout method implementation closure mutates caller value via ampersand`() {
        let spy = SpyInoutService()

        spy.updateImplementation = { value in
            value += 1
        }

        var value = 41
        spy.update(value: &value)
        #expect(value == 42)
        #expect(spy.updateCallCount == 1)
    }

    @Test
    func `Mixed inout and regular params track only non-inout args`() {
        let spy = SpyMixedInoutService()
        var output = "initial"

        spy.process(name: "test", output: &output)

        #expect(spy.processCallCount == 1)
        // Regular param tracked
        #expect(spy.processReceivedName == "test")
        #expect(spy.processReceivedInvocations == ["test"])
        // Call enum captures both (inout type stripped)
        #expect(spy.calls.count == 1)
    }

    @Test
    func `Mixed inout and regular params implementation closure`() {
        let spy = SpyMixedInoutService()

        spy.processImplementation = { name, output in
            output = "processed by \(name)"
        }

        var result = "before"
        spy.process(name: "Alice", output: &result)
        #expect(result == "processed by Alice")
        #expect(spy.processCallCount == 1)
    }

    @Test
    func `Inout call enum captures value snapshot`() {
        let spy = SpyInoutService()

        var value = 10
        spy.update(value: &value)
        value = 20
        spy.update(value: &value)

        #expect(spy.calls.count == 2)
        // Each call captured the value at the time of the call
        if case .update(let captured) = spy.calls[0] {
            #expect(captured == 10)
        } else {
            #expect(Bool(false), "Expected .update(10)")
        }
        if case .update(let captured) = spy.calls[1] {
            #expect(captured == 20)
        } else {
            #expect(Bool(false), "Expected .update(20)")
        }
    }

}

nonisolated private func requireSendable<T: Sendable>(_: T) {}
