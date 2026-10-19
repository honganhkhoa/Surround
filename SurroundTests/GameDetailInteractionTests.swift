import XCTest

final class GameDetailInteractionTests: XCTestCase {
    func testPlayStartsWithBothPanelsClosed() {
        let interaction = GameDetailInteraction()
        XCTAssertEqual(interaction.panel, .playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertFalse(interaction.isChatVisible)
    }

    func testChatReplacesAnalysisWithoutResettingItsWork() {
        var interaction = GameDetailInteraction(panel: .analyze)
        let revision = interaction.analysisResetRevision
        interaction.setChatVisible(true)
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertTrue(interaction.isChatVisible)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
    }

    func testAnalysisReplacesChatWithoutRestoringItWhenClosed() {
        var interaction = GameDetailInteraction(panel: .chat)
        let revision = interaction.analysisResetRevision
        interaction.setAnalyzing(true)
        XCTAssertEqual(interaction.panel, .analyze)
        XCTAssertTrue(interaction.isAnalyzing)
        XCTAssertFalse(interaction.isChatVisible)
        interaction.setAnalyzing(false)
        XCTAssertEqual(interaction.panel, .playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertFalse(interaction.isChatVisible)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
    }

    func testClosingChatReturnsToPlayAndPreservesAnalysisWork() {
        var interaction = GameDetailInteraction(panel: .analyze)
        let revision = interaction.analysisResetRevision
        interaction.setChatVisible(true)
        interaction.setChatVisible(false)
        XCTAssertEqual(interaction.panel, .playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertFalse(interaction.isChatVisible)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
        interaction.setAnalyzing(true)
        XCTAssertEqual(interaction.analysisResetRevision, revision)
    }

    func testDisablingAnInactivePanelDoesNotChangeTheActiveTask() {
        var interaction = GameDetailInteraction(panel: .chat)
        interaction.setAnalyzing(false)
        XCTAssertEqual(interaction.panel, .chat)
        interaction.setAnalyzing(true)
        interaction.setChatVisible(false)
        XCTAssertEqual(interaction.panel, .analyze)
        XCTAssertEqual(interaction.analysisResetRevision, 0)
    }

    func testChatInteractionAndPreviewReplaceAnalysisWithoutReset() {
        var interaction = GameDetailInteraction(panel: .analyze)
        interaction.beginChatInteraction()
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertFalse(interaction.isAnalyzing)
        interaction.selectPanel(.analyze)
        interaction.beginChatPreview()
        XCTAssertEqual(interaction.panel, .chat)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertEqual(interaction.analysisResetRevision, 0)
    }

    func testSelectingPanelsPreservesRetainedWorkAcrossEveryTransition() {
        var interaction = GameDetailInteraction()
        for panel in [GameDetailPanel.analyze, .chat, .playerInfo, .analyze] {
            interaction.selectPanel(panel)
            XCTAssertEqual(interaction.panel, panel)
            XCTAssertEqual(interaction.isAnalyzing, panel == .analyze)
            XCTAssertEqual(interaction.isChatVisible, panel == .chat)
            XCTAssertEqual(interaction.analysisResetRevision, 0)
        }
    }

    func testAccountOrSpeedResetClosesThePanelWithObservableRevision() {
        var interaction = GameDetailInteraction(panel: .analyze)
        interaction.setChatVisible(true)
        let revision = interaction.analysisResetRevision
        interaction.resetPanels()
        XCTAssertEqual(interaction.panel, .playerInfo)
        XCTAssertFalse(interaction.isAnalyzing)
        XCTAssertFalse(interaction.isChatVisible)
        XCTAssertEqual(interaction.analysisResetRevision, revision + 1)
        // A second context change must also invalidate work retained in Play.
        interaction.resetPanels()
        XCTAssertEqual(interaction.analysisResetRevision, revision + 2)
    }
}
