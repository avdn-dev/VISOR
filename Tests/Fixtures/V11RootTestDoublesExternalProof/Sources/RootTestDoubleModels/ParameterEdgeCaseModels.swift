import VISORTestDoubles

// MARK: - ParameterEdgeCaseRecording

@GenerateSpy
public protocol ParameterEdgeCaseRecording {
  func record(_: Int)
  func store(`repeat` `default`: String)
}
