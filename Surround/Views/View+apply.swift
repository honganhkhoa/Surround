//
//  View+apply.swift
//  Surround
//
//  Created by Anh Khoa Hong on 2024/7/9.
//

import SwiftUI

extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
}
