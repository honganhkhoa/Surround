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
    @State private var selectedCategory: ProfileRatingCategory = .overall

    let user: OGSUser

    private var selectedRating: ProfileRating {
        ProfileRating(user: user, category: selectedCategory)
    }

    var body: some View {
        if !hidesRank {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .zIndex(1)
                headline
                    .profileContentMargins()
                    .padding(.vertical, 12)
                VStack(spacing: 0) {
                    ForEach(ProfileRatingCategory.allCases) { category in
                        if category != .overall { Divider() }
                        ratingRow(ProfileRating(user: user, category: category))
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: 1_100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatings)
            .onChange(of: user.id) { _, _ in selectedCategory = .overall }
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

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedRating.hasData {
                Text("No rated games")
                    .font(.title2.weight(.semibold))
            } else {
                if selectedRating.isProvisional && !showsRatings {
                    Text("Provisional rank")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.indigo)
                    if let range = selectedRating.likelyRankRange {
                        Text("Likely range: \(range)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(verbatim: showsRatings ? selectedRating.ratingText : selectedRating.rankText(longFormat: true))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                if showsRatings || !selectedRating.isProvisional,
                   let deviation = showsRatings ? selectedRating.ratingDeviationText : selectedRating.rankDeviationText {
                    Group {
                        if showsRatings {
                            Text("\(selectedCategory.title) · ±\(deviation) rating points")
                        } else {
                            Text("\(selectedCategory.title) · ±\(deviation) ranks")
                        }
                    }
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if selectedRating.isProvisional && showsRatings {
                    Text("Provisional")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingHeadline)
    }

    private func ratingRow(_ rating: ProfileRating) -> some View {
        let selected = selectedCategory == rating.category
        let usesVerticalLayout = dynamicTypeSize.isAccessibilitySize
        let layout = usesVerticalLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return Button {
            selectedCategory = rating.category
        } label: {
            layout {
                Text(verbatim: rating.category.title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !usesVerticalLayout { Spacer(minLength: 8) }
                rowValue(rating, usesVerticalLayout: usesVerticalLayout)
            }
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Color.indigo.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.category.title))
        .accessibilityValue(accessibilityValue(for: rating))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.profileRatingCategory(rating.category.rawValue))
    }

    private func rowValue(_ rating: ProfileRating, usesVerticalLayout: Bool) -> some View {
        VStack(alignment: usesVerticalLayout ? .leading : .trailing, spacing: 4) {
            if rating.hasData {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ratingValueParts(rating)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ratingValueParts(rating)
                    }
                }
                .monospacedDigit()
                if rating.isProvisional && showsRatings {
                    Text("Provisional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        missingRatingValue
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: usesVerticalLayout ? .leading : .trailing, spacing: 4) {
                        missingRatingValue
                    }
                }
            }
        }
        .multilineTextAlignment(usesVerticalLayout ? .leading : .trailing)
    }

    @ViewBuilder
    private var missingRatingValue: some View {
        Text("—").foregroundStyle(.secondary)
        Text("No rated games")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func ratingValueParts(_ rating: ProfileRating) -> some View {
        Text(verbatim: showsRatings ? rating.ratingText : rating.rankText())
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
        if rating.isProvisional && !showsRatings, let range = rating.likelyRankRange {
            Text(verbatim: range)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        } else if let deviation = showsRatings ? rating.ratingDeviationText : rating.rankDeviationText {
            Text("±\(deviation)")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
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
