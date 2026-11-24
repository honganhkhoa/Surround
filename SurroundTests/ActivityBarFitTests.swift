//
//  ActivityBarFitTests.swift
//  SurroundTests
//
//  The Activity bar keeps its parts in English and every translation. In
//  each host's narrowest bar, at the default text size and at XXL, the cap,
//  left to right and right to left, with "1:30:00" and "+99", every kind's
//  parts that never drop still fit once the form's drop order has run, with
//  line one down to a letter and an ellipsis, or to the ellipsis alone where
//  it may go. Where the form keeps line two, both lines fit the bar's
//  height in every language. The Now section's rows keep their clock or
//  Retry at the iPad's 270 pt and the Mac's 200 pt, but for the Mac's few
//  long labels the test lists by name. The text is the hosted app bundle's
//  own. The bar's new strings have only Malay and
//  Indonesian so far, so in the other languages they read as English here,
//  as they do on screen until they are translated; the strings the bar
//  measures (the actions, the status words, "SD", ranks) are translated in
//  every language already.
//

import UIKit
import XCTest

final class ActivityBarFitTests: XCTestCase {
    /// English and the 13 translations the app ships.
    private static let languages = ["en", "de", "es", "fr", "id", "ja", "ko", "ms",
                                    "pt-BR", "pt-PT", "th", "vi", "zh-Hans", "zh-Hant"]
    /// The default text size, and the largest, which the bar caps at XXL.
    private static let sizes: [UIContentSizeCategory] = [.large, .accessibilityExtraExtraExtraLarge]
    private static let directions: [NSWritingDirection] = [.leftToRight, .rightToLeft]

    /// Each host's narrowest bar.
    private struct Host {
        var name: String
        var bar: ActivityHostPolicy.Bar
        var form: ActivityBarForm
        var width: CGFloat
    }

    private static let hosts = [
        // Set once the view is in a window, and again after each size
        // transition, Closed upright's accessory is 290 pt.
        Host(name: "Duo Closed", bar: .uiKitAccessory, form: .closed, width: 290),
        // Beside the minimized tab bar's Home circle: 284 pt on an 18 Pro.
        Host(name: "iOS 27 inline, 18 Pro", bar: .uiKitAccessory, form: .inline, width: 284),
        // An SE is 27 pt narrower than an 18 Pro, with the same margins:
        // derived, not measured, so it is the narrowest the bar may get.
        Host(name: "iOS 27 inline, SE", bar: .uiKitAccessory, form: .inline, width: 257),
        // 21 pt from each edge of a 375 pt screen.
        Host(name: "iOS 27 accessory, SE", bar: .uiKitAccessory, form: .expanded, width: 333),
        // The content's width less 32 pt.
        Host(name: "custom bar, SE", bar: .customBar, form: .expanded, width: 343),
        Host(name: "custom bar, SE in landscape", bar: .customBar, form: .compactHeight, width: 635),
        // A centred capsule from iPadOS 27.0.
        Host(name: "iPad accessory from 27.0", bar: .uiKitAccessory, form: .expanded, width: 347.5),
    ]

    /// The Now section's rows: the iPad's narrowest sidebar, and the Mac's
    /// 200 pt rows inside its 220 pt sidebar.
    private static let nowRows: [(name: String, width: CGFloat)] = [("iPad Now row", 270), ("Mac Now row", 200)]

    /// Where the Mac's 200 pt row can't hold its trailing part beside a
    /// letter of its words, even with the hourglass and the tile dropped:
    /// Retry and Open game in these languages. How the Mac's rows draw these
    /// is the Mac's Now section's to decide; until then the list is exact,
    /// so a change of font, padding or translation that moves a case shows.
    private static let macRowOverflows: Set<String> = [
        "de XXL status unreachable",
        "fr XXL started", "id XXL started", "ms XXL started",
        "pt-BR L status unreachable", "pt-BR XXL status unreachable",
        "pt-PT L status unreachable", "pt-PT XXL status unreachable",
    ]

    // MARK: The content

    /// One kind of the bar's content, with what its measured parts draw.
    private struct Kind {
        var name: String
        var content: ActivityBarContent
        /// Line one may truncate to the ellipsis alone.
        var mayTruncateFully = false
        /// Line one is a player's name, with a rank beside it.
        var hasRank = false
        var clock: GameControlClock? = nil
        var isSuddenDeath = false
    }

    private static let ninetyNine = (1...99).map { ActivityBarCountedItem.conversation(peerID: $0) }
    private static let clock = GameControlClock(timeLeft: 5400)
    private static let search = ActivityModel.Waiting(id: ActivityModel.WaitingID.quickMatch("q"), kind: .quickMatch,
                                                     isLive: true, since: 0)
    private static let openChallenge = ActivityModel.Waiting(id: ActivityModel.WaitingID.openChallenge(1),
                                                            kind: .openChallenge, isLive: true, since: 0)
    private static let sentChallenge = ActivityModel.Waiting(id: ActivityModel.WaitingID.sentChallenge(2),
                                                            kind: .sentChallenge, isLive: true, since: 0)
    private static let rengo = ActivityModel.Waiting(id: ActivityModel.WaitingID.rengo(3), kind: .rengo,
                                                    isLive: true, since: 0)
    private static let challenge = ActivityModel.Challenge(id: 9, isLive: true)

    private static func result(_ state: ActivityActionState) -> ActivityBarContent {
        .result(ActivityBarResult(itemID: "waiting-quick-match-q", action: .withdraw, state: state,
                                  display: ActivityRowDisplay(title: "Quick match", detail: "Live · 19×19")))
    }

    private static let kinds: [Kind] = {
        var kinds = [Kind]()
        for counted in [ninetyNine, []] {
            let n = counted.isEmpty ? "" : " +99"
            kinds += [
                Kind(name: "live 1:30:00\(n)", content: .lead(.liveGame(gameID: 1), counted: counted, status: nil),
                     hasRank: true, clock: clock),
                Kind(name: "live SD 59:59\(n)", content: .lead(.liveGame(gameID: 1), counted: counted, status: nil),
                     hasRank: true, clock: GameControlClock(timeLeft: 3599), isSuddenDeath: true),
                Kind(name: "live, no countdown\(n)", content: .lead(.liveGame(gameID: 1), counted: counted, status: nil),
                     hasRank: true),
                Kind(name: "live offline\(n)",
                     content: .lead(.liveGame(gameID: 1), counted: counted, status: .reconnecting),
                     hasRank: true, clock: clock),
                Kind(name: "started\(n)", content: .lead(.gameStarted(gameID: 1), counted: counted, status: nil)),
                Kind(name: "challenge\(n)", content: .lead(.challenge(challenge), counted: counted, status: nil),
                     hasRank: true),
                Kind(name: "search\(n)", content: .lead(.waiting(search, withdrawsInPlace: true), counted: counted,
                                                        status: nil)),
                Kind(name: "search, card\(n)", content: .lead(.waiting(search, withdrawsInPlace: false),
                                                              counted: counted, status: nil)),
                Kind(name: "open challenge\(n)", content: .lead(.waiting(openChallenge, withdrawsInPlace: true),
                                                                counted: counted, status: nil)),
                Kind(name: "sent challenge\(n)", content: .lead(.waiting(sentChallenge, withdrawsInPlace: true),
                                                                counted: counted, status: nil)),
                Kind(name: "rengo\(n)", content: .lead(.waiting(rengo, withdrawsInPlace: false), counted: counted,
                                                       status: nil)),
                Kind(name: "unreachable\(n)", content: .unreachable(counted: counted), mayTruncateFully: true),
            ]
        }
        kinds += [
            Kind(name: "nothing leads", content: .lead(.nothingLeads(count: 99), counted: ninetyNine, status: nil)),
            Kind(name: "reconnecting", content: .status(.reconnecting)),
            Kind(name: "connecting", content: .status(.connecting)),
            Kind(name: "connected", content: .status(.connected)),
            Kind(name: "withdrawing", content: result(.pending(since: 0))),
            Kind(name: "withdrawn", content: result(.succeeded(.withdrawn))),
            Kind(name: "couldn’t withdraw", content: result(.failed)),
        ]
        return kinds
    }()

    // MARK: Every kind in every host

    func testEveryKindKeepsItsPartsInEveryHostAndLanguage() throws {
        var report = ["language size host kind: kept parts (width / bar)"]
        var checked = 0
        for language in Self.languages {
            let words = try Words(language: language, bundle: try appBundle())
            for size in Self.sizes {
                for host in Self.hosts {
                    let metrics = ActivityBarMetrics(form: host.form, sizeCategory: size)
                    for kind in Self.kinds {
                        let drawing = ActivityBarDrawing(kind.content, form: host.form)
                        var fits = [ActivityBarFit]()
                        for direction in Self.directions {
                            let text = words.text(for: kind, direction: direction)
                            let fit = metrics.fit(drawing, in: host.width, text: text)
                            fits.append(fit)
                            checked += 1
                            let name = "\(language) \(size.rawValue) \(host.name) \(kind.name)"
                                + (direction == .rightToLeft ? " RTL" : "")
                            XCTAssertTrue(fit.fits, "\(name): \(fit.width) pt in \(host.width)")
                            for part in Self.partsThatStay(drawing, text: text) {
                                XCTAssertTrue(fit.parts.contains(part), "\(name) lost \(part)")
                            }
                        }
                        XCTAssertEqual(fits.first?.parts, fits.last?.parts,
                                       "\(language) \(host.name) \(kind.name): right to left keeps the same parts")
                        if language == "en" || size != .large {
                            report.append("\(language) \(metrics.sizeCategory.rawValue) \(host.name) \(kind.name): "
                                          + "\(fits[0].parts.map(Self.short).joined(separator: ",")) "
                                          + "(\(Int(ceil(fits[0].width))) / \(host.width))")
                        }
                    }
                }
            }
        }
        report.insert("\(checked) cases", at: 0)
        attach("Every kind in every host", report.joined(separator: "\n"))
    }

    /// The parts a form never drops: all but its drop order. Line two shares
    /// line one's column; the chip draws its own mark in sudden death, and
    /// its hourglass alone without a countdown.
    private static func partsThatStay(_ drawing: ActivityBarDrawing, text: ActivityBarPartText) -> [ActivityBarPart] {
        let chipDrawsItsSymbol = text.clock == nil || text.suddenDeathMark != nil
        return drawing.parts.filter { part in
            part != .lineTwo && !(part == .hourglass && chipDrawsItsSymbol) && !drawing.dropOrder.contains(part)
        }
    }

    // MARK: Two lines in the bar's height

    func testTwoLinesFitEveryHostsHeightInEveryLanguage() throws {
        var report = [String]()
        for language in Self.languages {
            let words = try Words(language: language, bundle: try appBundle())
            for size in Self.sizes {
                for bar in [ActivityHostPolicy.Bar.uiKitAccessory, .customBar] {
                    for form in [ActivityBarForm.expanded, .compactHeight, .inline, .closed]
                    where bar == .customBar ? !form.isOneLine : form != .compactHeight {
                        let metrics = ActivityBarMetrics(form: form, sizeCategory: size)
                        let height = ActivityBarMetrics.height(of: bar, form: form)
                        let lineOne = words.lineOneSamples.map { ActivityBarMetrics.lineHeight($0, font: metrics.lineOneFont) }.max() ?? 0
                        let lineTwo = words.lineTwoSamples.map { ActivityBarMetrics.lineHeight($0, font: metrics.detailFont) }.max() ?? 0
                        let showsLineTwo = metrics.showsLineTwo(in: bar)
                        let lines = lineOne + (showsLineTwo ? ActivityBarMetrics.lineGap + max(lineTwo, metrics.badgeHeight) : 0)
                        let name = "\(language) \(metrics.sizeCategory.rawValue) \(bar) \(form)"
                        XCTAssertLessThanOrEqual(lines, height, "\(name): \(lines) pt of lines in \(height)")
                        XCTAssertLessThanOrEqual(max(metrics.tileSize, metrics.clockHeight, metrics.capsuleHeight), height, name)
                        if form == .expanded, size == .large {
                            XCTAssertTrue(showsLineTwo, "\(name): two lines at the default size")
                        }
                        if size != .large || language == "en" {
                            report.append("\(name): \(lines) of \(height)\(form == .expanded && !showsLineTwo ? ", line two drops" : "")")
                        }
                    }
                }
            }
        }
        attach("Lines in the bar's height", report.joined(separator: "\n"))
    }

    /// Line two drops only in the system's 44 pt accessories at the cap,
    /// where two lines don't fit; the custom bar keeps it at every size.
    func testLineTwoDropsOnlyInTheAccessoriesAtTheCap() {
        for size in [UIContentSizeCategory.large, .extraLarge] {
            XCTAssertTrue(ActivityBarMetrics(form: .expanded, sizeCategory: size).showsLineTwo(in: .uiKitAccessory),
                          size.rawValue)
        }
        let cap = ActivityBarMetrics(form: .expanded, sizeCategory: .accessibilityExtraExtraExtraLarge)
        XCTAssertFalse(cap.showsLineTwo(in: .uiKitAccessory))
        XCTAssertFalse(cap.showsLineTwo(in: .swiftUIAccessory))
        XCTAssertTrue(cap.showsLineTwo(in: .customBar))
        XCTAssertFalse(ActivityBarMetrics(form: .inline, sizeCategory: .large).showsLineTwo(in: .uiKitAccessory),
                       "The one-line forms draw no line two.")
    }

    // MARK: The Now section's rows

    func testEveryNowRowKeepsItsTrailingPartInEveryLanguage() throws {
        let leads: [(name: String, lead: ActivityBarLead, clock: GameControlClock?, hasRank: Bool)] = [
            ("live 1:30:00", .liveGame(gameID: 1), Self.clock, true),
            ("live, no countdown", .liveGame(gameID: 1), nil, true),
            ("started", .gameStarted(gameID: 1), nil, false),
            ("challenge", .challenge(Self.challenge), nil, true),
            ("search", .waiting(Self.search, withdrawsInPlace: true), nil, false),
            ("sent challenge", .waiting(Self.sentChallenge, withdrawsInPlace: true), nil, false),
            ("rengo", .waiting(Self.rengo, withdrawsInPlace: false), nil, false),
            ("nothing leads", .nothingLeads(count: 99), nil, false),
        ]
        let statusRows = [NowStatusRow(.unreachable, place: .root(isMessagesTab: false)),
                          NowStatusRow(.reconnecting, place: .root(isMessagesTab: false))].compactMap { $0 }
        var report = [String]()
        var macOverflows = Set<String>()
        for language in Self.languages {
            let words = try Words(language: language, bundle: try appBundle())
            for size in Self.sizes {
                let metrics = ActivityNowRowMetrics(sizeCategory: size)
                for row in Self.nowRows {
                    var cases = leads.map { lead in
                        (lead.name, ActivityNowRowMetrics.parts(lead.lead),
                         words.text(lineOneMinimum: ActivityBarPartText.letterAndEllipsis, hasRank: lead.hasRank,
                                    clock: lead.clock))
                    }
                    cases += statusRows.map { status in
                        ("status \(status.words)", ActivityNowRowMetrics.parts(status),
                         words.text(lineOneMinimum: ActivityBarPartText.letterAndEllipsis, hasRank: false, clock: nil))
                    }
                    for (name, parts, text) in cases {
                        for direction in Self.directions {
                            var text = text
                            text.direction = direction
                            let fit = metrics.fit(parts, in: row.width, text: text)
                            let label = "\(language) \(metrics.sizeCategory.rawValue) \(row.name) \(name)"
                                + (direction == .rightToLeft ? " RTL" : "")
                            let sizeName = size == .large ? "L" : "XXL"
                            if row.width < 270, !fit.fits {
                                macOverflows.insert("\(language) \(sizeName) \(name)")
                            } else {
                                XCTAssertTrue(fit.fits, "\(label): \(fit.width) pt in \(row.width)")
                            }
                            for part in [ActivityBarPart.clock, .action(.retry)] where parts.contains(part) && fit.fits {
                                XCTAssertTrue(fit.parts.contains(part), "\(label) lost \(part)")
                            }
                            if direction == .leftToRight, language == "en" || size != .large || !fit.fits {
                                report.append("\(label): \(fit.parts.map(Self.short).joined(separator: ",")) "
                                              + "(\(Int(ceil(fit.width))) / \(row.width))")
                            }
                        }
                    }
                }
            }
        }
        attach("Now rows", report.joined(separator: "\n"))
        XCTAssertEqual(macOverflows, Self.macRowOverflows,
                       "The Mac's 200 pt Now rows that can't hold their trailing part, in either direction")
    }

    // MARK: The catalog's words

    /// The hosted tests' main bundle is the test runner's, so the bar's
    /// plurals come from the app's own catalog here.
    func testTheBarsCountsReadInTheCatalogsPlurals() throws {
        let app = try appBundle()
        func counted(_ key: String, _ value: Int, _ language: String) throws -> String {
            let lproj = try XCTUnwrap(app.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)), language)
            return String.localizedStringWithFormat(lproj.localizedString(forKey: key, value: nil, table: "Localizable"), value)
        }
        XCTAssertEqual(try counted("%lld correspondence challenges", 1, "en"), "A correspondence challenge")
        XCTAssertEqual(try counted("%lld correspondence challenges", 2, "en"), "2 correspondence challenges")
        XCTAssertEqual(try counted("%lld conversations", 1, "en"), "1 conversation")
        XCTAssertEqual(try counted("%lld unread conversations", 1, "en"), "1 unread conversation")
        XCTAssertEqual(try counted("%lld live games on your move", 1, "en"), "1 live game on your move")
        XCTAssertEqual(try counted("%lld challenges", 1, "en"), "1 challenge")
        XCTAssertEqual(try counted("%lld unread conversations", 2, "ms"), "2 perbualan belum dibaca")
        XCTAssertEqual(try counted("%lld unread conversations", 2, "id"), "2 percakapan belum dibaca")
        XCTAssertEqual(try counted("%lld live games on your move", 2, "ms"), "giliran anda dalam 2 permainan langsung")
        XCTAssertEqual(try counted("%lld correspondence challenges", 1, "id"), "1 tantangan korespondensi")
    }

    // MARK: The measurement

    /// The drawn bar, in English at the default size in an 18 Pro's
    /// accessory, keeps every part for "00:42" and "+3".
    func testTheDrawnBarKeepsEveryPartInEnglishAtTheDefaultSize() throws {
        let words = try Words(language: "en", bundle: try appBundle())
        let metrics = ActivityBarMetrics(form: .expanded, sizeCategory: .large)
        let counted = [ActivityBarCountedItem](Self.ninetyNine.prefix(3))
        let live = Kind(name: "live", content: .lead(.liveGame(gameID: 1), counted: counted, status: nil),
                        hasRank: true, clock: GameControlClock(timeLeft: 42))
        let fit = metrics.fit(ActivityBarDrawing(live.content, form: .expanded), in: 360,
                              text: words.text(for: live, direction: .leftToRight))
        XCTAssertEqual(fit.parts, [.tile, .lineOne, .hourglass, .clock, .plusN])
        let inline = ActivityBarMetrics(form: .inline, sizeCategory: .large)
        let inlineFit = inline.fit(ActivityBarDrawing(live.content, form: .inline), in: 284,
                                   text: words.text(for: live, direction: .leftToRight))
        XCTAssertEqual(inlineFit.parts, [.tile, .lineOne, .hourglass, .clock, .plusN],
                       "Beside a minimized tab bar the bar keeps its tile, name, clock and +N at the default size.")
    }

    func testTextStopsGrowingAtXXL() {
        for form in [ActivityBarForm.expanded, .compactHeight, .inline, .closed] {
            var previous: CGFloat = 0
            for size in [UIContentSizeCategory.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
                         .extraExtraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge] {
                let metrics = ActivityBarMetrics(form: form, sizeCategory: size)
                XCTAssertLessThanOrEqual(metrics.sizeCategory, .extraExtraLarge, "\(form) \(size.rawValue)")
                XCTAssertGreaterThanOrEqual(metrics.lineOneFont.pointSize, previous, "\(form) \(size.rawValue)")
                previous = metrics.lineOneFont.pointSize
            }
            XCTAssertEqual(ActivityBarMetrics(form: form, sizeCategory: .accessibilityExtraExtraExtraLarge).lineOneFont.pointSize,
                           ActivityBarMetrics(form: form, sizeCategory: .extraExtraLarge).lineOneFont.pointSize, "\(form)")
        }
        let large = ActivityBarMetrics(form: .expanded, sizeCategory: .large)
        XCTAssertEqual(large.lineOneFont.pointSize, 15, "Line one is 15 pt at the default size.")
        XCTAssertEqual(large.detailFont.pointSize, 13, "Line two is 13 pt at the default size.")
        XCTAssertEqual(ActivityBarMetrics(form: .expanded, sizeCategory: .unspecified).sizeCategory, .large)
        XCTAssertEqual(ActivityNowRowMetrics(sizeCategory: .accessibilityExtraExtraExtraLarge).sizeCategory, .extraExtraLarge)
    }

    func testTheClocksDigitsAreMonospaced() {
        for form in [ActivityBarForm.expanded, .closed] {
            for size in Self.sizes {
                let metrics = ActivityBarMetrics(form: form, sizeCategory: size)
                for samples in [["00:00", "11:11", "48:59"], ["0:00:00", "1:11:11", "9:48:59"]] {
                    let widths = Set(samples.map { ActivityBarMetrics.textWidth($0, font: metrics.clockFont) })
                    XCTAssertEqual(widths.count, 1, "\(form) at \(size.rawValue): \(samples)")
                }
            }
        }
    }

    func testTheHostedAppHasEveryLanguage() throws {
        let app = try appBundle()
        for language in Self.languages.dropFirst() {
            XCTAssertNotNil(app.path(forResource: language, ofType: "lproj"), language)
        }
    }

    // MARK: Helpers

    /// What one language draws in the bar's measured parts.
    private struct Words {
        var actions: [ActivityBarAction: String]
        var rank: String
        var suddenDeath: GameControlSuddenDeathMark
        var lineOneSamples: [String]
        var lineTwoSamples: [String]

        init(language: String, bundle app: Bundle) throws {
            let lproj = app.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            let bundle = try XCTUnwrap(lproj ?? (language == "en" ? app : nil), "No \(language).lproj in the app")
            func word(_ key: String) -> String { bundle.localizedString(forKey: key, value: nil, table: "Localizable") }
            func count(_ key: String, _ value: Int) -> String {
                String.localizedStringWithFormat(word(key), value)
            }
            actions = [.openGame: word("Open game"), .view: word("View"), .withdraw: word("Withdraw"),
                       .retry: word("Retry")]
            // The widest short rank, such as "25k".
            rank = count("%lldkyu", 25)
            suddenDeath = GameControlSuddenDeathMark(bottomBar: word("SD"))
            lineOneSamples = ["HarborMist", word("Game started"), word("Searching for a game"), word("Can’t reach OGS"),
                              word("Couldn’t withdraw"), count("%lld waiting", 3)]
            lineTwoSamples = ["\(word("Your move")) · 19×19", "\(word("Challenge")) · 19×19 · \(word("Live"))",
                              word("Reconnecting…"), count("%lld conversations", 2),
                              count("%lld correspondence challenges", 2)]
        }

        func text(for kind: Kind, direction: NSWritingDirection) -> ActivityBarPartText {
            var text = text(lineOneMinimum: kind.mayTruncateFully ? ActivityBarPartText.ellipsis
                                                                  : ActivityBarPartText.letterAndEllipsis,
                            hasRank: kind.hasRank, clock: kind.clock)
            text.suddenDeathMark = kind.isSuddenDeath ? suddenDeath : nil
            text.plusN = kind.content.plusN
            text.direction = direction
            return text
        }

        func text(lineOneMinimum: String, hasRank: Bool, clock: GameControlClock?) -> ActivityBarPartText {
            let actions = actions
            return ActivityBarPartText(lineOneMinimum: lineOneMinimum, rank: hasRank ? rank : nil,
                                       actionLabel: { actions[$0] ?? "" }, clock: clock)
        }
    }

    private static func short(_ part: ActivityBarPart) -> String {
        switch part {
        case .tile: "tile"
        case .lineOne: "line1"
        case .lineTwo: "line2"
        case .hourglass: "hourglass"
        case .clock: "clock"
        case .action(let action): "\(action)"
        case .plusN: "+N"
        }
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
