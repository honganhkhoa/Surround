//
//  WelcomeView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 25/03/2021.
//

import SwiftUI
import Combine

struct WelcomeView: View {
    @Environment(\.surroundAllowsRemoteActivity) private var allowsRemoteActivity
    @EnvironmentObject var ogs: OGSService
    @State var publicGames = [Game]()
    private let animatesPublicGameChanges: Bool

    init(
        publicGames: [Game] = [],
        animatesPublicGameChanges: Bool = true
    ) {
        _publicGames = State(initialValue: publicGames)
        self.animatesPublicGameChanges = animatesPublicGameChanges
    }
    
    @State private var introductionHeight: CGFloat = 0
    private let margin: CGFloat = 16
    /// The introduction's width when the boards sit beside it.
    private let besideIntroductionWidth: CGFloat = 380
    private let boardSpacing: CGFloat = 12
    /// Below this, a board would be too small to read, so none show.
    private let minimumBoardSize: CGFloat = 160
    /// One board never grows past this, so a tall screen shows it whole
    /// without filling the page.
    private let maximumBoardSize: CGFloat = 480

    private func accountLink<Label: View>(path: String, @ViewBuilder label: () -> Label) -> some View {
        AppNavigationLink(
            destination: OGSBrowserView(
                initialURL: URL(string: "\(OGSService.ogsRoot)/\(path)")!,
                showsURLBar: true
            )
            .navigationBarTitleDisplayMode(.inline)
        ) {
            label()
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Surround is a client to play Go online with other players on the website Online-Go.com, also known as Online Go Server (OGS).")
                .font(.callout)
                .padding(.horizontal, 4)
                .modifier(HomeSceneLegibility())
            VStack(spacing: 10) {
                accountLink(path: "sign-in") {
                    Text("Sign in to your OGS account")
                }
                .modifier(HomeActionSurface())
                accountLink(path: "register") {
                    Text("Register an OGS account")
                        .modifier(HomeActionText())
                }
                .modifier(HomeCard(cornerRadius: 25))
            }
            .frame(maxWidth: 420)
            .padding(.top, 18)
            if let liveGames = ogs.sitewiseLiveGamesCount, let correspondenceGames = ogs.sitewiseCorrespondenceGamesCount {
                Text(.init(localized: "**\(correspondenceGames) correspondence games** and **\(liveGames) live games** are being played right now."))
                    .font(.subheadline)
                    .modifier(HomeSecondaryText())
                    .padding(.horizontal, 4)
                    .modifier(HomeSceneLegibility())
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private struct BoardFit {
        let columns: Int
        let side: CGFloat
    }

    /// The largest whole boards that fit side by side in the space, and how
    /// many of them; nil when even one would be too small to read.
    private func boardFit(width: CGFloat, height: CGFloat) -> BoardFit? {
        let tallest = min(height, maximumBoardSize)
        guard !publicGames.isEmpty, tallest >= minimumBoardSize, width >= minimumBoardSize else { return nil }
        let columns = min(publicGames.count, max(1, Int((width + boardSpacing) / (tallest + boardSpacing))))
        let side = min(tallest, (width - CGFloat(columns - 1) * boardSpacing) / CGFloat(columns))
        return side >= minimumBoardSize ? BoardFit(columns: columns, side: side) : nil
    }

    /// The boards beside the introduction or below it, after a gap.
    private enum BoardPlacement {
        case beside(introductionWidth: CGFloat, gap: CGFloat, fit: BoardFit)
        case below(gap: CGFloat, fit: BoardFit?)
    }

    /// The active fold of a Duo in Book, in this view's space; nil when the
    /// screen is one flat canvas (Closed, Open, and every other device).
    private func activeFold(in geometry: GeometryProxy) -> CGRect? {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            // The frame already includes the fold's interaction margins.
            return geometry.reservedRegions(kind: .division)
                .first(where: \.isActive).map(\.frame)
        }
        #endif
        return nil
    }

    /// Below the introduction or, where that gives larger boards, beside it.
    /// A fold in Book is never crossed: the boards take the right or lower
    /// screen, as the board does in Game Detail.
    private func boardPlacement(in geometry: GeometryProxy) -> BoardPlacement {
        let size = geometry.size
        let fold = activeFold(in: geometry)
        if let fold, fold.height > fold.width {
            guard let fit = boardFit(width: size.width - fold.maxX - 2 * margin,
                                     height: size.height - 2 * boardSpacing)
            else { return .below(gap: 0, fit: nil) }
            return .beside(introductionWidth: fold.minX, gap: fold.width, fit: fit)
        }
        let top = max(introductionHeight, fold?.maxY ?? 0)
        let below = boardFit(width: size.width - 2 * margin,
                             height: size.height - top - 2 * boardSpacing)
        if fold == nil,
           let beside = boardFit(width: size.width - besideIntroductionWidth - 2 * margin,
                                 height: size.height - 2 * boardSpacing),
           beside.side > (below?.side ?? 0) {
            return .beside(introductionWidth: besideIntroductionWidth, gap: 0, fit: beside)
        }
        return .below(gap: top - introductionHeight, fit: below)
    }

    private func publicGameBoards(_ fit: BoardFit) -> some View {
        HStack(spacing: boardSpacing) {
            ForEach(publicGames.prefix(fit.columns)) { game in
                BoardView(boardPosition: game.currentPosition)
                    .frame(width: fit.side, height: fit.side)
            }
        }
        .padding(.horizontal, margin)
        .padding(.vertical, boardSpacing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Games being played now", comment: "Welcome - VoiceOver: the public games shown when signed out"))
    }

    /// Signed out, Home says what Surround is, offers both ways in, and
    /// shows games being played now: just their boards, whole and as large
    /// as they fit, below the introduction or beside it, and never across a
    /// fold (canvas "Home Redesign").
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                switch boardPlacement(in: proxy) {
                case let .beside(introductionWidth, gap, fit):
                    HStack(alignment: .top, spacing: gap) {
                        introduction
                            .frame(width: introductionWidth)
                        publicGameBoards(fit)
                    }
                case let .below(gap, fit):
                    VStack(alignment: .leading, spacing: 0) {
                        introduction
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { introductionHeight = $0 }
                        if let fit {
                            publicGameBoards(fit)
                                .padding(.top, gap)
                        }
                    }
                }
            }
        }
        .background { GameDetailBackdrop().ignoresSafeArea(.container) }
        .onAppear {
            #if DEBUG && MAIN_APP
            if SurroundUITestContract.isEnabled {
                publicGames = Array(ogs.sortedPublicGames.prefix(4))
                return
            }
            #endif
            guard allowsRemoteActivity else { return }
            ogs.ensureConnect {
                ogs.subscribeToGameCount()
                ogs.cyclePublicGames()
            }
        }
        .onDisappear {
            guard allowsRemoteActivity else { return }
            ogs.unsubscribeFromGameCount()
            ogs.cancelPublicGamesCycling()
        }
        .onChange(of: ogs.sortedPublicGames) { _, games in
            guard animatesPublicGameChanges else {
                publicGames = Array(games.prefix(4))
                return
            }
            if self.publicGames.count > 0 {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = []
                }
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(2500))) {
                withAnimation(.easeInOut(duration: 2)) {
                    self.publicGames = games.shuffled()
                }
            }
        }
    }
}

#if DEBUG
private func welcomePreview() -> some View {
    let games = [
        TestData.Ongoing19x19HandicappedWithNoInitialState,
        TestData.Ongoing19x19wBot1,
    ]
    return NavigationStack {
        WelcomeView(
            publicGames: games,
            animatesPublicGameChanges: false
        )
            .navigationTitle("Welcome")
    }
    .environmentObject(
        OGSService.previewInstance(
            publicGames: games
        )
    )
    .environment(\.surroundAllowsRemoteActivity, false)
}

#Preview("Welcome — Default device") {
    welcomePreview()
}

#Preview("Welcome — Compact layout", traits: .fixedLayout(width: 320, height: 568)) {
    welcomePreview()
}
#endif
