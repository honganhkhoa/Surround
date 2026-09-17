//
//  ProfileRatingTests.swift
//  SurroundTests
//

import XCTest

final class ProfileRatingTests: XCTestCase {
    func testProfileCategoriesIncludeAllSevenAggregatesInDisplayOrder() {
        XCTAssertEqual(ProfileRatingCategory.allCases.map(\.rawValue), [
            "overall", "9x9", "13x13", "19x19", "blitz", "live", "correspondence"
        ])
        XCTAssertEqual(ProfileRatingCategory.allCases.map(\.ogsCategory.rawValue), [
            "overall", "9x9", "13x13", "19x19", "blitz", "live", "correspondence"
        ])
    }

    func testMissingCategoryDoesNotUseStartingRatingOrOverallData() {
        let user = user(ratings: [.overall: rating(1800, deviation: 60)])
        let missing = ProfileRating(user: user, category: .thirteenByThirteen)
        XCTAssertFalse(missing.hasData)
        XCTAssertFalse(missing.isProvisional)
        XCTAssertEqual(missing.rankText(), "—")
        XCTAssertEqual(missing.ratingText, "—")
        XCTAssertNil(missing.rankDeviation)
        XCTAssertNil(missing.likelyRankRange)
    }

    func testProvisionalStateUsesSelectedCategoryInsteadOfOverall() {
        let user = user(ratings: [
            .overall: rating(1800, deviation: 60),
            .blitz_overall: rating(1500, deviation: 200),
            .live_overall: rating(1700, deviation: 159.99),
            .overall_13x13: rating(1500, deviation: 160)
        ])
        XCTAssertFalse(ProfileRating(user: user, category: .overall).isProvisional)
        XCTAssertTrue(ProfileRating(user: user, category: .blitz).isProvisional)
        XCTAssertEqual(ProfileRating(user: user, category: .blitz).rankText(), "?")
        XCTAssertFalse(ProfileRating(user: user, category: .live).isProvisional)
        XCTAssertTrue(ProfileRating(user: user, category: .thirteenByThirteen).isProvisional)
    }

    func testEstablishedCategoryRemainsVisibleWhenOverallIsProvisional() {
        var user = user(ratings: [
            .overall: rating(1500, deviation: 350),
            .overall_9x9: rating(1510, deviation: 100)
        ])
        user.uiClass = "provisional"
        let established = ProfileRating(user: user, category: .nineByNine)
        XCTAssertFalse(established.isProvisional)
        XCTAssertEqual(established.rankText(), RankUtils.formattedRank(24))
        XCTAssertEqual(established.rankText(longFormat: true), "6 Kyu")
    }

    func testDeviationAndLikelyRangeUseOGSConversionOnTheActualRating() {
        let result = ProfileRating(
            user: user(ratings: [.overall: rating(1500, deviation: 350)]),
            category: .overall
        )
        XCTAssertEqual(result.rankDeviation!, RankUtils.rank(fromRating: 1850) - RankUtils.rank(fromRating: 1500), accuracy: 1e-10)
        let lower = RankUtils.formattedRank(floor(RankUtils.rank(fromRating: 1150)))
        let upper = RankUtils.formattedRank(floor(RankUtils.rank(fromRating: 1850)))
        XCTAssertEqual(result.likelyRankRange, "\(lower)–\(upper)")
        XCTAssertEqual(result.ratingText, "1500")
        XCTAssertEqual(result.ratingDeviationText, "350")
    }

    func testThirteenByThirteenCategoriesRoundTripThroughWireDecoding() throws {
        let json = """
        {"overall":{"rating":1800,"deviation":60,"volatility":0.06},
         "13x13":{"rating":1600,"deviation":70,"volatility":0.06},
         "live-13x13":{"rating":1550,"deviation":80,"volatility":0.06},
         "blitz-13x13":{"rating":1500,"deviation":90,"volatility":0.06},
         "correspondence-13x13":{"rating":1650,"deviation":100,"volatility":0.06}}
        """
        let decoded = try JSONDecoder().decode(OGSRating.self, from: Data(json.utf8))
        XCTAssertEqual(decoded[.overall_13x13]?.rating, 1600)
        XCTAssertEqual(decoded[.live_13x13]?.rating, 1550)
        XCTAssertEqual(decoded[.blitz_13x13]?.rating, 1500)
        XCTAssertEqual(decoded[.correspondence_13x13]?.rating, 1650)
        let roundTrip = try JSONDecoder().decode(OGSRating.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    func testNumericRatingsRoundHalfwayValuesAwayFromZeroLikeOGS() {
        let result = ProfileRating(
            user: user(ratings: [.overall: rating(1500.5, deviation: 60.5)]),
            category: .overall
        )
        XCTAssertEqual(result.ratingText, "1501")
        XCTAssertEqual(result.ratingDeviationText, "61")
    }

    func testInvalidNumbersDoNotBecomePlausibleRanks() {
        for invalid in [rating(.nan, deviation: 60), rating(1500, deviation: .infinity), rating(1500, deviation: -1)] {
            XCTAssertFalse(ProfileRating(user: user(ratings: [.overall: invalid]), category: .overall).hasData)
        }
    }

    private func user(ratings: [OGSRatingCategory: OGSCategoryRating]) -> OGSUser {
        OGSUser(username: "RatedPlayer", id: 42, ratings: OGSRating(ratingByCategory: ratings))
    }

    private func rating(_ rating: Double, deviation: Double) -> OGSCategoryRating {
        OGSCategoryRating(rating: rating, deviation: deviation, volatility: 0.06)
    }
}
