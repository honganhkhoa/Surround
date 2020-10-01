//
//  SettingsView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/30/20.
//

import SwiftUI
import URLImage

struct SettingsView: View {
    @EnvironmentObject var ogs: OGSService
    
    @State var username: String = ""
    @State var password: String = ""
    
    @State var isShowingFacebookLogin = false
    @State var isShowingGoogleLogin = false
    @State var isShowingTwitterLogin = false
    
    var body: some View {
        ScrollView {
            VStack {
                if let user = ogs.user {
                    GroupBox(label: Text("Online-go.com Account")) {
                        HStack(alignment: .top) {
                            if let url = user.iconURL(ofSize: 64) {
                                URLImage(url)
                                    .frame(width: 64, height: 64)
                                    .background(Color.gray)
                                    .cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(user.username)
                                    Text("[\(user.formattedRank)]")
                                }
                                .font(.title3)
                                Button(action: { ogs.logout() }) {
                                    Text("Logout")
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .hoverEffect()
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                } else {
                    LoginView()
                }
                GameplaySettings()
            }
            .frame(maxWidth: 600)
        }
        .navigationTitle("Settings")
        .modifier(RootViewSwitchingMenu())
    }
}

struct GameplaySettings: View {
    var body: some View {
        GroupBox(label: Text("Gameplay")) {
            Toggle("Haptics", isOn: SettingWithDefault(key: .hapticsFeedback).binding)
            GroupBox(label: Text("Auto submiting moves")) {
                Toggle("Live games", isOn: SettingWithDefault(key: .autoSubmitForLiveGames).binding)
                Toggle("Correspondence games", isOn: SettingWithDefault(key: .autoSubmitForCorrespondenceGames).binding)
            }
        }
        .padding(.horizontal)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(
            OGSService.previewInstance(
                user: OGSUser(
                    username: "kata-bot",
                    id: 592684,
                    ranking: 27,
                    icon: "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png"
                )
            )
        )
    }
}
