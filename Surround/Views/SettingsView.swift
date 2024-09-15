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
    @EnvironmentObject var sgs: SurroundService
        
    @State var notificationEnabled = Setting(.notificationEnabled).wrappedValue
    @State var showSupporterView = false
    @State var hidesRank: Bool = Setting(.hidesRank).wrappedValue
    
    var accountSettings: some View {
        Group {
            if let user = ogs.user {
                GroupBox(label: Text("Online-go.com Account")) {
                    HStack(alignment: .top) {
                        if let url = user.iconURL(ofSize: 64) {
                            URLImage(url: url) { $0.resizable() }
                                .frame(width: 64, height: 64)
                                .background(Color.gray)
                                .cornerRadius(10)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if hidesRank {
                                    Text(verbatim: user.username)
                                } else {
                                    Text(verbatim: "\(user.username) [\(user.formattedRank)]") 
                                }
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
                GroupBox(label: Text("Online-go.com Account")) {
                    NavigationLink(destination: OGSBrowserView(initialURL: URL(string: "\(OGSService.ogsRoot)/sign-in")!, showsURLBar: true).navigationBarTitleDisplayMode(.inline)) {
                        Text("Sign in to your Account")
                            .leadingAlignedInScrollView()
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    var generalSettings: some View {
        GroupBox(label: Text("General")) {
            Toggle(String(localized: "Hide ranks and ratings"), isOn: $hidesRank)
        }
        .padding(.horizontal)
        .onChange(of: hidesRank) { newValue in
            userDefaults[.hidesRank] = newValue
        }
    }
    
    var canToggleNotifications: Bool {
        if notificationEnabled {
            return true
        }
        
        if sgs.supporterProductId != nil {
            return true
        }
        
        if let user = ogs.user {
            if user.isOGSSupporter || user.isOGSAdmin || user.isOGSModerator {
                return true
            }
        }
        
        return false
    }
    
    var notificationSettings: some View {
        return GroupBox(
            label: Toggle(isOn: $notificationEnabled) {
                Text("Correspondence games notifications")
                    .leadingAlignedInScrollView()
            }.disabled(!canToggleNotifications)
        ) {
            if !canToggleNotifications {
                Button(action: { showSupporterView = true }) {
                    (Text("Currently, notification is only available for Supporters, due to ongoing server cost associated with the feature. ").foregroundColor(Color(.label)) + Text("Learn more...").bold())
                        .font(.subheadline)
                        .leadingAlignedInScrollView()
                }
            }
            GroupBox(label: Text("Send a notification on...")) {
                Toggle(String(localized: "My turn", comment: "Correspondence games notification setting"), isOn: Setting(.notificationOnUserTurn).binding)
                Toggle(String(localized: "Time running low", comment: "Correspondence games notification setting"), isOn: Setting(.notificationOnTimeRunningOut).binding)
//                Toggle("Challenge received", isOn: Setting(.notificationOnChallengeReceived).binding)
                Toggle(String(localized: "A game starts", comment: "Correspondence games notification setting"), isOn: Setting(.notificationOnNewGame).binding)
                Toggle(String(localized: "A game ends", comment: "Correspondence games notification setting"), isOn: Setting(.notiticationOnGameEnd).binding)
            }
            .disabled(!notificationEnabled)
        }
        .padding(.horizontal)
        .onChange(of: notificationEnabled) { enabled in
            userDefaults[.notificationEnabled] = enabled
            sgs.setPushEnabled(enabled: enabled)
            if enabled {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
                    if let error = error {
                        print(error)
                    } else if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                    print("Notifications permission granted: \(granted)")
                }
            }
        }
        .sheet(isPresented: $showSupporterView) {
            NavigationView {
                SupporterView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: { showSupporterView = false }) {
                                Text("Close")
                            }
                        }
                    }
            }
            .environmentObject(sgs)
            .environmentObject(ogs)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                accountSettings
                generalSettings
                GameplaySettings(withDemoOption: true)
                notificationSettings
            }
            .frame(maxWidth: 600)
        }
        .navigationTitle("Settings")
    }
}

struct GameplaySettings: View {
    var withDemoOption = false
    @State var showDemoBoard = false
    
    var body: some View {
        GroupBox(label: Text("Gameplay")) {
            Toggle("Board coordinates", isOn: Setting(.showsBoardCoordinates).binding)
            Toggle("Haptics", isOn: Setting(.hapticsFeedback).binding)
            Toggle("Stone sounds", isOn: Setting(.soundOnStonePlacement).binding)
            Toggle("Voice countdown", isOn: Setting(.voiceCountdown).binding)
            (Text("Note: Sounds and voice countdown will not play when your device is in **Silent** mode."))
                .font(.caption)
                .leadingAlignedInScrollView()
            Toggle("Auto Zen mode", isOn: Setting(.autoZen).binding)
            GroupBox(label: Text("Auto submiting moves")) {
                Toggle("Live games", isOn: Setting(.autoSubmitForLiveGames).binding)
                Toggle("Correspondence games", isOn: Setting(.autoSubmitForCorrespondenceGames).binding)
            }
            if withDemoOption {
                Button(action: { showDemoBoard.toggle() }) {
                    if showDemoBoard {
                        Text("Hide demo board", comment: "Demo board in settings").bold().leadingAlignedInScrollView()
                    } else {
                        Text("Try it out", comment: "Demo board in settings").bold().leadingAlignedInScrollView()
                    }
                }
                if showDemoBoard {
                    BoardDemoView()
                }
            }
        }
        .padding(.horizontal)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationService.shared.main.rootView = .settings
        userDefaults[.supporterProductId] = nil
        return Group {
            NavigationView {
                SettingsView()
                    .modifier(RootViewSwitchingMenu())
            }
            .environmentObject(OGSService.previewInstance())
            .colorScheme(.dark)
            NavigationView {
                SettingsView()
                    .modifier(RootViewSwitchingMenu())
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
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(NavigationService.shared)
        .environmentObject(SurroundService.shared)
    }
}
