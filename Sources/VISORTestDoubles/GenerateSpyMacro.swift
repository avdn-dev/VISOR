/// Generates a spy peer type with call recording.
///
/// Pass ``TestDoubleTrait/sendable`` to generate checked Sendable,
/// synchronised storage.
///
/// - Parameter traits: Options that specialise the generated spy.
@attached(peer, names: prefixed(Spy))
public macro GenerateSpy(_ traits: TestDoubleTrait...) = #externalMacro(
  module: "VISORMacros",
  type: "GenerateTestDoublesSpyMacro")
