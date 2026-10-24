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
    @EnvironmentObject private var stackRouter: StackRouter
    @Environment(\.colorScheme) private var colorScheme

    private let preferredSettingsOverride: [OGSChallengeTemplate]?
    
    @State var openChallengeCancellableBySetting: [OGSChallengeTemplate: AnyCancellable] = [:]
    @State var deleteSettingCancellableBySetting: [OGSChallengeTemplate: AnyCancellable] = [:]
    @State var settingBeingEdited: OGSChallengeTemplate?
    @State var creatingNewPreferredSetting = false

    /// `startsCreatingNewSetting` opens straight on the new-setting form, as
    /// Home's "Add a preferred setting…" does.
    init(
        preferredSettingsOverride: [OGSChallengeTemplate]? = nil,
        startsCreatingNewSetting: Bool = false
    ) {
        self.preferredSettingsOverride = preferredSettingsOverride
        _creatingNewPreferredSetting = State(initialValue: startsCreatingNewSetting)
    }
    
    var cardBackground: some View {
        Color(
            colorScheme == .light ? UIColor.systemBackground : UIColor.systemGray5
        )
        .shadow(radius: 2)
    }
    
    @ViewBuilder
    private func cardIconButton(
        systemName: String,
        foreground: Color,
        background: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(background)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(foreground)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(foreground)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preferredSettingsContent: some View {
        let settings = preferredSettingsOverride
            ?? ogs.remoteSettings[.preferredGameSettings]
            ?? []
        if !settings.isEmpty {
            preferredSettingsList(settings)
        } else {
            Button(action: {
                creatingNewPreferredSetting = true
            }) {
                Text("Add your preferred game settings to create a game with the exact settings you want faster.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    private func preferredSettingsList(_ settings: [OGSChallengeTemplate]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 15, alignment: .top)], spacing: 15) {
                Section {
                    ForEach(Array(settings.enumerated()), id: \.0) { index, setting in
                        preferredSettingCard(setting)
                            .accessibilityIdentifier(
                                SurroundUITestContract.AccessibilityID
                                    .preferredSetting(index)
                            )
                    }
                }
            }
            .padding()
        }
    }

    private func preferredSettingCard(_ setting: OGSChallengeTemplate) -> some View {
        VStack {
            ZStack(alignment: .topTrailing) {
                ChallengeCell(challenge: setting, hidePlayerDetails: true)
                    .padding()
                HStack(spacing: 8) {
                    if !setting.rengo {
                        cardIconButton(
                            systemName: "pencil",
                            foreground: .accentColor,
                            background: Color(UIColor.systemGray6)
                        ) {
                            settingBeingEdited = setting
                        }
                    }
                    cardIconButton(
                        systemName: "trash",
                        foreground: .red,
                        background: Color.red.opacity(0.14),
                        isLoading: self.deleteSettingCancellableBySetting[setting] != nil
                    ) {
                        self.deleteSettingCancellableBySetting[setting] = ogs.removePreferredGameSetting(challenge: setting).sink(
                            receiveCompletion: { _ in
                                self.deleteSettingCancellableBySetting.removeValue(forKey: setting)
                            },
                            receiveValue: { _ in }
                        )
                    }
                    .disabled(self.deleteSettingCancellableBySetting[setting] != nil)
                }
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
            Divider()
            Button(action: {
                createChallenge(for: setting, opponent: nil)
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
                Button(action: {
                    let submit = challengeSubmission(for: setting)
                    stackRouter.openSavedSettingsOpponentPicker { submit($0) }
                }) {
                    HStack {
                        Text("Select your opponent ")
                        Spacer()
                        Image(systemName: "chevron.forward")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                }
                .disabled(self.openChallengeCancellableBySetting[setting] != nil)
            }
        }
        .padding(.bottom, 5)
        .background(cardBackground)
    }

    private func createChallenge(for setting: OGSChallengeTemplate, opponent: OGSUser?) {
        challengeSubmission(for: setting)(opponent)
    }

    private func challengeSubmission(for setting: OGSChallengeTemplate) -> (OGSUser?) -> Void {
        let appNavigation = nav
        return preferredSettingChallengeSubmission(
            for: setting, using: ogs, requests: $openChallengeCancellableBySetting
        ) {
            appNavigation.home.showingPreferredSettings = false
        }
    }

    var body: some View {
        preferredSettingsContent
            .accessibilityIdentifier(
                SurroundUITestContract.AccessibilityID.screenPreferredSettings
            )
            .onAppear {
                ogs.subscribeToSeekGraph()
            }
            .onDisappear {
                ogs.unsubscribeFromSeekGraphWhenDone()
            }
            .appNavigationDestination(isPresented: $creatingNewPreferredSetting) {
                CustomGameForm(mode: .createPreferredSetting)
                    .navigationTitle("New preferred setting")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .appNavigationDestination(isPresented: Binding(
                get: { settingBeingEdited != nil },
                set: { isActive in
                    if !isActive {
                        settingBeingEdited = nil
                    }
                }
            )) {
                if let settingBeingEdited {
                    CustomGameForm(
                        initialChallenge: settingBeingEdited,
                        mode: .editPreferredSetting(original: settingBeingEdited)
                    )
                    .navigationTitle("Edit preferred setting")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        creatingNewPreferredSetting = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
    }
}

/// Sends a saved setting as a challenge, open or to one opponent, at most
/// one request per setting at a time. Each send holds the seek graph until
/// its challenge shows up there (see `SeekGraphSendHold`). The stack retains
/// the result while an opponent picker is open, so it captures only its
/// dependencies.
func preferredSettingChallengeSubmission(
    for setting: OGSChallengeTemplate,
    using service: OGSService,
    requests: Binding<[OGSChallengeTemplate: AnyCancellable]>,
    onSent: @escaping () -> Void
) -> (OGSUser?) -> Void {
    return { opponent in
        guard requests.wrappedValue[setting] == nil else { return }
        let hold = SeekGraphSendHold(service: service)
        requests.wrappedValue[setting] = service.sendChallenge(opponent: opponent, challenge: setting)
            .handleEvents(receiveCancel: { hold.release() })
            .sink(
                receiveCompletion: { completion in
                    requests.wrappedValue.removeValue(forKey: setting)
                    if case .failure = completion { hold.release() }
                },
                receiveValue: { challengeID in
                    hold.challengeSent(id: challengeID, isOpen: opponent == nil)
                    onSent()
                }
            )
    }
}

#if DEBUG
private var preferredSettingsPreviewFixture: [OGSChallengeTemplate] {
    [
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
}

private func preferredSettingsPreview(
    settings: [OGSChallengeTemplate]
) -> some View {
    let user = OGSUser(username: "honganhkhoa", id: 1526)
    let nav = NavigationService()
    return AppNavigationStack {
        PreferredSettingsView(preferredSettingsOverride: settings)
            .navigationTitle("Preferred settings")
    }
    .environmentObject(
        OGSService.previewInstance(
            user: user,
            preferredGameSettings: settings
        )
    )
    .environmentObject(nav)
}

#Preview("Preferred settings — Saved setting") {
    preferredSettingsPreview(settings: preferredSettingsPreviewFixture)
}

#Preview("Preferred settings — Empty") {
    preferredSettingsPreview(settings: [])
}
#endif
