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
    
    var cardBackground: some View {
        Color(
            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
        )
        .shadow(radius: 2)
    }
    
    var body: some View {
        if let settings = ogs.remoteSettings[.preferredGameSettings], settings.count > 0 {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                    Section {
                        ForEach(Array(settings.enumerated()), id: \.0) { _, setting in
                            VStack {
                                ChallengeCell(challenge: setting)
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
                            }
                            .padding(.bottom, 5)
                            .background(cardBackground)
                        }
                    }
                }
                .padding()
            }
        } else {
            Text("No saved preferred settings.")
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
