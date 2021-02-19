//
//  ContentView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

struct MainViewWrapper: View {
    @SceneStorage("sceneID") var sceneID = UUID().uuidString
    
    var body: some View {
        let ogs = OGSService.instance(forSceneWithID: sceneID)
        let sgs = SurroundService.instance(forSceneWithID: sceneID)
        let nav = NavigationService.instance(forSceneWithID: sceneID)
        return MainView()
            .environmentObject(ogs)
            .environmentObject(sgs)
            .environmentObject(nav)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainViewWrapper()
    }
}
