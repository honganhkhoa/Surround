//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct ContentView: View {
    @State var isLoggedIn = OGSService.shared.isLoggedIn()
    
    var body: some View {
        NavigationView {
            !isLoggedIn ?
                AnyView(LoginView(isLoggedIn: $isLoggedIn)) :
                AnyView(MainView(isLoggedIn: $isLoggedIn))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
