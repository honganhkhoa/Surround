import XCTest

final class AppReviewGameActivityTests: XCTestCase {
    func testConfirmsSubmittedMoveAfterOpponentHasReplied() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let submitted = try initial.makeMove(move: .placeStone(2, 2))
        let opponentReply = try submitted.makeMove(move: .placeStone(6, 6))

        for confirmed in [submitted, opponentReply] {
            XCTAssertTrue(AppReviewGameActivity.confirmsSubmittedMove(
                .placeStone(2, 2), moveNumber: 1,
                from: initial, in: confirmed
            ))
        }
    }

    func testRejectsDifferentMoveAndUnchangedOrUndonePosition() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let differentMove = try initial.makeMove(move: .placeStone(3, 3))
        let submitted = try initial.makeMove(move: .placeStone(2, 2))

        for unrelated in [initial, differentMove, submitted.previousPosition!] {
            XCTAssertFalse(AppReviewGameActivity.confirmsSubmittedMove(
                .placeStone(2, 2), moveNumber: 1,
                from: initial, in: unrelated
            ))
        }
        XCTAssertFalse(AppReviewGameActivity.confirmsSubmittedMove(
            .placeStone(2, 2), moveNumber: 2,
            from: initial, in: submitted
        ))
    }

    func testRejectsSameMoveOnDifferentBranchOrByDifferentColor() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let differentBoard = BoardPosition(width: 9, height: 9)
        differentBoard.putStone(row: 8, column: 8, color: .white)
        let differentTurn = BoardPosition(width: 9, height: 9)
        differentTurn.nextToMove = .white

        for predecessor in [differentBoard, differentTurn] {
            let unrelated = try predecessor.makeMove(move: .placeStone(2, 2))
            XCTAssertFalse(AppReviewGameActivity.confirmsSubmittedMove(
                .placeStone(2, 2), moveNumber: 1,
                from: initial, in: unrelated
            ))
        }
    }

    func testConfirmsPassWithMatchingMoveNumberAndAncestry() throws {
        let initial = BoardPosition(width: 9, height: 9)
        let pass = try initial.makeMove(move: .pass)
        let opponentReply = try pass.makeMove(move: .placeStone(2, 2))

        XCTAssertTrue(AppReviewGameActivity.confirmsSubmittedMove(
            .pass, moveNumber: 1, from: initial, in: opponentReply
        ))
        XCTAssertFalse(AppReviewGameActivity.confirmsSubmittedMove(
            .pass, moveNumber: 2, from: pass, in: opponentReply
        ))
    }

    func testEquivalentReconstructedPredecessorIsAccepted() throws {
        let original = try BoardPosition(width: 9, height: 9)
            .makeMove(move: .placeStone(2, 2))
        let reconstructed = try BoardPosition(width: 9, height: 9)
            .makeMove(move: .placeStone(2, 2))
        let confirmed = try reconstructed.makeMove(move: .placeStone(6, 6))

        XCTAssertFalse(original === reconstructed)
        XCTAssertTrue(AppReviewGameActivity.confirmsSubmittedMove(
            .placeStone(6, 6), moveNumber: 2,
            from: original, in: confirmed
        ))
    }

    func testUnknownAndIncompleteFinishedDataDoNotReplaceOngoingBaseline() {
        XCTAssertNil(AppReviewGameActivity.phase(
            nil, authoritativePhase: nil, outcome: nil
        ))
        XCTAssertNil(AppReviewGameActivity.phase(
            .finished, authoritativePhase: .play, outcome: "Resignation"
        ))
        let emptyOutcomes: [String?] = [nil, "", " \n "]
        for outcome in emptyOutcomes {
            XCTAssertNil(AppReviewGameActivity.phase(
                .finished, authoritativePhase: .finished, outcome: outcome
            ))
        }
    }

    func testPlayingScoringAndFinishedHistoryClassification() {
        XCTAssertEqual(AppReviewGameActivity.phase(
            .play, authoritativePhase: .play, outcome: nil
        ), .playing)
        XCTAssertEqual(AppReviewGameActivity.phase(
            .stoneRemoval, authoritativePhase: .play, outcome: nil
        ), .scoring)

        // Classification alone does not establish participant activity: the
        // coordinator rejects finished history without an ongoing baseline.
        for outcome in ["Resignation", "2.5", "Timeout"] {
            XCTAssertEqual(AppReviewGameActivity.phase(
                .finished, authoritativePhase: .finished, outcome: outcome
            ), .finished)
        }
    }

    func testCancellationOutcomeNeverClassifiesAsCompletedGame() {
        for outcome in ["Cancellation", "Canceled", "Cancelled", " CANCELLATION\n"] {
            XCTAssertEqual(AppReviewGameActivity.phase(
                .finished, authoritativePhase: .finished, outcome: outcome
            ), .cancelled)
        }
    }
}
