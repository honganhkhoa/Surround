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
            HStack {
                if let user = ogs.user {
                    GroupBox(label: Text("Online-go.com Account")) {
                        HStack(alignment: .top) {
                            if let url = user.iconURL(ofSize: 96) {
                                URLImage(url)
                                    .frame(width: 96, height: 96)
                                    .background(Color.gray)
                                    .cornerRadius(10)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(user.username)
                                    Text("[\(user.formattedRank)]")
                                }
                                .font(.title)
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
                } else {
                    LoginView()
                }
            }
            .frame(maxWidth: 600)
        }

        .navigationTitle("Settings")
        .modifier(RootViewSwitchingMenu())
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
//                user: OGSUser(
//                    username: "kata-bot",
//                    id: 592684,
//                    ranking: 27,
//                    icon: "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/7bb95c73c9ce77095b3a330729104b35-32.png"
//                )
            )
        )
    }
}
