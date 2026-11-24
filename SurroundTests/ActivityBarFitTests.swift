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
//  height in every language. The Now section's rows keep their clock and
//  their action at the iPad's 270 pt and the Mac's 200 pt, the Mac's few
//  long actions as their symbols, which the test lists by name. The text is
//  the hosted app bundle's own. The bar's new strings have only Malay and
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

    /// Where the Mac's 200 pt row can't hold its action's words beside a
    /// letter of its own, even with the hourglass and the tile dropped, so
    /// the action is drawn as its symbol: Retry and Open game in these
    /// languages. The list is exact, so a change of font, padding or
    /// translation that moves a case shows. The iPad's rows draw none.
    private static let macRowSymbols: Set<String> = [
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
        var symbols = [String: Set<String>]()
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
                        var drawsSymbol = [Bool]()
                        for direction in Self.directions {
                            var text = text
                            text.direction = direction
                            let symbol = metrics.actionDrawsSymbol(parts, in: row.width, text: text)
                            drawsSymbol.append(symbol)
                            let fit = metrics.fit(parts, in: row.width, text: text, actionAsSymbol: symbol)
                            let label = "\(language) \(metrics.sizeCategory.rawValue) \(row.name) \(name)"
                                + (direction == .rightToLeft ? " RTL" : "")
                            XCTAssertTrue(fit.fits, "\(label): \(fit.width) pt in \(row.width)")
                            for part in parts where part == .clock || Self.isAction(part) {
                                XCTAssertTrue(fit.parts.contains(part), "\(label) lost \(part)")
                            }
                            if symbol {
                                symbols[row.name, default: []].insert("\(language) \(size == .large ? "L" : "XXL") \(name)")
                            }
                            if direction == .leftToRight, language == "en" || size != .large || symbol {
                                report.append("\(label): \(fit.parts.map(Self.short).joined(separator: ","))"
                                              + "\(symbol ? " (symbol)" : "") (\(Int(ceil(fit.width))) / \(row.width))")
                            }
                        }
                        XCTAssertEqual(drawsSymbol.first, drawsSymbol.last,
                                       "\(language) \(row.name) \(name): right to left draws the action alike")
                    }
                }
            }
        }
        attach("Now rows", report.joined(separator: "\n"))
        XCTAssertEqual(symbols["Mac Now row"] ?? [], Self.macRowSymbols,
                       "The Mac's 200 pt Now rows whose action is drawn as its symbol")
        XCTAssertEqual(symbols["iPad Now row"] ?? [], [], "The iPad's rows keep every action's words")
    }

    /// An action drawn as its symbol is a pill of at least 44 pt that never
    /// grows past its words' pill, at every size and for every action, and
    /// every symbol exists.
    func testANowActionsSymbolIsAPillNoWiderThanItsWords() throws {
        let words = try Words(language: "en", bundle: try appBundle())
        for size in Self.sizes {
            let metrics = ActivityNowRowMetrics(sizeCategory: size)
            for action in [ActivityBarAction.openGame, .view, .withdraw, .retry] {
                XCTAssertNotNil(UIImage(systemName: ActivityNowRowMetrics.symbolName(action)), "\(action)")
                let symbol = metrics.symbolActionWidth(action)
                XCTAssertGreaterThanOrEqual(symbol, ActivityBarMetrics.targetSize, "\(action) at \(size.rawValue)")
                XCTAssertLessThanOrEqual(symbol, ActivityBarMetrics.targetSize + 8, "\(action) at \(size.rawValue)")
                let text = words.text(lineOneMinimum: ActivityBarPartText.letterAndEllipsis, hasRank: false, clock: nil)
                XCTAssertEqual(metrics.width(of: .action(action), text, actionAsSymbol: true), symbol)
                if action != .withdraw {
                    XCTAssertLessThanOrEqual(symbol, metrics.width(of: .action(action), text), "\(action)")
                }
            }
        }
        let started = ActivityNowRowMetrics.parts(.gameStarted(gameID: 1))
        let english = words.text(lineOneMinimum: ActivityBarPartText.letterAndEllipsis, hasRank: false, clock: nil)
        XCTAssertFalse(ActivityNowRowMetrics(sizeCategory: .large).actionDrawsSymbol(started, in: 200, text: english),
                       "English keeps Open game's words on the Mac.")
        let live = ActivityNowRowMetrics.parts(.liveGame(gameID: 1))
        XCTAssertFalse(ActivityNowRowMetrics(sizeCategory: .large).actionDrawsSymbol(live, in: 1, text: english),
                       "A row with no action draws no symbol, however narrow.")
    }

    private static func isAction(_ part: ActivityBarPart) -> Bool {
        if case .action = part { return true }
        return false
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

extension ActivityBarFitTests {
    /// Two Now rows where the window is tall enough for them below the
    /// sidebar's tab rows, one in a shorter window, and none where even one
    /// row would reach the last tab row: from the window's height, the text
    /// size and the language the sidebar is drawn in alone. A larger size,
    /// lines iOS sets taller, and an accessibility size, where the titles
    /// wrap, need a taller window; from AX4 there is none. Each threshold is
    /// at least 9 pt above the height at which the section's top was
    /// measured to meet the last tab row on iPadOS 26.5, but two rows at XXL
    /// and in Thai at the default size, from 834 pt, 1 pt above it.
    func testAShortWindowGivesTheNowSectionOneRowAndAShorterOneNone() {
        typealias Rows = ActivityNowSectionRows
        func count(_ height: CGFloat, _ size: UIContentSizeCategory, _ strings: String,
                   lines: String? = nil) -> Int {
            Rows.count(windowHeight: height, sizeCategory: size,
                       language: Rows.Language(strings: strings, lines: lines ?? strings))
        }
        // English at the default size and at XXL.
        XCTAssertEqual(count(834, .large, "en"), 2)
        XCTAssertEqual(count(770, .large, "en"), 2)
        XCTAssertEqual(count(769, .large, "en"), 1)
        XCTAssertEqual(count(708, .large, "en"), 1)
        XCTAssertEqual(count(707, .large, "en"), 0)
        XCTAssertEqual(count(597, .large, "en"), 0)
        XCTAssertEqual(count(486, .small, "en"), 0)
        XCTAssertEqual(count(770, .unspecified, "en"), 2)
        XCTAssertEqual(count(707, .unspecified, "en"), 0)
        XCTAssertEqual(count(834, .extraExtraLarge, "en"), 2)
        XCTAssertEqual(count(833, .extraExtraLarge, "en"), 1)
        XCTAssertEqual(count(780, .extraExtraLarge, "en"), 1)
        XCTAssertEqual(count(779, .extraExtraLarge, "en"), 0)

        // A full-size landscape window, 834 pt tall: two rows up to XXL, and
        // in Thai and Vietnamese at the default size; one at XXXL, in
        // Vietnamese at XL and XXL and in Thai at XL; none in Thai from XXL,
        // in Vietnamese from XXXL, and at accessibility sizes but AX1 in
        // Chinese and Korean, whose titles don't wrap there.
        for language in Self.languages where !["th", "vi"].contains(language) {
            XCTAssertEqual(count(834, .extraExtraLarge, language), 2, language)
            XCTAssertEqual(count(834, .extraExtraExtraLarge, language), 1, language)
            XCTAssertEqual(count(834, .accessibilityMedium, language),
                           ["ko", "zh-Hans", "zh-Hant"].contains(language) ? 1 : 0, language)
        }
        XCTAssertEqual(count(834, .large, "th"), 2)
        XCTAssertEqual(count(834, .extraLarge, "th"), 1)
        XCTAssertEqual(count(834, .extraExtraLarge, "th"), 0, "In Thai at XXL even one row would reach Web version.")
        XCTAssertEqual(count(834, .large, "vi"), 2)
        XCTAssertEqual(count(834, .extraLarge, "vi"), 1)
        XCTAssertEqual(count(834, .extraExtraLarge, "vi"), 1)
        XCTAssertEqual(count(834, .extraExtraExtraLarge, "vi"), 0)
        XCTAssertEqual(count(834, .accessibilityMedium, "th"), 0)
        XCTAssertEqual(count(834, .accessibilityExtraExtraExtraLarge, "fr"), 0)
        // A full-size portrait window, 1210 pt tall: one row at AX1 and AX2,
        // at AX3 only where the titles leave room, and none from AX4.
        for language in Self.languages {
            XCTAssertEqual(count(1210, .accessibilityMedium, language), 1, language)
            XCTAssertEqual(count(1210, .accessibilityLarge, language), 1, language)
            XCTAssertEqual(count(1210, .accessibilityExtraLarge, language),
                           ["es", "fr", "pt-PT", "th", "vi"].contains(language) ? 0 : 1, language)
            XCTAssertEqual(count(1210, .accessibilityExtraExtraLarge, language), 0, language)
            XCTAssertEqual(count(1376, .accessibilityExtraExtraExtraLarge, language), 0, language)
        }

        // iOS sets the lines for the first preferred language, whether the
        // app ships it or not: around the app's English, Arabic's lines are as
        // tall as Vietnamese's, Hindi's as Thai's, and Khmer's taller still.
        let lineHeights: [(String, Rows.LineHeight)] = [
            ("en", .standard), ("zh-Hant-TW", .standard), ("nl-NL", .standard), ("he", .standard),
            ("vi-VN", .likeVietnamese), ("ar", .likeVietnamese), ("ta", .likeVietnamese),
            ("th_TH", .likeThai), ("hi-IN", .likeThai), ("hy", .likeThai), ("km", .likeKhmer), ("my", .likeKhmer),
        ]
        for (lines, height) in lineHeights {
            XCTAssertEqual(Rows.LineHeight(Rows.Language(strings: "en", lines: lines)), height, lines)
        }
        XCTAssertEqual(count(834, .extraExtraLarge, "en", lines: "hi-IN"), 0)
        XCTAssertEqual(count(834, .extraExtraLarge, "en", lines: "ar"), 1)
        XCTAssertEqual(count(834, .extraExtraLarge, "fr", lines: "nl-NL"), 2)
        XCTAssertEqual(count(834, .large, "en", lines: "km"), 1)
        XCTAssertEqual(count(1210, .accessibilityMedium, "en", lines: "hi-IN"), 1)
        XCTAssertEqual(count(1210, .accessibilityMedium, "fr", lines: "hi-IN"), 0,
                       "At accessibility sizes taller lines were measured around English titles and their own only.")

        // Where the section's top met the last tab row on iPadOS 26.5, in
        // the window that left the least room, for two rows and for one:
        // every threshold is at least 9 pt above, but two rows from 834 pt,
        // the full-size landscape window, where every measurement left room.
        let needs: [(size: UIContentSizeCategory, lines: String, two: CGFloat?, one: CGFloat)] = [
            (.large, "en", 761, 699), (.large, "vi", 797, 735), (.large, "th", 833, 771),
            (.large, "km", 887, 825),
            (.extraLarge, "en", 797, 735), (.extraLarge, "vi", 837.5, 775.5), (.extraLarge, "th", 873.5, 811.5),
            (.extraLarge, "km", 936.5, 874.5),
            (.extraExtraLarge, "en", 833, 771), (.extraExtraLarge, "vi", 873.5, 811.5),
            (.extraExtraLarge, "th", 918.5, 856.5), (.extraExtraLarge, "km", 981.5, 919.5),
            (.extraExtraExtraLarge, "en", 887, 825), (.extraExtraExtraLarge, "vi", 936.5, 874.5),
            (.extraExtraExtraLarge, "th", 981.5, 919.5), (.extraExtraExtraLarge, "km", 1053.5, 991.5),
            (.accessibilityMedium, "km", nil, 1073.5), (.accessibilityMedium, "hi", nil, 994.5),
            (.accessibilityMedium, "ar", nil, 943.5), (.accessibilityLarge, "hi", nil, 1148),
            (.accessibilityLarge, "ar", nil, 1084.5),
        ]
        for need in needs {
            // Measured in every language the app ships for the standard
            // height, and around their own titles or English's otherwise.
            let measuredStrings = need.lines == "en" ? Self.languages.filter { !["th", "vi"].contains($0) }
                : ["vi", "th"].contains(need.lines) ? [need.lines] : ["en"]
            for strings in measuredStrings {
                let heights = Rows.heights(sizeCategory: need.size,
                                           language: Rows.Language(strings: strings, lines: need.lines))
                let tag = "\(strings) set in \(need.lines) at \(need.size.rawValue)"
                if let two = need.two, let threshold = heights.twoRows {
                    XCTAssertGreaterThanOrEqual(threshold, two + (threshold == 834 ? 1 : 9), tag)
                }
                if let threshold = heights.oneRow {
                    XCTAssertGreaterThanOrEqual(threshold, need.one + 9, tag)
                }
            }
        }
        let accessibilityNeeds: [(size: UIContentSizeCategory, one: [String: CGFloat])] = [
            (.accessibilityMedium, ["de": 951, "en": 888, "es": 919.5, "fr": 888, "id": 888, "ja": 856.5, "ko": 825,
                                    "ms": 888, "pt-BR": 919.5, "pt-PT": 919.5, "th": 994.5, "vi": 943.5,
                                    "zh-Hans": 825, "zh-Hant": 825]),
            (.accessibilityLarge, ["de": 1056.5, "en": 1016.5, "es": 1056.5, "fr": 1096.5, "id": 976.5,
                                   "ja": 1016.5, "ko": 896.5, "ms": 936.5, "pt-BR": 1016.5, "pt-PT": 1056.5,
                                   "th": 1054, "vi": 997.5, "zh-Hans": 856.5, "zh-Hant": 856.5]),
            (.accessibilityExtraLarge, ["de": 1173, "en": 1125, "es": 1221, "fr": 1221, "id": 1173, "ja": 1125,
                                        "ko": 1029, "ms": 1077, "pt-BR": 1125, "pt-PT": 1221, "th": 1387,
                                        "vi": 1252, "zh-Hans": 1029, "zh-Hant": 1029]),
        ]
        for need in accessibilityNeeds {
            for (language, one) in need.one {
                let heights = Rows.heights(sizeCategory: need.size, language: Rows.Language(language))
                XCTAssertNil(heights.twoRows, "\(language) \(need.size.rawValue)")
                XCTAssertGreaterThanOrEqual(heights.oneRow ?? .infinity, one + 9, "\(language) \(need.size.rawValue)")
            }
        }

        // In every language: never more rows in a shorter window, at a larger
        // size or with taller lines, and at most one at accessibility sizes.
        let sizes: [UIContentSizeCategory] = [.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
                                              .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
                                              .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
                                              .accessibilityExtraExtraExtraLarge]
        for language in Self.languages {
            for height in stride(from: CGFloat(400), through: 1400, by: 2) {
                var previous = Int.max
                for size in sizes {
                    let rows = count(height, size, language)
                    let tag = "\(language) \(height) \(size.rawValue)"
                    XCTAssertLessThanOrEqual(rows, previous, tag)
                    XCTAssertLessThanOrEqual(rows, count(height + 2, size, language), tag)
                    XCTAssertLessThanOrEqual(rows, size.isAccessibilityCategory ? 1 : 2, tag)
                    let byLines = ["km", "hi", "ar", "nl"].map { count(height, size, language, lines: $0) }
                    XCTAssertEqual(byLines, byLines.sorted(), "Taller lines never list more rows: \(tag)")
                    previous = rows
                }
            }
        }
    }
}
