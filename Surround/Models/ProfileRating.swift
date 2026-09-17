//
//  ProfileRating.swift
//  Surround
//

import Foundation

enum ProfileRatingCategory: String, CaseIterable, Identifiable {
    case overall
    case nineByNine = "9x9"
    case thirteenByThirteen = "13x13"
    case nineteenByNineteen = "19x19"
    case blitz
    case live
    case correspondence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overall: String(localized: "Overall")
        case .nineByNine: "9×9"
        case .thirteenByThirteen: "13×13"
        case .nineteenByNineteen: "19×19"
        case .blitz: String(localized: "Blitz")
        case .live: String(localized: "Live")
        case .correspondence: String(localized: "Correspondence")
        }
    }

    var ogsCategory: OGSRatingCategory {
        switch self {
        case .overall: .overall
        case .nineByNine: .overall_9x9
        case .thirteenByThirteen: .overall_13x13
        case .nineteenByNineteen: .overall_19x19
        case .blitz: .blitz_overall
        case .live: .live_overall
        case .correspondence: .correspondence_overall
        }
    }
}

/// Current category data must stay distinct from OGS's fallback starting rating.
/// A missing category represents no rated games, not an estimated 1500 rating.
struct ProfileRating: Equatable {
    let category: ProfileRatingCategory
    let rating: OGSCategoryRating?

    init(user: OGSUser, category: ProfileRatingCategory) {
        self.category = category
        if let rating = user.ratings?[category.ogsCategory],
           rating.rating.isFinite, rating.deviation.isFinite,
           rating.deviation >= 0 {
            self.rating = rating
        } else {
            rating = nil
        }
    }

    var hasData: Bool { rating != nil }

    var isProvisional: Bool {
        guard let rating else { return false }
        return rating.deviation >= 160
    }

    var rankDeviation: Double? {
        guard let rating else { return nil }
        return RankUtils.rank(fromRating: rating.rating + rating.deviation)
            - RankUtils.rank(fromRating: rating.rating)
    }

    var likelyRankRange: String? {
        guard let rating else { return nil }
        let lower = RankUtils.formattedRank(floor(RankUtils.rank(fromRating: rating.rating - rating.deviation)))
        let upper = RankUtils.formattedRank(floor(RankUtils.rank(fromRating: rating.rating + rating.deviation)))
        return "\(lower)–\(upper)"
    }

    func rankText(longFormat: Bool = false) -> String {
        guard let rating else { return "—" }
        guard !isProvisional else { return "?" }
        return RankUtils.formattedRank(
            floor(RankUtils.rank(fromRating: rating.rating)),
            longFormat: longFormat
        )
    }

    var ratingText: String {
        guard let rating else { return "—" }
        return rating.rating.rounded(.toNearestOrAwayFromZero)
            .formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }

    var ratingDeviationText: String? {
        rating?.deviation.rounded(.toNearestOrAwayFromZero)
            .formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }

    var rankDeviationText: String? {
        guard let rankDeviation else { return nil }
        return ((rankDeviation * 10).rounded(.toNearestOrAwayFromZero) / 10)
            .formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }
}
