import SwiftUI
import SafariServices

struct PlayerAboutView: View {
    @EnvironmentObject private var navigation: StackRouter
    @EnvironmentObject private var appNavigation: NavigationService
    @EnvironmentObject private var ogs: OGSService
    @Environment(\.openURL) private var openURL
    let profile: OGSPlayerProfile
    private let baseURL: URL
    private let document: ProfileBiographyDocument

    init(profile: OGSPlayerProfile) {
        self.profile = profile
        baseURL = URL(string: OGSService.ogsRoot)!.appendingPathComponent("player").appendingPathComponent(String(profile.id))
        document = ProfileBiographyDocument(source: profile.about ?? "", baseURL: baseURL)
    }

    @State private var scrollOffset: CGFloat = 0
    @State private var browserURL: BiographyBrowserURL?

    var body: some View {
        VStack(spacing: 0) {
            ProfileBiographyWebView(fragment: document.bodyHTML, baseURL: baseURL,
                height: .constant(1), scrollOffset: $scrollOffset, onLink: openLink)
        }
        .accessibilityElement(children: .contain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("profile.about.title")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.screenPlayerAbout)
            #if !targetEnvironment(macCatalyst)
            .sheet(item: $browserURL) { item in BiographySafariView(url: item.url) }
            #endif
    }

    private func openLink(_ url: URL) {
        switch ProfileBiographyLinkTarget.resolve(url, baseURL: baseURL) {
        case .player(let id): navigation.openProfile(playerID: id)
        case .game(let id): navigation.openGame(gameID: id, using: appNavigation, service: ogs)
        case .external(let url): presentExternal(url)
        case .fragment(let fragment):
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
            components?.fragment = fragment
            if let url = components?.url { presentExternal(url) }
        case nil:
            break
        }
    }

    private func presentExternal(_ url: URL) {
        #if targetEnvironment(macCatalyst)
        openURL(url)
        #else
        if url.scheme?.lowercased() == "mailto" { openURL(url) }
        else { browserURL = BiographyBrowserURL(url: url) }
        #endif
    }

}

struct PlayerBiographySummary: View {
    @EnvironmentObject private var navigation: StackRouter
    let profile: OGSPlayerProfile
    private let baseURL: URL
    private let document: ProfileBiographyDocument

    init(profile: OGSPlayerProfile) {
        self.profile = profile
        baseURL = URL(string: OGSService.ogsRoot)!.appendingPathComponent("player").appendingPathComponent(String(profile.id))
        document = ProfileBiographyDocument(source: profile.about ?? "", baseURL: baseURL)
    }

    @State private var height: CGFloat = 64

    var body: some View {
        if !document.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ProfileBiographyWebView(fragment: document.summaryHTML, baseURL: baseURL,
                    isSummary: true, height: $height, scrollOffset: .constant(0),
                    onLink: { _ in navigation.openAbout(profile) })
                    .frame(height: height)
                Button { navigation.openAbout(profile) } label: {
                    HStack {
                        Text("profile.about.title")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(minHeight: 32)
                }
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileAbout)
            }
            .profileContentMargins()
            .padding(.bottom, 12)
        }
    }

}

private struct BiographyBrowserURL: Identifiable {
    let url: URL
    var id: URL { url }
}

#if !targetEnvironment(macCatalyst)
private struct BiographySafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
