import Observation
import VISORTestDoubles

@GenerateStub
package protocol PackageCatalogueServing {
  func count() -> Int
}

@GenerateSpy(.sendable)
package nonisolated protocol PackageEventRecording: Sendable {
  func record(_ value: Int)
}
