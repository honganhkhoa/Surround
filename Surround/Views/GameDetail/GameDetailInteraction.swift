/// Every layout presents the same single panel. Switching tasks changes only
/// presentation; their retained analysis work and chat draft belong to the game.
enum GameDetailPanel: Hashable {
    case playerInfo
    case chat
    case analyze
}

/// Game Detail reopens the Chat panel the user last left open at regular
/// width, once per route, once it has measured its width. Until then, what
/// follows the panel counts that Chat panel as open, so the first frames
/// already agree with the ones after it opens.
struct GameDetailChatRestore: Equatable {
    /// The route has restored already, or measured a compact width.
    var hasRestored: Bool
    /// The Chat panel was open when the user last left a regular layout.
    var remembersChat: Bool
    /// The layout it would open into is compact: the measured width's, or,
    /// before Game Detail has measured, the size class's.
    var isCompact: Bool

    /// Chat opens, from Play, once Game Detail has measured its width.
    func opensChat(from panel: GameDetailPanel) -> Bool {
        !hasRestored && remembersChat && !isCompact && panel == .playerInfo
    }
}

struct GameDetailInteraction: Equatable {
    private(set) var panel: GameDetailPanel
    var isAnalyzing: Bool { panel == .analyze }
    var isChatVisible: Bool { panel == .chat }
    // Context changes reset retained work even when Analyze is not visible.
    private(set) var analysisResetRevision = 0

    init(panel: GameDetailPanel = .playerInfo) {
        self.panel = panel
    }

    mutating func selectPanel(_ panel: GameDetailPanel) {
        self.panel = panel
    }

    mutating func setAnalyzing(_ analyzing: Bool) {
        if analyzing {
            panel = .analyze
        } else if isAnalyzing {
            panel = .playerInfo
        }
    }

    mutating func setChatVisible(_ visible: Bool) {
        if visible {
            panel = .chat
        } else if panel == .chat {
            panel = .playerInfo
        }
    }

    /// Reset presentation intent on account or game-speed transitions. Preserve
    /// a monotonic revision so the retained game owner observes the reset.
    mutating func resetPanels() {
        panel = .playerInfo
        analysisResetRevision += 1
    }

    mutating func beginChatInteraction() {
        setChatVisible(true)
    }

    mutating func beginChatPreview() {
        setChatVisible(true)
    }
}
