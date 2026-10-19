//
//  AppStoreScreenshotAvatar.swift
//  Surround
//
//  Created by Anh Khoa Hong on 9/11/20.
//

import SwiftUI

#if DEBUG && MAIN_APP
struct AppStoreScreenshotAvatar: View {
    let player: OGSUser
    let size: CGFloat

    private static let palettes: [(Color, Color, Color)] = [
        (
            Color(red: 0.20, green: 0.35, blue: 0.93),
            Color(red: 0.12, green: 0.78, blue: 0.86),
            Color(red: 0.76, green: 0.96, blue: 0.98)
        ),
        (
            Color(red: 0.95, green: 0.36, blue: 0.20),
            Color(red: 0.98, green: 0.68, blue: 0.18),
            Color(red: 1.00, green: 0.92, blue: 0.62)
        ),
        (
            Color(red: 0.35, green: 0.16, blue: 0.72),
            Color(red: 0.87, green: 0.28, blue: 0.60),
            Color(red: 0.96, green: 0.76, blue: 0.92)
        ),
        (
            Color(red: 0.05, green: 0.48, blue: 0.37),
            Color(red: 0.37, green: 0.76, blue: 0.38),
            Color(red: 0.84, green: 0.95, blue: 0.62)
        ),
        (
            Color(red: 0.10, green: 0.24, blue: 0.43),
            Color(red: 0.32, green: 0.58, blue: 0.82),
            Color(red: 0.77, green: 0.89, blue: 1.00)
        ),
        (
            Color(red: 0.55, green: 0.18, blue: 0.16),
            Color(red: 0.91, green: 0.38, blue: 0.33),
            Color(red: 1.00, green: 0.78, blue: 0.64)
        ),
    ]

    private static let symbols = [
        "leaf.fill",
        "mountain.2.fill",
        "moon.stars.fill",
        "water.waves",
        "bird.fill",
        "sparkles",
    ]

    private var paletteIndex: Int {
        Int(player.id.magnitude % UInt(Self.palettes.count))
    }

    private var symbolIndex: Int {
        player.username.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult + Int(scalar.value)) % Self.symbols.count
        }
    }

    var body: some View {
        let palette = Self.palettes[paletteIndex]

        ZStack {
            LinearGradient(
                colors: [palette.0, palette.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.2.opacity(0.72))
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: size * 0.28, y: -size * 0.24)

            Circle()
                .fill(.black.opacity(0.12))
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(x: -size * 0.30, y: size * 0.30)

            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(.white.opacity(0.13))
                .frame(width: size * 0.82, height: size * 0.30)
                .rotationEffect(.degrees(-18))
                .offset(x: -size * 0.18, y: -size * 0.20)

            Image(systemName: Self.symbols[symbolIndex])
                .font(.system(size: size * 0.40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(
                    color: .black.opacity(0.24),
                    radius: size * 0.04,
                    y: size * 0.02
                )

            HStack(spacing: size * 0.04) {
                Circle()
                    .fill(.black)
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.20), lineWidth: 0.5))
            }
            .frame(width: size * 0.26, height: size * 0.11)
            .offset(x: size * 0.29, y: size * 0.31)
            .shadow(
                color: .black.opacity(0.25),
                radius: size * 0.025,
                y: size * 0.015
            )
        }
        .frame(width: size, height: size)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.42), lineWidth: max(1, size * 0.018))
        }
        .accessibilityHidden(true)
    }
}
#endif
