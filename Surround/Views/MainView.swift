//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            PublicGamesList()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                OGSWebSocket.shared.ensureConnect()
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MainView()
        }
    }
}
