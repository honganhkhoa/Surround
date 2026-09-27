/// The current task is independent of the layout presenting it. A wide layout
/// can show analysis and a chat composer together; a compact one shows the panel
/// where the user most recently interacted, without discarding analysis work.
enum GameDetailPanel: Hashable {
    case playerInfo
    case chat
    case analyze
}

struct GameDetailInteraction: Equatable {
    private(set) var panel: GameDetailPanel
    private(set) var isAnalyzing: Bool
    // A temporary chat presentation does not end the analysis session.
    // Explicit exits reset it even when a preview has already hidden Analyze.
    private(set) var analysisResetRevision = 0

    init(panel: GameDetailPanel = .playerInfo) {
        self.panel = panel
        isAnalyzing = panel == .analyze
    }

    mutating func selectPanel(_ panel: GameDetailPanel) {
        self.panel = panel
        isAnalyzing = panel == .analyze
        if !isAnalyzing {
            analysisResetRevision += 1
        }
    }

    mutating func setAnalyzing(_ analyzing: Bool) {
        isAnalyzing = analyzing
        if analyzing {
            panel = .analyze
        } else {
            analysisResetRevision += 1
            if panel == .analyze {
                panel = .playerInfo
            }
        }
    }

    mutating func beginChatInteraction() {
        panel = .chat
    }

    mutating func beginChatPreview() {
        panel = .chat
        isAnalyzing = false
    }
}
