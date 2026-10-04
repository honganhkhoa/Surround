//
//  PlayerProfileRatings.swift
//  Surround
//

import SwiftUI

struct PlayerProfileRatings: View {
    @ObservedObject private var preferences = userDefaults
    @Setting(.hidesRank) private var hidesRank: Bool
    @Setting(.profileShowsRatings) private var showsRatings: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let user: OGSUser

    private var ratings: [ProfileRating] {
        ProfileRatingCategory.allCases.map { ProfileRating(user: user, category: $0) }
    }

    var body: some View {
        if !hidesRank {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .zIndex(1)
                VStack(alignment: .leading, spacing: 8) {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibleRatings
                    } else if horizontalSizeClass == .regular {
                        regularRatings
                    } else {
                        compactRatings
                    }
                    if ratings.contains(where: \.isProvisional) {
                        Group {
                            if showsRatings {
                                Text("Gray ratings are provisional.")
                            } else {
                                Text("? means provisional — the range is where their rank likely is.")
                            }
                        }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingKey)
                    }
                }
                .profileContentMargins()
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatings)
        }
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text("Rating")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Picker("Rating display", selection: _showsRatings.binding) {
                Text("Rank").tag(false)
                Text("Rating").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 168)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingMode)
        }
        .profileContentMargins()
        .padding(.vertical, 6)
        .background(Color(.systemGray3).shadow(radius: 2))
    }

    private var compactRatings: some View {
        VStack(spacing: 6) {
            horizontalRating(ProfileRating(user: user, category: .overall))
            VStack(spacing: 0) {
                compactRow([.nineByNine, .thirteenByThirteen, .nineteenByNineteen])
                Divider()
                compactRow([.blitz, .live, .correspondence])
            }
        }
    }

    private func compactRow(_ categories: [ProfileRatingCategory]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(categories) { category in
                if category != categories.first { Divider() }
                ratingCell(ProfileRating(user: user, category: category), centered: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var regularRatings: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ratings, id: \.category) { rating in
                if rating.category == .nineByNine || rating.category == .blitz { Divider() }
                ratingCell(rating, centered: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibleRatings: some View {
        VStack(spacing: 0) {
            ForEach(ratings, id: \.category) { rating in
                if rating.category != .overall { Divider() }
                horizontalRating(rating)
            }
        }
    }

    private func horizontalRating(_ rating: ProfileRating) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(verbatim: rating.category.title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: .leading, spacing: 4) {
                inlineValue(rating)
                provisionalMarker(rating)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rating.category == .overall ? Color.indigo.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.category.title))
        .accessibilityValue(accessibilityValue(for: rating))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingCategory(rating.category.rawValue))
    }

    private func ratingCell(_ rating: ProfileRating, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 4) {
            Text(verbatim: rating.category.title)
                .font(.caption.weight(rating.category == .overall ? .semibold : .regular))
                .foregroundStyle(rating.category == .overall ? .primary : .secondary)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if centered {
                primaryValue(rating)
                supplementaryValue(rating)
            } else {
                inlineValue(rating)
            }
            provisionalMarker(rating)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .background(rating.category == .overall ? Color.indigo.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.category.title))
        .accessibilityValue(accessibilityValue(for: rating))
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingCategory(rating.category.rawValue))
    }

    private func inlineValue(_ rating: ProfileRating) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                primaryValue(rating)
                supplementaryValue(rating)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                primaryValue(rating)
                supplementaryValue(rating)
            }
        }
        .monospacedDigit()
    }

    private func primaryValue(_ rating: ProfileRating) -> some View {
        Text(verbatim: showsRatings ? rating.ratingText : rating.rankText())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(!rating.hasData || (showsRatings && rating.isProvisional) ? .secondary : .primary)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func supplementaryValue(_ rating: ProfileRating) -> some View {
        if rating.isProvisional && !showsRatings, let range = rating.likelyRankRange {
            Text(verbatim: range)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let deviation = showsRatings ? rating.ratingDeviationText : rating.rankDeviationText {
            Text("±\(deviation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func provisionalMarker(_ rating: ProfileRating) -> some View {
        if differentiateWithoutColor && showsRatings && rating.isProvisional {
            Text("Provisional")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accessibilityValue(for rating: ProfileRating) -> Text {
        guard rating.hasData else { return Text("No rated games") }
        let value = showsRatings ? rating.ratingText : rating.rankText(longFormat: true)
        let deviation = (showsRatings ? rating.ratingDeviationText : rating.rankDeviationText) ?? ""
        if rating.isProvisional {
            if !showsRatings, let range = rating.likelyRankRange {
                return Text("Provisional rank. Likely range: \(range)")
            }
            return Text("\(value) ±\(deviation). Provisional")
        }
        return Text("\(value) ±\(deviation)")
    }
}
