/// Every layout presents the same single panel. Switching tasks changes only
/// presentation; their retained analysis work and chat draft belong to the game.
enum GameDetailPanel: Hashable {
    case playerInfo
    case chat
    case analyze
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
