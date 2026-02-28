//
//  PreferredSettingsView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 2024/3/11.
//

import SwiftUI
import Combine

struct PreferredSettingsView: View {
    @EnvironmentObject var ogs: OGSService
    @EnvironmentObject var nav: NavigationService
    @Environment(\.colorScheme) private var colorScheme
    
    @State var openChallengeCancellableBySetting: [OGSChallengeTemplate: AnyCancellable] = [:]
    @State var deleteSettingCancellableBySetting: [OGSChallengeTemplate: AnyCancellable] = [:]
    
    var cardBackground: some View {
        Color(
            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
        )
        .shadow(radius: 2)
    }

    @ViewBuilder
    private var preferredSettingsContent: some View {
        if let settings = ogs.remoteSettings[.preferredGameSettings], settings.count > 0 {
            preferredSettingsList(settings)
        } else {
            Text("No saved preferred settings.")
        }
    }

    private func preferredSettingsList(_ settings: [OGSChallengeTemplate]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                Section {
                    ForEach(Array(settings.enumerated()), id: \.0) { _, setting in
                        preferredSettingCard(setting)
                    }
                }
            }
            .padding()
        }
    }

    private func preferredSettingCard(_ setting: OGSChallengeTemplate) -> some View {
        VStack {
            ChallengeCell(challenge: setting, hidePlayerDetails: true)
                .padding()
            Divider()
            Button(action: {
                self.openChallengeCancellableBySetting[setting] = ogs.sendChallenge(opponent: nil, challenge: setting).sink(
                    receiveCompletion: { _ in
                        self.openChallengeCancellableBySetting.removeValue(forKey: setting)
                    }, receiveValue: { _ in
                        nav.home.showingPreferredSettings = false
                    })
            }) {
                HStack {
                    if self.openChallengeCancellableBySetting[setting] != nil {
                        ProgressView()
                    } else {
                        Text("Create open challenge")
                    }
                    Spacer()
                }
                .font(.subheadline.bold())
                .padding(.horizontal)
                .padding(.vertical, 5)
            }
            if !setting.rengo {
                Divider()
                Button(action: {}) {
                    HStack {
                        Text("Select opponent")
                        Spacer()
                        Image(systemName: "chevron.forward")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                }
            }
            Divider()
            Button(action: {
                self.deleteSettingCancellableBySetting[setting] = ogs.removePreferredGameSetting(challenge: setting).sink(
                    receiveCompletion: { _ in
                        self.deleteSettingCancellableBySetting.removeValue(forKey: setting)
                    },
                    receiveValue: { _ in }
                )
            }) {
                HStack {
                    if self.deleteSettingCancellableBySetting[setting] != nil {
                        ProgressView()
                    } else {
                        Label("Delete setting", systemImage: "trash")
                    }
                    Spacer()
                }
                .font(.subheadline.bold())
                .padding(.horizontal)
                .padding(.vertical, 5)
            }
            .foregroundStyle(.red)
            .disabled(self.deleteSettingCancellableBySetting[setting] != nil)
        }
        .padding(.bottom, 5)
        .background(cardBackground)
    }
    
    var body: some View {
        preferredSettingsContent
            .onAppear {
                ogs.subscribeToSeekGraph()
            }
            .onDisappear {
                ogs.unsubscribeFromSeekGraphWhenDone()
            }
    }
}

#Preview {
    let preferredSettings = [
        OGSChallengeTemplate(
            game: OGSChallengeTemplate.GameDetail(
                width: 19,
                height: 19,
                ranked: true,
                handicap: -1,
                disableAnalysis: false,
                name: "Test",
                rules: .japanese,
                timeControl: TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject
            )
        )
    ]
    let user = OGSUser(
        username: "honganhkhoa", id: 1526,
        icon: "https://secure.gravatar.com/avatar/4d95e45e08111986fd3fe61e1077b67d?s=32&d=retro",
        iconUrl: "https://secure.gravatar.com/avatar/4d95e45e08111986fd3fe61e1077b67d?s=32&d=retro"
    )
    if let preferredSettingsData = try? JSONEncoder().encode(preferredSettings) {
        if let decodedSettings = try? JSONSerialization.jsonObject(with: preferredSettingsData) as? [[String: Any]] {
            OGSRemoteSettingKey<[OGSChallengeTemplate]>.preferredGameSettings.saveIfValid(settings: decodedSettings, replication: .RemoteOverwritesLocal, modified: Date())
        }
    }
    return NavigationStack {
        PreferredSettingsView()
            .navigationTitle("Preferred settings")
    }
    .environmentObject(OGSService.previewInstance(
        user: user,
        preferredGameSettings: preferredSettings
    ))
}
