//
//  GameControlChipFitTests.swift
//  SurroundTests
//
//  The in-game control's custom forms keep their fixed frames in English
//  and every translation. At the default text size and the largest, every
//  state fits every frame once its drop order has run, with no text cut and
//  no part that never drops gone. The only translated text the chip draws
//  is its sudden-death mark, read here from the hosted app bundle; the
//  clock and +N are digits.
//

import UIKit
import XCTest

final class GameControlChipFitTests: XCTestCase {
    private typealias WidthClass = GameControlWindowClass.WidthClass

    /// English and the 13 translations the app ships.
    private static let languages = ["en", "de", "es", "fr", "id", "ja", "ko", "ms",
                                    "pt-BR", "pt-PT", "th", "vi", "zh-Hans", "zh-Hant"]
    /// The default text size, and the largest, which each form's cap stops.
    private static let sizes: [UIContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
    private static let allSizes: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]
    private static let forms: [GameControlForm] = [.bottomBar, .topBar]
    /// Before the root has measured, and each class.
    private static let windowClasses: [GameControlWindowClass?] = [nil] + WidthClass.allCases.map {
        GameControlWindowClass(widthClass: $0, shape: .portrait)
    }
    /// The widest +N the test asks every frame to hold, and a usual one.
    private static let slots: [GameControlSlot] = [
        .chip(gameID: 1, plusN: 0, hasDot: false), .chip(gameID: 1, plusN: 3, hasDot: true),
        .chip(gameID: 1, plusN: 99, hasDot: false),
        .gameStarted(gameID: 1, plusN: 0, hasDot: true), .gameStarted(gameID: 1, plusN: 99, hasDot: false),
        .gameOverCard(challengeID: 2, plusN: 0), .gameOverCard(challengeID: 2, plusN: 99),
        .base(plusN: 0), .base(plusN: 3), .base(plusN: 99), .dot, .inbox(count: 1), .inbox(count: 99),
    ]
    /// No countdown, then the widest time of each length.
    private static let clocks: [GameControlClock?] = [
        nil, GameControlClock(timeLeft: 42), GameControlClock(timeLeft: 5400), GameControlClock(timeLeft: 45_000),
    ]

    // MARK: The language's mark

    func testTheHostedAppHasEveryLanguage() throws {
        let app = try appBundle()
        for language in Self.languages.dropFirst() {
            XCTAssertNotNil(app.path(forResource: language, ofType: "lproj"), language)
        }
    }

    /// Two-letter Latin forms stay text; the longer forms take the glyph.
    func testEachLanguageKeepsOneSuddenDeathMarkAtEverySize() throws {
        let cap = GameControlChipMetrics(form: .bottomBar, sizeCategory: GameControlChipMetrics.cap(for: .bottomBar))
        var glyphLanguages = [String]()
        for language in Self.languages {
            let sd = try localizedSD(language)
            let mark = GameControlSuddenDeathMark(bottomBar: sd)
            let atCap = GameControlChipMetrics.textWidth(sd, font: cap.textFont)
            for size in Self.allSizes {
                let metrics = GameControlChipMetrics(form: .bottomBar, sizeCategory: size)
                XCTAssertLessThanOrEqual(GameControlChipMetrics.textWidth(sd, font: metrics.textFont), atCap,
                                         "\(language) at \(size.rawValue): no size draws the mark wider than the cap")
            }
            switch mark {
            case .text(let text):
                XCTAssertEqual(text, sd, language)
                XCTAssertLessThanOrEqual(atCap, GameControlSuddenDeathMark.textSlotWidth, language)
            case .glyph:
                XCTAssertGreaterThan(atCap, GameControlSuddenDeathMark.textSlotWidth, language)
                glyphLanguages.append(language)
            }
        }
        XCTAssertEqual(glyphLanguages, ["ja", "ko", "zh-Hans", "zh-Hant"],
                       "Today's catalog: the two-letter forms fit, the longer ones take the glyph.")
    }

    // MARK: Every state in every frame

    func testEveryStateFitsEveryFrameInEveryLanguage() throws {
        var report = ["language size form class modes state clock: frame kept (width)"]
        var checked = 0
        for language in Self.languages {
            let bottomBarMark = GameControlSuddenDeathMark(bottomBar: try localizedSD(language))
            for size in Self.sizes {
                for form in Self.forms {
                    let metrics = GameControlChipMetrics(form: form, sizeCategory: size)
                    let mark = form == .bottomBar ? bottomBarMark : .glyph
                    for windowClass in Self.windowClasses {
                        for modes in [2, 3] {
                            for slot in Self.slots {
                                for clock in Self.clocks {
                                    for suddenDeath in Self.suddenDeathCases(slot, clock) {
                                        let name = [language, size.rawValue, "\(form)", windowClass.map { "\($0.widthClass)" } ?? "nil",
                                                    "\(modes)", "\(slot)", clock?.text ?? "none", suddenDeath ? "SD" : ""]
                                            .joined(separator: " ")
                                        let drawing = try XCTUnwrap(GameControlDrawing(
                                            slot, form: form, windowClass: windowClass, modeCount: modes,
                                            sizeCategory: size, allowsPicker: true, hasCountdown: clock != nil,
                                            isSuddenDeath: suddenDeath), name)
                                        let fit = drawing.fit(metrics, clock: clock, mark: mark)
                                        checked += 1
                                        XCTAssertTrue([160, 120, 96, 84, 44].contains(drawing.frame.width), name)
                                        XCTAssertTrue(fit.fits, "\(name): \(fit.width) pt in \(drawing.frame.width)")
                                        XCTAssertLessThanOrEqual(fit.width, drawing.frame.width, name)
                                        for part in Self.partsThatStay(drawing, slot: slot, form: form, clock: clock,
                                                                       suddenDeath: suddenDeath) {
                                            XCTAssertTrue(fit.parts.contains(part), "\(name) lost \(part)")
                                        }
                                        if Self.reports(windowClass, modes: modes, slot: slot, clock: clock) {
                                            report.append("\(name): \(Int(drawing.frame.width)) "
                                                + "\(fit.parts.map(Self.short).joined(separator: ",")) (\(Int(ceil(fit.width))))")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        report.insert("\(checked) cases", at: 0)
        attach("Every state in every frame", report.joined(separator: "\n"))
    }

    /// The drawn chip, at the default size in English, keeps everything for
    /// "00:42" and "+3".
    func testTheDrawnChipKeepsEveryPartInEnglishAtTheDefaultSize() throws {
        let metrics = GameControlChipMetrics(form: .bottomBar, sizeCategory: .large)
        let drawing = try XCTUnwrap(GameControlDrawing(.chip(gameID: 1, plusN: 3, hasDot: false), form: .bottomBar,
                                                       windowClass: nil, modeCount: 2, sizeCategory: .large,
                                                       allowsPicker: true))
        let fit = drawing.fit(metrics, clock: GameControlClock(timeLeft: 42),
                              mark: GameControlSuddenDeathMark(bottomBar: try localizedSD("en")))
        XCTAssertEqual(drawing.frame.width, 160)
        XCTAssertEqual(fit.parts, [.board, .hourglass, .clock, .plusN])
        let top = try XCTUnwrap(GameControlDrawing(.chip(gameID: 1, plusN: 3, hasDot: false), form: .topBar,
                                                   windowClass: nil, modeCount: 2, sizeCategory: .large,
                                                   allowsPicker: true))
        XCTAssertEqual(top.fit(GameControlChipMetrics(form: .topBar, sizeCategory: .large),
                               clock: GameControlClock(timeLeft: 42), mark: .glyph).parts,
                       [.board, .hourglass, .clock], "The top bar's chip keeps its hourglass for 00:42.")
    }

    // MARK: The measurement

    func testTheClocksDigitsAreMonospaced() {
        for form in Self.forms {
            for size in Self.allSizes {
                let font = GameControlChipMetrics(form: form, sizeCategory: size).textFont
                for samples in [["00:00", "11:11", "48:59"], ["0:00:00", "1:11:11", "9:48:59"],
                                ["00:00:00", "11:11:11", "23:48:59"]] {
                    let widths = Set(samples.map { GameControlChipMetrics.textWidth($0, font: font) })
                    XCTAssertEqual(widths.count, 1, "\(form) at \(size.rawValue): \(samples)")
                }
            }
        }
    }

    func testTextStopsGrowingAtEachFormsCap() {
        for form in Self.forms {
            let cap = GameControlChipMetrics(form: form, sizeCategory: GameControlChipMetrics.cap(for: form))
            var previous: CGFloat = 0
            for size in Self.allSizes {
                let metrics = GameControlChipMetrics(form: form, sizeCategory: size)
                XCTAssertLessThanOrEqual(metrics.textFont.pointSize, cap.textFont.pointSize, "\(form) \(size.rawValue)")
                XCTAssertLessThanOrEqual(metrics.countFont.pointSize, cap.countFont.pointSize, "\(form) \(size.rawValue)")
                XCTAssertGreaterThanOrEqual(metrics.textFont.pointSize, previous, "\(form) \(size.rawValue)")
                previous = metrics.textFont.pointSize
            }
            let largest = GameControlChipMetrics(form: form, sizeCategory: .accessibilityExtraExtraExtraLarge)
            XCTAssertEqual(largest.sizeCategory, GameControlChipMetrics.cap(for: form), "\(form)")
        }
        let large = GameControlChipMetrics(form: .bottomBar, sizeCategory: .large)
        let cap = GameControlChipMetrics(form: .bottomBar, sizeCategory: .extraLarge)
        XCTAssertGreaterThan(cap.symbolWidth("hourglass"), large.symbolWidth("hourglass"),
                             "The symbols beside the clock grow with its text.")
        XCTAssertEqual(GameControlChipMetrics(form: .bottomBar, sizeCategory: .large).textFont.pointSize, 15,
                       "15 pt at the default size")
        XCTAssertEqual(GameControlChipMetrics(form: .bottomBar, sizeCategory: .unspecified).sizeCategory, .large)
    }

    /// Each part's width at the two sizes, for the record.
    func testRecordThePartsWidths() throws {
        var lines = [String]()
        for form in Self.forms {
            for size in Self.sizes {
                let metrics = GameControlChipMetrics(form: form, sizeCategory: size)
                let widths: [(String, CGFloat)] = [
                    ("hourglass", metrics.width(of: .hourglass, clock: nil, plusN: 0, mark: .glyph)),
                    ("glyph", metrics.width(of: .suddenDeathMark, clock: nil, plusN: 0, mark: .glyph)),
                    ("00:00", metrics.width(of: .clock, clock: GameControlClock(timeLeft: 42), plusN: 0, mark: .glyph)),
                    ("0:00:00", metrics.width(of: .clock, clock: GameControlClock(timeLeft: 5400), plusN: 0, mark: .glyph)),
                    ("00:00:00", metrics.width(of: .clock, clock: GameControlClock(timeLeft: 45_000), plusN: 0, mark: .glyph)),
                    ("+3", metrics.width(of: .plusN, clock: nil, plusN: 3, mark: .glyph)),
                    ("+99", metrics.width(of: .plusN, clock: nil, plusN: 99, mark: .glyph)),
                ]
                lines.append("\(form) \(size.rawValue) (\(metrics.sizeCategory.rawValue), \(metrics.textFont.pointSize) pt): "
                             + widths.map { "\($0.0) \(String(format: "%.1f", $0.1))" }.joined(separator: ", "))
            }
        }
        let cap = GameControlChipMetrics(form: .bottomBar, sizeCategory: GameControlChipMetrics.cap(for: .bottomBar))
        for language in Self.languages {
            let sd = try localizedSD(language)
            lines.append("\(language) \"\(sd)\" at the cap: \(String(format: "%.2f", GameControlChipMetrics.textWidth(sd, font: cap.textFont))) pt, "
                         + "\(GameControlSuddenDeathMark(bottomBar: sd))")
        }
        attach("Part widths", lines.joined(separator: "\n"))
    }

    // MARK: Helpers

    /// Sudden death is a clock's state, so it applies to the chip with a
    /// countdown, here at every length.
    private static func suddenDeathCases(_ slot: GameControlSlot, _ clock: GameControlClock?) -> [Bool] {
        guard case .chip = slot, clock != nil else { return [false] }
        return [false, true]
    }

    /// What the chip's design never drops: in the bottom bar the board, the
    /// mark and the clock; in a top bar the clock and the glyph; otherwise
    /// the board, the tile or the icon, and the hourglass that stands in for
    /// a missing countdown. A live game's last byo-yomi period lasts at most
    /// an hour, so a sudden-death clock reads an hour or more only in such a
    /// period's first second, and then the bottom bar's board may give way.
    private static func partsThatStay(_ drawing: GameControlDrawing, slot: GameControlSlot, form: GameControlForm,
                                      clock: GameControlClock?, suddenDeath: Bool) -> [GameControlPart] {
        guard case .chip = slot, let clock else { return drawing.parts.filter { $0 != .plusN } }
        var mayDrop: [GameControlPart] = [.hourglass, .plusN]
        if form == .topBar || (suddenDeath && clock.seconds >= 3600) {
            mayDrop.append(.board)
        }
        return drawing.parts.filter { !mayDrop.contains($0) }
    }

    /// The report keeps the frames a person sees: the chip in each class
    /// beside three modes, and the base icon with the widest count.
    private static func reports(_ windowClass: GameControlWindowClass?, modes: Int, slot: GameControlSlot,
                                clock: GameControlClock?) -> Bool {
        guard modes == 3, windowClass != nil else { return false }
        switch slot {
        case .chip(_, let plusN, _): return plusN == 3
        case .base(let plusN): return plusN == 99 && clock == nil
        default: return false
        }
    }

    private static func short(_ part: GameControlPart) -> String {
        switch part {
        case .board: "board"
        case .tile: "tile"
        case .icon(let icon): "\(icon)"
        case .hourglass: "hourglass"
        case .suddenDeathMark: "mark"
        case .clock: "clock"
        case .plusN: "+N"
        }
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The language's "SD" from the hosted app's own catalog. English, the
    /// source language, falls back to the key.
    private func localizedSD(_ language: String) throws -> String {
        let app = try appBundle()
        let lproj = app.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        let bundle = try XCTUnwrap(lproj ?? (language == "en" ? app : nil), "No \(language).lproj in the app")
        return bundle.localizedString(forKey: "SD", value: nil, table: "Localizable")
    }

    private func appBundle() throws -> Bundle {
        let testBundleURL = Bundle(for: Self.self).bundleURL
        let candidates = [
            // Installed hosted tests live at Surround.app/PlugIns/SurroundTests.xctest.
            testBundleURL.deletingLastPathComponent().deletingLastPathComponent(),
            // Build products keep Surround.app beside SurroundTests.xctest.
            testBundleURL.deletingLastPathComponent().appendingPathComponent("Surround.app"),
        ]
        return try XCTUnwrap(candidates.compactMap { Bundle(url: $0) }.first {
            Set(Self.languages.dropFirst()).isSubset(of: $0.localizations)
        }, "Unable to locate the hosted app bundle with every translation")
    }
}
