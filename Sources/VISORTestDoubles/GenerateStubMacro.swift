/// Generates a stub peer type with configurable values and implementations.
///
/// Pass ``TestDoubleTrait/sendable`` to generate checked Sendable,
/// synchronised storage.
@attached(peer, names: prefixed(Stub))
public macro GenerateStub(_ traits: TestDoubleTrait...) = #externalMacro(
  module: "VISORMacros",
  type: "GenerateTestDoublesStubMacro")
