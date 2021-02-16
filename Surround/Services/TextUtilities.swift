//
//  TextUtilities.swift
//  Surround
//
//  Created by Anh Khoa Hong on 16/02/2021.
//

import Foundation
import SwiftUI

struct LeadingAlignTextInScrollView: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Text {
    func leadingAlignedInScrollView() -> some View {
        self.modifier(LeadingAlignTextInScrollView())
    }
}
