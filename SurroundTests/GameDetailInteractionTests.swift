import XCTest

final class GameDetailInteractionTests: XCTestCase {
    func testComposingChoosesChatWithoutDiscardingWideAnalysis() {
        var interaction = GameDetailInteraction(panel: .analyze)
        let revision = interaction.analysisResetRevision
        interaction.beginChatInteraction()
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertTrue(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
    }

    func testPreviewHidesAnalysisWithoutResettingItsSession() {
        var interaction = GameDetailInteraction(panel: .analyze)
        let revision = interaction.analysisResetRevision
        interaction.beginChatPreview()
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision)

        interaction.selectPanel(.analyze)
        XCTAssertTrue(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
    }

    func testExplicitNonAnalysisPanelSelectionEndsTheAnalysisSession() {
        for panel in [GameDetailPanel.playerInfo, .chat] {
            var interaction = GameDetailInteraction(panel: .analyze)
            interaction.beginChatInteraction()
            let revision = interaction.analysisResetRevision
            interaction.selectPanel(panel)
            XCTAssertFalse(interaction.isAnalyzing)
            XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
            interaction.selectPanel(.analyze)
            XCTAssertTrue(interaction.isAnalyzing)
            XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
        }
    }

    func testTurningOffWideAnalysisKeepsAnActiveComposerVisible() {
        var interaction = GameDetailInteraction(panel: .analyze)
        interaction.beginChatInteraction()
        let revision = interaction.analysisResetRevision
        interaction.setAnalyzing(false)
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
    }

    func testTurningOffAnalysisReturnsToPlayerInfoAndEndsItsSession() {
        var interaction = GameDetailInteraction(panel: .analyze)
        let revision = interaction.analysisResetRevision
        interaction.setAnalyzing(false)
        XCTAssertEqual(interaction.panel, .playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
    }

    func testLeavingPreviewExplicitlyEndsTheSuspendedAnalysisSession() {
        var interaction = GameDetailInteraction(panel: .analyze)
        interaction.beginChatPreview()
        let revision = interaction.analysisResetRevision
        interaction.selectPanel(.playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
    }
}
