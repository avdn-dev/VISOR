import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

enum TestDoubleGeneratedNameRole: String {
  case callCount = "call-count member"
  case receivedArgument = "received-argument member"
  case receivedArguments = "received-arguments member"
  case receivedInvocations = "invocation-history member"
  case returnStorage = "return-storage member"
  case implementation = "implementation closure"
  case callLog = "call-log member"
  case callType = "call-log type"
  case callCase = "call-log case"
  case storage = "synchronised-storage member"
  case storageType = "synchronised-storage type"
}

struct TestDoubleGeneratedNameRename {
  let role: TestDoubleGeneratedNameRole
  let preferredName: String
  let generatedName: String
  let methodName: String?
}

struct TestDoubleMethodNamePlan {
  let prefix: String
  let callCount: String?
  let receivedArgument: String?
  let receivedArguments: String?
  let receivedInvocations: String?
  let returnStorage: String?
  let implementation: String?
  let callCase: String?
}

struct TestDoubleNamePlan {
  let methods: [TestDoubleMethodNamePlan]
  let callType: String?
  let callLog: String?
  let storageType: String?
  let storage: String?
  let renames: [TestDoubleGeneratedNameRename]

  init(
    kind: TestDoubleKind,
    analysis: ProtocolAnalysis,
    isSendable: Bool)
  {
    let methodPrefixes = uniqueMethodPrefixes(for: analysis.methods)
    var memberAllocator = GeneratedNameAllocator(reserving:
      analysis.properties.map(\.name) + analysis.methods.map(\.name))
    var typeAllocator = GeneratedNameAllocator(reserving: analysis.typeAliasNames)
    var renames: [TestDoubleGeneratedNameRename] = []

    if isSendable {
      storageType = Self.allocate(
        preferred: "_Storage",
        fallback: "_GeneratedStorage",
        role: .storageType,
        methodName: nil,
        allocator: &typeAllocator,
        renames: &renames)
      storage = Self.allocate(
        preferred: "_testDoubleStorage",
        fallback: "_generatedTestDoubleStorage",
        role: .storage,
        methodName: nil,
        allocator: &memberAllocator,
        renames: &renames)
    } else {
      storageType = nil
      storage = nil
    }

    if kind == .spy, !analysis.methods.isEmpty {
      callType = Self.allocate(
        preferred: "Call",
        fallback: "GeneratedCall",
        role: .callType,
        methodName: nil,
        allocator: &typeAllocator,
        renames: &renames)
      callLog = Self.allocate(
        preferred: "calls",
        fallback: "recordedCalls",
        role: .callLog,
        methodName: nil,
        allocator: &memberAllocator,
        renames: &renames)
    } else {
      callType = nil
      callLog = nil
    }

    var callCaseSignatures: Set<CallCaseSignature> = []
    var methodPlans: [TestDoubleMethodNamePlan] = []
    methodPlans.reserveCapacity(analysis.methods.count)

    for (method, methodPrefix) in zip(analysis.methods, methodPrefixes) {
      let methodName = method.name
      let returnStorage = Self.preferredReturnStorageName(
        for: method,
        methodPrefix: methodPrefix).map {
          Self.allocate(
            preferred: $0,
            fallback: "\($0)Generated",
            role: .returnStorage,
            methodName: methodName,
            allocator: &memberAllocator,
            renames: &renames)
        }

      guard kind == .spy else {
        methodPlans.append(TestDoubleMethodNamePlan(
          prefix: methodPrefix,
          callCount: nil,
          receivedArgument: nil,
          receivedArguments: nil,
          receivedInvocations: nil,
          returnStorage: returnStorage,
          implementation: nil,
          callCase: nil))
        continue
      }

      let callCountPreferred = "\(methodPrefix)CallCount"
      let callCount = Self.allocate(
        preferred: callCountPreferred,
        fallback: "\(callCountPreferred)Generated",
        role: .callCount,
        methodName: methodName,
        allocator: &memberAllocator,
        renames: &renames)

      let receivedParameters = method.parameters.filter { !$0.isInout }
      let storableParameters = receivedParameters.filter {
        spyStorageType(for: $0, method: method) != nil
      }

      let receivedArgument: String?
      let receivedArguments: String?
      let receivedInvocations: String?
      if storableParameters.count == 1, let parameter = storableParameters.first {
        let preferred = "\(methodPrefix)Received\(parameter.internalName.capitalisedFirst)"
        receivedArgument = Self.allocate(
          preferred: preferred,
          fallback: "\(preferred)Generated",
          role: .receivedArgument,
          methodName: methodName,
          allocator: &memberAllocator,
          renames: &renames)
        receivedArguments = nil
        let invocationsPreferred = "\(methodPrefix)ReceivedInvocations"
        receivedInvocations = Self.allocate(
          preferred: invocationsPreferred,
          fallback: "\(invocationsPreferred)Generated",
          role: .receivedInvocations,
          methodName: methodName,
          allocator: &memberAllocator,
          renames: &renames)
      } else if storableParameters.count > 1 {
        receivedArgument = nil
        let preferred = "\(methodPrefix)ReceivedArguments"
        receivedArguments = Self.allocate(
          preferred: preferred,
          fallback: "\(preferred)Generated",
          role: .receivedArguments,
          methodName: methodName,
          allocator: &memberAllocator,
          renames: &renames)
        let invocationsPreferred = "\(methodPrefix)ReceivedInvocations"
        receivedInvocations = Self.allocate(
          preferred: invocationsPreferred,
          fallback: "\(invocationsPreferred)Generated",
          role: .receivedInvocations,
          methodName: methodName,
          allocator: &memberAllocator,
          renames: &renames)
      } else {
        receivedArgument = nil
        receivedArguments = nil
        receivedInvocations = nil
      }

      let implementation: String?
      if supportsImplementationClosure(for: method) {
        let preferred = "\(methodPrefix)Implementation"
        implementation = Self.allocate(
          preferred: preferred,
          fallback: "\(preferred)Closure",
          role: .implementation,
          methodName: methodName,
          allocator: &memberAllocator,
          renames: &renames)
      } else {
        implementation = nil
      }

      let callParameters = method.parameters.filter {
        spyStorageType(for: $0, method: method) != nil
      }
      let callCase = Self.allocateCallCase(
        preferred: method.name,
        labels: callParameters.map(\.internalName),
        methodPrefix: methodPrefix,
        methodName: methodName,
        signatures: &callCaseSignatures,
        renames: &renames)

      methodPlans.append(TestDoubleMethodNamePlan(
        prefix: methodPrefix,
        callCount: callCount,
        receivedArgument: receivedArgument,
        receivedArguments: receivedArguments,
        receivedInvocations: receivedInvocations,
        returnStorage: returnStorage,
        implementation: implementation,
        callCase: callCase))
    }

    methods = methodPlans
    self.renames = renames
  }

  func diagnose(
    protocolDecl: ProtocolDeclSyntax,
    macroName: String,
    context: some MacroExpansionContext)
  {
    for rename in renames {
      let message: TestDoubleDiagnostic
      if rename.role == .implementation, let methodName = rename.methodName {
        message = .implementationNameCollision(
          methodName: methodName,
          preferredName: rename.preferredName,
          generatedName: rename.generatedName,
          macroName: macroName)
      } else {
        message = .generatedMemberNameCollision(
          role: rename.role.rawValue,
          preferredName: rename.preferredName,
          generatedName: rename.generatedName,
          macroName: macroName)
      }
      context.diagnose(Diagnostic(node: Syntax(protocolDecl), message: message))
    }
  }

  private static func preferredReturnStorageName(
    for method: ProtocolMethodInfo,
    methodPrefix: String)
    -> String?
  {
    guard !method.isRethrowing else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.returnType) else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType) else {
      return nil
    }
    if method.isThrowing {
      return "\(methodPrefix)Result"
    }
    return method.returnType == nil ? nil : "\(methodPrefix)ReturnValue"
  }

  private static func allocate(
    preferred: String,
    fallback: String,
    role: TestDoubleGeneratedNameRole,
    methodName: String?,
    allocator: inout GeneratedNameAllocator,
    renames: inout [TestDoubleGeneratedNameRename])
    -> String
  {
    let generated = allocator.allocate(preferred: preferred, fallback: fallback)
    if generated != preferred {
      renames.append(TestDoubleGeneratedNameRename(
        role: role,
        preferredName: preferred,
        generatedName: generated,
        methodName: methodName))
    }
    return generated
  }

  private static func allocateCallCase(
    preferred: String,
    labels: [String],
    methodPrefix: String,
    methodName: String,
    signatures: inout Set<CallCaseSignature>,
    renames: inout [TestDoubleGeneratedNameRename])
    -> String
  {
    let preferredSignature = CallCaseSignature(name: preferred, labels: labels)
    guard signatures.contains(preferredSignature) else {
      signatures.insert(preferredSignature)
      return preferred
    }

    var generated = methodPrefix
    var suffix = 2
    while signatures.contains(CallCaseSignature(name: generated, labels: labels)) {
      generated = "\(methodPrefix)Call\(suffix)"
      suffix += 1
    }
    signatures.insert(CallCaseSignature(name: generated, labels: labels))
    renames.append(TestDoubleGeneratedNameRename(
      role: .callCase,
      preferredName: preferred,
      generatedName: generated,
      methodName: methodName))
    return generated
  }
}

private struct GeneratedNameAllocator {
  private var reservedNames: Set<String>

  init(reserving names: [String]) {
    reservedNames = Set(names)
  }

  mutating func allocate(preferred: String, fallback: String) -> String {
    guard reservedNames.contains(preferred) else {
      reservedNames.insert(preferred)
      return preferred
    }

    var candidate = fallback
    var suffix = 2
    while reservedNames.contains(candidate) {
      candidate = "\(fallback)\(suffix)"
      suffix += 1
    }
    reservedNames.insert(candidate)
    return candidate
  }
}

private struct CallCaseSignature: Hashable {
  let name: String
  let labels: [String]
}
