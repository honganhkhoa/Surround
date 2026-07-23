//
//  OGSUserTests.swift
//  SurroundTests
//

import XCTest

final class OGSUserTests: XCTestCase {
    // English abbreviates "%lldkyu"/"%llddan" to "%lldk"/"%lldd" in the catalog,
    // which the unit-test bundle cannot resolve, so those expectations are built
    // through String(localized:) to stay correct in the shipping app too. The
    // long "Kyu"/"Dan" and pro "p" forms are source-language identical.

    func testRankAndRatingConversionsAreInverses() {
        for rank in [5.0, 17.9, 24.0, 30.0, 38.0] {
            XCTAssertEqual(RankUtils.rank(fromRating: RankUtils.rating(fromRank: rank)), rank, accuracy: 1e-9)
        }
    }

    func testRankFromRatingClampsToTheSupportedRatingRange() {
        XCTAssertEqual(RankUtils.rank(fromRating: 50), RankUtils.rank(fromRating: 100))
        XCTAssertEqual(RankUtils.rank(fromRating: 10_000), RankUtils.rank(fromRating: 6000))
    }

    func testFormattedRankBoundaries() {
        XCTAssertEqual(RankUtils.formattedRank(25), kyu(5))
        XCTAssertEqual(RankUtils.formattedRank(25, longFormat: true), "5 Kyu")
        XCTAssertEqual(RankUtils.formattedRank(29.9), kyu(1))
        XCTAssertEqual(RankUtils.formattedRank(30), dan(1))
        XCTAssertEqual(RankUtils.formattedRank(30, longFormat: true), "1 Dan")
        XCTAssertEqual(RankUtils.formattedRank(37.5), dan(8))

        // Out-of-range ranks are clamped to 25 kyu and 9 dan.
        XCTAssertEqual(RankUtils.formattedRank(2), kyu(25))
        XCTAssertEqual(RankUtils.formattedRank(45), dan(9))

        XCTAssertEqual(RankUtils.formattedRank(40, professional: true), "4p")
        XCTAssertEqual(RankUtils.formattedRank(1037, professional: true), "1p")
        XCTAssertEqual(RankUtils.formattedRank(-950), "?")
    }

    func testUserRankFallsBackToTheDefaultRatingWithoutRatings() {
        let user = OGSUser(username: "nobody", id: 1)
        XCTAssertEqual(user.rank(), 24)
    }

    func testUserFormattedRankUsesRatingsAndProvisionalState() {
        let established = user(rating: 1510, deviation: 120)
        XCTAssertEqual(established.formattedRank(), kyu(6))

        let provisionalByDeviation = user(rating: 1510, deviation: 350)
        XCTAssertEqual(provisionalByDeviation.formattedRank(), "?")

        var provisionalByUIClass = user(rating: 1510, deviation: 120)
        provisionalByUIClass.uiClass = "provisional"
        XCTAssertEqual(provisionalByUIClass.formattedRank(), "?")

        var professional = user(rating: 1510, deviation: 120)
        professional.professional = true
        professional.ranking = 40
        XCTAssertEqual(professional.formattedRank(), "4p")
    }

    /// formattedRank must honour its `category` and `longFormat` arguments even
    /// when the user carries ratings (previously both were ignored on that path).
    func testFormattedRankHonoursCategoryAndLongFormatArguments() {
        let multiCategory = OGSUser(
            username: "player",
            id: 1,
            ratings: OGSRating(ratingByCategory: [
                .overall: OGSCategoryRating(rating: 1510, deviation: 120, volatility: 0.06),
                .overall_9x9: OGSCategoryRating(rating: 3000, deviation: 120, volatility: 0.06)
            ])
        )

        XCTAssertEqual(multiCategory.formattedRank(), kyu(6))
        XCTAssertEqual(multiCategory.formattedRank(category: .overall_9x9), dan(9))
        XCTAssertEqual(multiCategory.formattedRank(longFormat: true), "6 Kyu")
    }

    private func kyu(_ rank: Int) -> String {
        String(localized: "\(rank)kyu")
    }

    private func dan(_ rank: Int) -> String {
        String(localized: "\(rank)dan")
    }

    private func user(rating: Double, deviation: Double) -> OGSUser {
        OGSUser(
            username: "player",
            id: 1,
            ratings: OGSRating(ratingByCategory: [
                .overall: OGSCategoryRating(rating: rating, deviation: deviation, volatility: 0.06)
            ])
        )
    }
}
