import VISORTestDoubles

// MARK: - PackageCatalogueServing

@GenerateStub
package protocol PackageCatalogueServing {
  func count() -> Int
}

// MARK: - PackageEventRecording

@GenerateSpy(.sendable)
package nonisolated protocol PackageEventRecording: Sendable {
  func record(_ value: Int)
}
