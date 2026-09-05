//
//  ObservationContentIdentityProbe.swift
//  VISORTests
//
//  Created by avdn-dev on 05.09.2026.
//

import SwiftUI

/// Lives below the readiness gate so withdrawing content resets this identity.
@MainActor
struct ObservationContentIdentityProbe: View {
  let appeared: (UUID) -> Void

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .onAppear { appeared(identity) }
  }

  @State private var identity = UUID()
}
