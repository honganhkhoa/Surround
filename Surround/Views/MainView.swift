//
//  MainView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/29/20.
//

import SwiftUI

struct MainView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        VStack {
            PublicGamesList()
        }
        .navigationBarTitle(Text("Welcome"))
        .navigationBarItems(trailing: Button(action: {
            OGSService.shared.logout()
            self.isLoggedIn = OGSService.shared.isLoggedIn()
        }, label: {
            Text("Logout")
        }))
        .onAppear() {
            OGSWebSocket.shared.connect()
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MainView(isLoggedIn: .constant(true))
        }
    }
}
