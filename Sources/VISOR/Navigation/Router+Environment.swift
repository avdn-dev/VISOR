//
//  Router+Environment.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

import SwiftUI

extension EnvironmentValues {
  /// Type-erased router, automatically set by NavigationContainer.
  @Entry package var router: AnyObject?
}
