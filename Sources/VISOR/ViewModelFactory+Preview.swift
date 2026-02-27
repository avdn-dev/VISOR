//
//  ViewModelFactory+Preview.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

#if DEBUG
import SwiftUI

extension ViewModelFactory where VM: PreviewProviding, VM.PreviewInstance == VM {
  public static var preview: Self { Self { .preview } }
}

extension View {
  public func previewFactory<VM: ViewModel & PreviewProviding>(
    for _: VM.Type,
    configure: @escaping (VM) -> Void = { _ in }
  ) -> some View where VM.PreviewInstance == VM {
    environment(ViewModelFactory<VM> {
      let vm = VM.preview
      configure(vm)
      return vm
    })
  }
}
#endif
