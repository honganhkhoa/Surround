//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct ContentView: View {
    @SceneStorage("sceneID") var sceneID = UUID().uuidString
    @State var isLoggedIn = false
    
    var body: some View {
        let ogs = OGSService.instance(forSceneWithID: sceneID)
        return MainView()
            .environmentObject(ogs)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
