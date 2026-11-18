//
//  GameControlModelTests.swift
//  SurroundTests
//
//  The value Game Detail's Active games slot shows, computed from one input
//  with no state from before it: a pure value, and a window's first read of
//  each Activity state. Also the window's width class and shape, which the
//  control's frames follow; what each form draws, its frames and its drop
//  order; the rail's and the Mac's native states; what a tap and a hold do,
//  with the press timing; and what VoiceOver says.
//

import XCTest

final class GameControlModelTests: XCTestCase {
    private typealias Model = ActivityModel
    private typealias Context = ActivityModel.GameControlContext

    private func yourMove(_ id: Int, left: TimeInterval = 300) -> Model.LiveGame {
        Model.LiveGame(id: id, isYourMove: true, isClockRunning: true, timeUntilTimeout: left)
    }

    // MARK: The value

    func testTheSlotKeepsTheStateButNotTheClock() {
        let game = yourMove(7, left: 42)
        XCTAssertEqual(GameControlSlot(.chip(game, plusN: 3, hasDot: true)), .chip(gameID: 7, plusN: 3, hasDot: true))
        XCTAssertEqual(GameControlSlot(.gameStarted(game, plusN: 0, hasDot: false)),
                       .gameStarted(gameID: 7, plusN: 0, hasDot: false))
        XCTAssertEqual(GameControlSlot(.gameOverCard(challengeID: 95, plusN: 2)),
                       .gameOverCard(challengeID: 95, plusN: 2))
        XCTAssertEqual(GameControlSlot(.base(plusN: 4)), .base(plusN: 4))
        XCTAssertEqual(GameControlSlot(.dot), .dot)
        XCTAssertEqual(GameControlSlot(.inbox(count: 1)), .inbox(count: 1))

        var ticked = game
        ticked.timeUntilTimeout = 41
        ticked.isInLastByoyomiPeriod = true
        XCTAssertNotEqual(ticked, game)
        XCTAssertEqual(GameControlSlot(.chip(ticked, plusN: 3, hasDot: true)),
                       GameControlSlot(.chip(game, plusN: 3, hasDot: true)),
                       "The clock ticks inside the control, never through the slot.")
    }

    func testTheSlotNeedsOneInputAndNothingFromBefore() {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2, left: 100)]
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        let first = GameControlSlot(input, context: .home)
        XCTAssertEqual(first, .chip(gameID: 2, plusN: 0, hasDot: false))

        var switched = input
        switched.place = .game(id: 2, isOwnGame: true, isLive: true, isOver: false)
        XCTAssertEqual(GameControlSlot(switched, context: .home), .chip(gameID: 1, plusN: 0, hasDot: false),
                       "After an in-place switch the next read has the new game's slot.")
        XCTAssertEqual(GameControlSlot(input, context: .home), first, "Nothing carries over between reads.")
        XCTAssertEqual(GameControlSlot(input, context: Context(isZen: true)), first, "Zen keeps only the chip.")
        XCTAssertNil(GameControlSlot(Model.Input(), context: .home), "A root screen has no slot.")
    }

    // MARK: The window

    private typealias WindowClass = GameControlWindowClass
    private typealias WidthClass = GameControlWindowClass.WidthClass

    func testTheWidthClassesChangeAt375And390And402Points() {
        XCTAssertEqual(WidthClass(width: 320), .floor, "Display Zoom's narrowest phone")
        XCTAssertEqual(WidthClass(width: 374.5), .floor, "Below 375 pt")
        XCTAssertEqual(WidthClass(width: 375), .narrow, "The iPhone SE and the narrowest iPad window")
        XCTAssertEqual(WidthClass(width: 389.5), .narrow, "Below 390 pt")
        XCTAssertEqual(WidthClass(width: 390), .standard, "390 pt itself, as the iPhone 16e")
        XCTAssertEqual(WidthClass(width: 393), .standard, "The iPhone 16")
        XCTAssertEqual(WidthClass(width: 401.5), .standard, "Below 402 pt")
        XCTAssertEqual(WidthClass(width: 402), .wide, "402 pt itself, as the iPhone 17 Pro")
        XCTAssertEqual(WidthClass(width: 1366), .wide)
        XCTAssertEqual(WidthClass.allCases, [.floor, .narrow, .standard, .wide],
                       "The classes go from narrowest to widest.")
        XCTAssertLessThan(WidthClass.floor, .narrow)
        XCTAssertLessThan(WidthClass.narrow, .standard)
        XCTAssertLessThan(WidthClass.standard, .wide)
    }

    func testEachClassRunsFromItsMinimumToTheNextOne() {
        let classes = WidthClass.allCases
        let minimums = classes.map(\.minimumWidth)
        XCTAssertEqual(minimums.first, 0, "Every width has a class.")
        XCTAssertEqual(minimums, minimums.sorted(), "Declared narrowest first.")
        XCTAssertEqual(Set(minimums).count, minimums.count, "No two classes start at one width.")
        for widthClass in classes {
            XCTAssertEqual(WidthClass(width: widthClass.minimumWidth), widthClass, "\(widthClass) starts at its minimum.")
        }
        for (narrower, wider) in zip(classes, classes.dropFirst()) {
            XCTAssertEqual(WidthClass(width: wider.minimumWidth - 0.5), narrower,
                           "Just under \(wider)'s minimum is still \(narrower).")
        }
    }

    func testTheShapeIsLandscapeOnlyWhenTheWindowIsWiderThanTall() {
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 402, height: 874)),
                       WindowClass(widthClass: .wide, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 874, height: 402)),
                       WindowClass(widthClass: .wide, shape: .landscape))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 390, height: 844)),
                       WindowClass(widthClass: .standard, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 320, height: 568)),
                       WindowClass(widthClass: .floor, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 568, height: 320)),
                       WindowClass(widthClass: .wide, shape: .landscape), "Turned, the same window is wide enough.")
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 375, height: 548)),
                       WindowClass(widthClass: .narrow, shape: .portrait))
        XCTAssertEqual(WindowClass(windowSize: CGSize(width: 600, height: 600)).shape, .portrait,
                       "A square window isn't landscape-shaped.")
    }

    func testAResizeWithinAClassAndShapeKeepsTheValue() {
        let standardPhones = [CGSize(width: 390, height: 844), CGSize(width: 393, height: 852)]
        let widePhones = [CGSize(width: 402, height: 874), CGSize(width: 440, height: 956)]
        XCTAssertTrue(standardPhones.allSatisfy { WindowClass(windowSize: $0) == WindowClass(widthClass: .standard,
                                                                                               shape: .portrait) },
                      "Only a resize across a boundary, or a turn, gives the root a new value to publish.")
        XCTAssertTrue(widePhones.allSatisfy { WindowClass(windowSize: $0) == WindowClass(widthClass: .wide,
                                                                                           shape: .portrait) })
        let turned = (standardPhones + widePhones).map { WindowClass(windowSize: CGSize(width: $0.height,
                                                                                         height: $0.width)) }
        XCTAssertTrue(turned.allSatisfy { $0 == WindowClass(widthClass: .wide, shape: .landscape) })
    }

    func testAFullSizeTopBarLacksRoomForTheChipOnlyWhereTheStatusBarSharesItsRow() {
        func fits(_ width: CGFloat, _ height: CGFloat, regular: Bool = true, phone: Bool = false) -> Bool {
            WindowClass(windowSize: CGSize(width: width, height: height), isRegularWidth: regular,
                        isPhone: phone).topBarFitsChip
        }
        // The windows measured with the chip beside three modes.
        XCTAssertFalse(fits(669, 951, phone: true),
                       "The Duo in its tall poses: the status bar takes the row's end, and Zen and Options went to More")
        XCTAssertTrue(fits(668, 741), "iPadOS 27's narrowest regular window, its window controls in the row")
        XCTAssertTrue(fits(671, 741), "iPadOS 26's narrowest regular window")
        XCTAssertTrue(fits(715, 915), "Stage Manager's narrowest regular window on iPadOS 18")
        XCTAssertTrue(fits(834, 1210))
        XCTAssertTrue(fits(1210, 834))
        XCTAssertTrue(fits(744, 1133), "An iPad mini in portrait")
        XCTAssertTrue(fits(956, 440, phone: true), "A Max iPhone in landscape, whose status bar hides")
        XCTAssertTrue(fits(402, 874, regular: false, phone: true), "A compact window shows no full-size top bar")
        XCTAssertTrue(fits(375, 548, regular: false))
        XCTAssertTrue(WindowClass(windowSize: CGSize(width: 669, height: 951)).topBarFitsChip,
                      "Without a size class the window counts as compact")

        // The row's need against what the window leaves it.
        let need = WindowClass.topBarRowForChip, share = WindowClass.statusBarShareOfTopBarRow
        XCTAssertTrue(fits(need, need + 100))
        XCTAssertFalse(fits(need - 0.5, need + 100))
        XCTAssertTrue(fits(need + share, need + share + 100, phone: true), "A tall phone window with room beside the status bar")
        XCTAssertFalse(fits(need + share - 0.5, need + share + 100, phone: true))
        XCTAssertTrue(fits(need + share - 0.5, need, phone: true), "Turned wider than tall, the status bar leaves the row")
    }

    // MARK: What each form draws

    private typealias Drawing = GameControlDrawing
    private let wide = GameControlWindowClass(widthClass: .wide, shape: .portrait)
    private let standard = GameControlWindowClass(widthClass: .standard, shape: .portrait)
    private let narrow = GameControlWindowClass(widthClass: .narrow, shape: .portrait)
    private let floor = GameControlWindowClass(widthClass: .floor, shape: .portrait)

    private func drawing(_ slot: GameControlSlot, _ form: GameControlForm, _ windowClass: GameControlWindowClass? = nil,
                         modes: Int = 2, size: UIContentSizeCategory = .large, allowsPicker: Bool = true,
                         hasCountdown: Bool = true, suddenDeath: Bool = false) throws -> Drawing {
        try XCTUnwrap(Drawing(slot, form: form, windowClass: windowClass, modeCount: modes, sizeCategory: size,
                              allowsPicker: allowsPicker, hasCountdown: hasCountdown, isSuddenDeath: suddenDeath),
                      "\(slot) in \(form)")
    }

    func testTheBottomBarDrawsEachStatesParts() throws {
        let chip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: true), .bottomBar, standard)
        XCTAssertEqual(chip.parts, [.board, .hourglass, .clock, .plusN])
        XCTAssertEqual(chip.dropOrder, [.hourglass, .plusN, .board], "The hourglass drops first, then +N; the board last.")
        XCTAssertEqual(chip.plusN, 3)
        XCTAssertTrue(chip.hasDot, "The dot at the top trailing corner while a challenge or message waits.")
        XCTAssertFalse(chip.isSuddenDeath)

        let suddenDeath = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .bottomBar, standard, suddenDeath: true)
        XCTAssertEqual(suddenDeath.parts, [.board, .suddenDeathMark, .clock], "The mark in the hourglass's place, and no +N.")
        XCTAssertEqual(suddenDeath.dropOrder, [.board], "The mark and the clock never drop; the board goes last.")
        XCTAssertEqual(suddenDeath.plusN, 0)
        XCTAssertTrue(suddenDeath.isSuddenDeath)

        let noCountdown = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .bottomBar, standard, hasCountdown: false)
        XCTAssertEqual(noCountdown.parts, [.board, .hourglass, .plusN], "The hourglass alone, which stays.")
        XCTAssertEqual(noCountdown.dropOrder, [.plusN])
        XCTAssertEqual(try drawing(.chip(gameID: 7, plusN: 0, hasDot: false), .bottomBar).parts,
                       [.board, .hourglass, .clock], "No capsule at 0.")

        let started = try drawing(.gameStarted(gameID: 8, plusN: 2, hasDot: true), .bottomBar)
        XCTAssertEqual(started.parts, [.board, .plusN])
        XCTAssertEqual(started.dropOrder, [.plusN])
        XCTAssertTrue(started.hasDot)
        XCTAssertEqual(try drawing(.gameOverCard(challengeID: 9, plusN: 2), .bottomBar).parts, [.tile, .plusN])
        XCTAssertEqual(try drawing(.base(plusN: 0), .bottomBar).parts, [.icon(.grid)])
        XCTAssertEqual(try drawing(.base(plusN: 3), .bottomBar).parts, [.icon(.grid), .plusN])
        XCTAssertEqual(try drawing(.inbox(count: 3), .bottomBar).parts, [.icon(.inbox), .plusN])
        XCTAssertEqual(try drawing(.inbox(count: 3), .bottomBar).plusN, 3, "The inbox draws its count as +N.")
        let dot = try drawing(.dot, .bottomBar)
        XCTAssertEqual(dot.parts, [.icon(.grid)])
        XCTAssertTrue(dot.hasDot)
        XCTAssertEqual(try drawing(.dot, .bottomBar, allowsPicker: false).parts, [.icon(.inbox)],
                       "Where there is no picker, the dot is on the inbox glyph.")
    }

    func testTopBarsDrawTheChipWithoutItsCount() throws {
        let chip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: true), .topBar, standard)
        XCTAssertEqual(chip.parts, [.board, .hourglass, .clock])
        XCTAssertEqual(chip.dropOrder, [.hourglass, .board], "The hourglass drops first, then the board.")
        XCTAssertEqual(chip.plusN, 0)
        XCTAssertFalse(chip.hasDot)
        let suddenDeath = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .topBar, suddenDeath: true)
        XCTAssertEqual(suddenDeath.parts, [.board, .suddenDeathMark, .clock])
        XCTAssertEqual(suddenDeath.dropOrder, [.board], "The glyph may push the board out; the clock and the glyph stay.")
        XCTAssertEqual(try drawing(.chip(gameID: 7, plusN: 0, hasDot: false), .topBar, hasCountdown: false).dropOrder, [])
        let started = try drawing(.gameStarted(gameID: 8, plusN: 2, hasDot: true), .topBar)
        XCTAssertEqual(started.parts, [.board], "The mini board alone.")
        XCTAssertFalse(started.hasDot)
        XCTAssertEqual(try drawing(.gameOverCard(challengeID: 9, plusN: 2), .topBar).parts, [.tile])
        XCTAssertEqual(try drawing(.base(plusN: 3), .topBar).parts, [.icon(.grid), .plusN])
        XCTAssertEqual(try drawing(.inbox(count: 3), .topBar).parts, [.icon(.inbox), .plusN])
        XCTAssertTrue(try drawing(.dot, .topBar).hasDot)
        for form in [GameControlForm.rail, .mac, .narrowTopBar] {
            XCTAssertNil(Drawing(.base(plusN: 3), form: form, windowClass: standard, modeCount: 2, sizeCategory: .large,
                             allowsPicker: true),
                         "\(form) draws the system's item, not a custom view.")
        }
    }

    func testEachFormHasFixedFramesPerStateAndWindowClass() throws {
        let chipStates: [GameControlSlot] = [.chip(gameID: 7, plusN: 3, hasDot: false),
                                             .gameStarted(gameID: 8, plusN: 3, hasDot: false),
                                             .gameOverCard(challengeID: 9, plusN: 3)]
        for slot in chipStates {
            for modes in [2, 3] {
                XCTAssertEqual(try drawing(slot, .bottomBar, nil, modes: modes).frame.width, 160, "\(slot): nil gives the full frame")
                XCTAssertEqual(try drawing(slot, .bottomBar, standard, modes: modes).frame.width, 160, "\(slot)")
                XCTAssertEqual(try drawing(slot, .bottomBar, wide, modes: modes).frame.width, 160, "\(slot)")
                XCTAssertEqual(try drawing(slot, .bottomBar, floor, modes: modes).frame.width, 44, "\(slot): the floor")
                for windowClass in [nil, floor, narrow, standard, wide] {
                    XCTAssertEqual(try drawing(slot, .topBar, windowClass, modes: modes).frame.width, 96, "\(slot)")
                }
            }
            XCTAssertEqual(try drawing(slot, .bottomBar, narrow, modes: 3).frame.width, 120, "\(slot) beside three modes")
            XCTAssertEqual(try drawing(slot, .bottomBar, narrow, modes: 2).frame.width, 160, "\(slot) beside two modes")
        }
        for form in [GameControlForm.bottomBar, .topBar] {
            XCTAssertEqual(try drawing(.base(plusN: 0), form, standard).frame.width, 44)
            XCTAssertEqual(try drawing(.base(plusN: 3), form, standard).frame.width, 84)
            XCTAssertEqual(try drawing(.base(plusN: 3), form, narrow, modes: 3).frame.width, 84)
            XCTAssertEqual(try drawing(.inbox(count: 3), form, standard).frame.width, 84)
            XCTAssertEqual(try drawing(.dot, form, standard).frame.width, 44)
        }
        XCTAssertEqual(try drawing(.base(plusN: 3), .bottomBar, floor).frame.width, 44)
        XCTAssertEqual(try drawing(.base(plusN: 3), .topBar, floor).frame.width, 84, "Top bars have no floor.")
        let heights = Set(try chipStates.map { try drawing($0, .topBar).frame.height })
        XCTAssertEqual(heights, [44])
    }

    func testNoFrameDependsOnTheClock() throws {
        for form in [GameControlForm.bottomBar, .topBar] {
            for windowClass in [nil, floor, narrow, standard, wide] {
                for modes in [2, 3] {
                    let frames = Set(try [(true, false), (true, true), (false, false)].map { countdown, suddenDeath in
                        try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), form, windowClass, modes: modes,
                                    hasCountdown: countdown, suddenDeath: suddenDeath).frame.width
                    })
                    XCTAssertEqual(frames.count, 1, "\(form) \(String(describing: windowClass)) \(modes): \(frames)")
                }
            }
        }
    }

    /// Above the default text size the bar's own items grow, and a 390 pt
    /// bar on iOS 27 keeps wider side insets: beside three modes the chip
    /// then narrows in a window from 390 pt to 402 pt as well. From 402 pt,
    /// beside two modes and in top bars it keeps its frame at every size.
    func testAboveTheDefaultTextSizeTheChipNarrowsBesideThreeModesBelow402Points() throws {
        XCTAssertEqual(GameControlDrawing.narrowsFromTextSize, .extraLarge,
                       "At 390 pt on iOS 27.2 the full chip fits at the default size and folds the bar from XL.")
        let sizes: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge,
        ]
        let chipStates: [GameControlSlot] = [.chip(gameID: 7, plusN: 3, hasDot: false),
                                             .gameStarted(gameID: 8, plusN: 3, hasDot: false),
                                             .gameOverCard(challengeID: 9, plusN: 3)]
        for slot in chipStates {
            for size in sizes {
                let large = size >= GameControlDrawing.narrowsFromTextSize
                let name = "\(slot) at \(size.rawValue)"
                XCTAssertEqual(try drawing(slot, .bottomBar, standard, modes: 3, size: size).frame.width,
                               large ? 120 : 160, "\(name) beside three modes from 390 pt")
                XCTAssertEqual(try drawing(slot, .bottomBar, standard, modes: 2, size: size).frame.width, 160,
                               "\(name) beside two modes")
                XCTAssertEqual(try drawing(slot, .bottomBar, wide, modes: 3, size: size).frame.width, 160,
                               "\(name) from 402 pt")
                XCTAssertEqual(try drawing(slot, .bottomBar, narrow, modes: 3, size: size).frame.width, 120,
                               "\(name) from 375 pt")
                XCTAssertEqual(try drawing(slot, .bottomBar, floor, modes: 3, size: size).frame.width, 44,
                               "\(name) below 375 pt")
                XCTAssertEqual(try drawing(slot, .bottomBar, nil, modes: 3, size: size).frame.width, 160,
                               "\(name) before the root has measured the window")
                XCTAssertEqual(try drawing(slot, .topBar, standard, modes: 3, size: size).frame.width, 96, name)
                XCTAssertEqual(GameControlDrawing.narrowsBesideModes(.standard, modeCount: 3, sizeCategory: size), large,
                               name)
            }
            XCTAssertEqual(try drawing(slot, .bottomBar, standard, modes: 3, size: .unspecified).frame.width, 160,
                           "An unknown text size counts as the default one.")
        }
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            XCTAssertEqual(try drawing(.base(plusN: 0), .bottomBar, standard, modes: 3, size: size).frame.width, 44)
            XCTAssertEqual(try drawing(.base(plusN: 3), .bottomBar, standard, modes: 3, size: size).frame.width, 84)
            XCTAssertEqual(try drawing(.inbox(count: 3), .bottomBar, standard, modes: 3, size: size).frame.width, 84)
            XCTAssertEqual(try drawing(.dot, .bottomBar, standard, modes: 3, size: size).frame.width, 44)
        }
    }

    func testTheFloorShowsTheBaseIconAloneWithTheDot() throws {
        let chip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: true), .bottomBar, floor, modes: 3)
        XCTAssertEqual(chip.parts, [.icon(.grid)], "Whatever the mode count")
        XCTAssertEqual(chip.dropOrder, [])
        XCTAssertEqual(chip.plusN, 0, "No +N; the popover carries the rest.")
        XCTAssertTrue(chip.hasDot, "The dot where it applies")
        let suddenDeath = try drawing(.chip(gameID: 7, plusN: 0, hasDot: false), .bottomBar, floor, suddenDeath: true)
        XCTAssertEqual(suddenDeath.parts, [.icon(.grid)])
        XCTAssertFalse(suddenDeath.isSuddenDeath, "No chip, so no outline.")
        XCTAssertFalse(try drawing(.base(plusN: 3), .bottomBar, floor).hasDot)
        XCTAssertEqual(try drawing(.inbox(count: 3), .bottomBar, floor).parts, [.icon(.inbox)])
        XCTAssertEqual(try drawing(.dot, .bottomBar, floor, allowsPicker: false).parts, [.icon(.inbox)])
        XCTAssertTrue(GameControlForm.bottomBar.showsIconAlone(in: floor))
        XCTAssertFalse(GameControlForm.bottomBar.showsIconAlone(in: narrow))
        XCTAssertFalse(GameControlForm.bottomBar.showsIconAlone(in: nil))
        XCTAssertFalse(GameControlForm.topBar.showsIconAlone(in: floor))
    }

    // MARK: The drop order

    private let unpadded = GameControlChipSpacing(leading: 0, trailing: 0, between: 0, beforeClock: 0)

    private func widths(_ clock: CGFloat, plusN: CGFloat = 30) -> (GameControlPart) -> CGFloat {
        { part in
            switch part {
            case .board, .tile: 28
            case .icon: 24
            case .hourglass: 14
            case .suddenDeathMark: 26
            case .clock: clock
            case .plusN: plusN
            }
        }
    }

    func testLowerPartsDropUntilTheRestFits() throws {
        // Unpadded: the board 28, the hourglass 14 and +N 30, around the clock.
        let chip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .bottomBar, standard)
        XCTAssertEqual(chip.fit(spacing: unpadded, width: widths(44)).parts, [.board, .hourglass, .clock, .plusN])
        XCTAssertEqual(chip.fit(spacing: unpadded, width: widths(100)).parts, [.board, .clock, .plusN],
                       "172 of 160: the hourglass goes first.")
        XCTAssertEqual(chip.fit(spacing: unpadded, width: widths(110)).parts, [.board, .clock],
                       "Then +N, and the hourglass doesn't come back into the room +N leaves.")
        XCTAssertEqual(chip.fit(spacing: unpadded, width: widths(110)).width, 138)
        XCTAssertEqual(chip.fit(spacing: unpadded, width: widths(140)).parts, [.clock],
                       "The board goes last, for a clock wider than any the chip shows.")

        let narrowChip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .bottomBar, narrow, modes: 3)
        XCTAssertEqual(narrowChip.fit(spacing: unpadded, width: widths(44)).parts, [.board, .hourglass, .clock, .plusN])
        XCTAssertEqual(narrowChip.fit(spacing: unpadded, width: widths(50)).parts, [.board, .clock, .plusN])
        XCTAssertEqual(narrowChip.fit(spacing: unpadded, width: widths(70)).parts, [.board, .clock])

        let topChip = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .topBar)
        XCTAssertEqual(topChip.fit(spacing: unpadded, width: widths(54)).parts, [.board, .hourglass, .clock])
        XCTAssertEqual(topChip.fit(spacing: unpadded, width: widths(60)).parts, [.board, .clock])
        XCTAssertEqual(topChip.fit(spacing: unpadded, width: widths(70)).parts, [.clock])

        let base = try drawing(.base(plusN: 3), .bottomBar)
        XCTAssertEqual(base.fit(spacing: unpadded, width: widths(0, plusN: 60)).parts, [.icon(.grid), .plusN], "84 of 84")
        XCTAssertEqual(base.fit(spacing: unpadded, width: widths(0, plusN: 61)).parts, [.icon(.grid)], "+N gives way.")
    }

    func testTheClockAndTheMarkNeverDropAndAnOverflowIsReported() throws {
        let suddenDeath = try drawing(.chip(gameID: 7, plusN: 3, hasDot: false), .bottomBar, narrow, modes: 3,
                                      suddenDeath: true)
        let fits = suddenDeath.fit(spacing: unpadded, width: widths(66))
        XCTAssertEqual(fits.parts, [.board, .suddenDeathMark, .clock], "120 of 120")
        XCTAssertTrue(fits.fits)
        let wider = suddenDeath.fit(spacing: unpadded, width: widths(67))
        XCTAssertEqual(wider.parts, [.suddenDeathMark, .clock], "A clock wider than any in sudden death: the board gives way.")
        XCTAssertTrue(wider.fits)
        let topBar = try drawing(.chip(gameID: 7, plusN: 0, hasDot: false), .topBar, suddenDeath: true)
        let overflows = topBar.fit(spacing: unpadded, width: widths(80))
        XCTAssertEqual(overflows.parts, [.suddenDeathMark, .clock], "Nothing that never drops goes, and nothing truncates.")
        XCTAssertFalse(overflows.fits)
        XCTAssertEqual(overflows.width, 106)
    }

    func testSpacingJoinsTheClockToItsHourglassOrMark() {
        let spacing = GameControlChipSpacing(leading: 5, trailing: 5, between: 4, beforeClock: 2)
        let width = widths(44)
        XCTAssertEqual(spacing.width(of: [.board, .hourglass, .clock, .plusN], width), 5 + 28 + 4 + 14 + 2 + 44 + 4 + 30 + 5)
        XCTAssertEqual(spacing.width(of: [.board, .clock], width), 5 + 28 + 4 + 44 + 5)
        XCTAssertEqual(spacing.width(of: [.suddenDeathMark, .clock], width), 5 + 26 + 2 + 44 + 5)
        XCTAssertEqual(spacing.width(of: [], width), 0)
    }

    // MARK: The clock and the mark

    func testTheClockIsDigitsOnly() {
        let cases: [(TimeInterval, String, String)] = [
            (42, "00:42", "00:00"), (0, "00:00", "00:00"), (-5, "00:00", "00:00"), (61.9, "01:01", "00:00"),
            (3599, "59:59", "00:00"), (3600, "1:00:00", "0:00:00"), (5400, "1:30:00", "0:00:00"),
            (35999, "9:59:59", "0:00:00"), (36000, "10:00:00", "00:00:00"), (45000, "12:30:00", "00:00:00"),
            (.nan, "00:00", "00:00"), (.infinity, "00:00", "00:00"),
        ]
        for (timeLeft, text, sample) in cases {
            let clock = GameControlClock(timeLeft: timeLeft)
            XCTAssertEqual(clock.text, text, "\(timeLeft)")
            XCTAssertEqual(clock.widestSample, sample, "\(timeLeft)")
            XCTAssertEqual(clock.widestSample.count, clock.text.count)
        }
        XCTAssertEqual(GameControlClock(timeLeft: 42.9).seconds, 42, "Truncated, as Home's chip reads it")
    }

    func testTheMarkIsTheLanguagesTextWhereItFitsItsSlot() {
        XCTAssertEqual(GameControlSuddenDeathMark(bottomBar: "SD"), .text("SD"))
        XCTAssertEqual(GameControlSuddenDeathMark(bottomBar: "MS"), .text("MS"))
        XCTAssertEqual(GameControlSuddenDeathMark(bottomBar: "残1回"), .glyph)
        XCTAssertEqual(GameControlSuddenDeathMark(bottomBar: "最后一次读秒"), .glyph)
        XCTAssertEqual(GameControlSuddenDeathMark(bottomBar: ""), .glyph)
        XCTAssertEqual(GameControlSuddenDeathMark.drawn(in: .topBar), .glyph, "Top bars always draw the glyph.")
        XCTAssertEqual(GameControlSuddenDeathMark.drawn(in: .bottomBar), .text("SD"), "The app's own SD, in English here")
    }

    // MARK: The native forms

    func testTheRailAndTheMacFollowTheirPlacement() {
        XCTAssertEqual(GameControlForm(.bottomBar, isCatalyst: false), .bottomBar)
        XCTAssertEqual(GameControlForm(.topBar, isCatalyst: false), .topBar)
        XCTAssertEqual(GameControlForm(.rail, isCatalyst: false), .rail)
        XCTAssertEqual(GameControlForm(.topBar, isCatalyst: true), .mac, "The Mac is always wide and always native.")
        XCTAssertEqual([GameControlForm.bottomBar, .topBar, .rail, .mac].map(\.isNative), [false, false, true, true])
    }

    func testAWideWindowsTopBarWithoutRoomForTheChipShowsTheNativeItem() {
        let duoTall = WindowClass(windowSize: CGSize(width: 669, height: 951), isRegularWidth: true, isPhone: true)
        let iPadWindow = WindowClass(windowSize: CGSize(width: 671, height: 741), isRegularWidth: true, isPhone: false)
        XCTAssertEqual(GameControlForm(.topBarAfterModes, isCatalyst: false, windowClass: duoTall), .narrowTopBar)
        XCTAssertTrue(GameControlForm.narrowTopBar.isNative)
        XCTAssertEqual(GameControlForm(.topBarAfterModes, isCatalyst: false, windowClass: iPadWindow), .topBar)
        XCTAssertEqual(GameControlForm(.topBarAfterModes, isCatalyst: false, windowClass: nil), .topBar,
                       "Before the root has measured its window, the chip, as the full frames")
        XCTAssertEqual(GameControlForm(.topBarBeforeModes, isCatalyst: false, windowClass: duoTall), .topBar,
                       "Compact landscape's bar always has room")
        XCTAssertEqual(GameControlForm(.bottomBar, isCatalyst: false, windowClass: duoTall), .bottomBar)
        XCTAssertEqual(GameControlForm(.rail, isCatalyst: false, windowClass: duoTall), .rail)
        XCTAssertEqual(GameControlForm(.railSeparated, isCatalyst: false, windowClass: duoTall), .rail)
        XCTAssertEqual(GameControlForm(.topBarAfterModes, isCatalyst: true, windowClass: duoTall), .mac)
        XCTAssertEqual(GameControlForm(.topBarAfterModes, isCatalyst: true, windowClass: iPadWindow), .mac)
    }

    func testTheNativeItemsShowTheSystemsIconAndCount() {
        typealias Item = GameControlNativeItem
        XCTAssertEqual(Item(.chip(gameID: 7, plusN: 2, hasDot: true), allowsPicker: true),
                       Item(icon: .grid, badge: .count(3)), "The chip's game and +N")
        XCTAssertEqual(Item(.gameStarted(gameID: 8, plusN: 0, hasDot: false), allowsPicker: true),
                       Item(icon: .grid, badge: .count(1)))
        XCTAssertEqual(Item(.gameOverCard(challengeID: 9, plusN: 2), allowsPicker: false),
                       Item(icon: .grid, badge: .count(3)))
        XCTAssertEqual(Item(.base(plusN: 0), allowsPicker: true), Item(icon: .grid, badge: .none))
        XCTAssertEqual(Item(.base(plusN: 3), allowsPicker: true), Item(icon: .grid, badge: .count(3)))
        XCTAssertEqual(Item(.dot, allowsPicker: true), Item(icon: .grid, badge: .dot), "An empty-text badge: a red dot")
        XCTAssertEqual(Item(.dot, allowsPicker: false), Item(icon: .inbox, badge: .dot))
        XCTAssertEqual(Item(.inbox(count: 3), allowsPicker: false), Item(icon: .inbox, badge: .count(3)))
        XCTAssertNil(Item(nil, allowsPicker: true), "The slot hides.")
        XCTAssertEqual(Item(nil, allowsPicker: true, keepsPlace: true), Item(icon: .inbox, badge: .none),
                       "The Duo's wide poses keep the unbadged inbox glyph.")
        let zen = ActivityModel.gameControl(zenInput(), context: Context(isZen: true)).map(GameControlSlot.init)
        XCTAssertEqual(zen.flatMap { Item($0, allowsPicker: true) }, Item(icon: .grid, badge: .count(1)),
                       "In Zen a badge of 1")
        XCTAssertEqual(GameControlIcon.grid.systemName, "square.grid.2x2")
        XCTAssertEqual(GameControlIcon.inbox.systemName, "tray")
    }

    private func zenInput() -> Model.Input {
        var input = Model.Input()
        input.liveGames = [yourMove(1), yourMove(2, left: 100), yourMove(3, left: 50)]
        input.challengesReceived = [Model.Challenge(id: 5, isLive: true)]
        input.place = .game(id: 1, isOwnGame: true, isLive: true, isOver: false)
        return input
    }

    // MARK: Tap, touch and hold

    private typealias Interaction = GameControlInteraction

    func testATapShowsTheChipsGameAndAHoldOpensThePopover() {
        for form in [GameControlForm.bottomBar, .topBar] {
            let chip = Interaction(.chip(gameID: 7, plusN: 3, hasDot: true), form: form, windowClass: standard)
            XCTAssertEqual(chip.tap, .show(gameID: 7), "\(form)")
            XCTAssertEqual(chip.hold, .openPopover)
            XCTAssertTrue(chip.offersOpenActivity)
            let started = Interaction(.gameStarted(gameID: 8, plusN: 0, hasDot: false), form: form)
            XCTAssertEqual(started.tap, .show(gameID: 8))
            XCTAssertEqual(started.hold, .openPopover)
            XCTAssertTrue(started.offersOpenActivity)
            for slot in [GameControlSlot.gameOverCard(challengeID: 9, plusN: 2), .base(plusN: 3), .dot, .inbox(count: 3)] {
                let interaction = Interaction(slot, form: form)
                XCTAssertEqual(interaction.tap, .openPopover, "\(slot)")
                XCTAssertEqual(interaction.hold, .openPopover, "\(slot)")
                XCTAssertFalse(interaction.offersOpenActivity, "\(slot): a tap already opens it")
            }
        }
    }

    func testTheNativeItemsAndTheFloorOpenThePopoverOnATap() {
        for form in [GameControlForm.rail, .mac, .narrowTopBar] {
            for slot in [GameControlSlot.chip(gameID: 7, plusN: 0, hasDot: false), .gameStarted(gameID: 8, plusN: 0, hasDot: false),
                         .gameOverCard(challengeID: 9, plusN: 0), .base(plusN: 0), .dot, .inbox(count: 1)] {
                let interaction = Interaction(slot, form: form)
                XCTAssertEqual(interaction.tap, .openPopover, "\(form) \(slot)")
                XCTAssertEqual(interaction.hold, .none, "\(form): a native item takes no hold")
                XCTAssertFalse(interaction.offersOpenActivity)
            }
        }
        let floorChip = Interaction(.chip(gameID: 7, plusN: 3, hasDot: false), form: .bottomBar, windowClass: floor)
        XCTAssertEqual(floorChip.tap, .openPopover, "The floor shows no chip, so a tap can't switch to it.")
        XCTAssertEqual(floorChip.hold, .openPopover)
        XCTAssertFalse(floorChip.offersOpenActivity)
    }

    func testInZenATapSwitchesAndNothingElse() {
        for form in [GameControlForm.topBar, .bottomBar, .rail, .mac] {
            let zen = Interaction(.chip(gameID: 7, plusN: 0, hasDot: false), form: form, isZen: true)
            XCTAssertEqual(zen.tap, .show(gameID: 7), "\(form)")
            XCTAssertEqual(zen.hold, .none, "\(form): no popover in Zen")
            XCTAssertFalse(zen.offersOpenActivity)
            XCTAssertEqual(zen.release(after: 0.8, holdFired: false), .none, "\(form)")
        }
    }

    func testAReleaseHalfASecondAfterThePressNeverSwitches() {
        XCTAssertEqual(Interaction.holdDuration, 0.5)
        let chip = Interaction(.chip(gameID: 7, plusN: 3, hasDot: false), form: .bottomBar)
        XCTAssertEqual(chip.release(after: 0.1, holdFired: false), .show(gameID: 7), "A tap switches.")
        XCTAssertEqual(chip.release(after: 0.49, holdFired: false), .show(gameID: 7))
        XCTAssertEqual(chip.release(after: 0.5, holdFired: false), .openPopover,
                       "A hold that something else took opens the popover, as a hold would.")
        XCTAssertEqual(chip.release(after: 3, holdFired: false), .openPopover)
        XCTAssertEqual(chip.release(after: 1, holdFired: true), .none, "The hold already opened it.")
        XCTAssertEqual(chip.release(after: 0.3, holdFired: true), .none)
        let started = Interaction(.gameStarted(gameID: 8, plusN: 0, hasDot: false), form: .topBar)
        XCTAssertEqual(started.release(after: 0.2, holdFired: false), .show(gameID: 8))
        XCTAssertEqual(started.release(after: 0.6, holdFired: false), .openPopover)
        let base = Interaction(.base(plusN: 3), form: .bottomBar)
        XCTAssertEqual(base.release(after: 0.2, holdFired: false), .openPopover)
        XCTAssertEqual(base.release(after: 1, holdFired: false), .openPopover)
        XCTAssertEqual(base.release(after: 1, holdFired: true), .none)
        for duration in stride(from: 0.5, through: 5, by: 0.25) {
            for slot in [GameControlSlot.chip(gameID: 7, plusN: 0, hasDot: true), .gameStarted(gameID: 8, plusN: 1, hasDot: false)] {
                for form in [GameControlForm.bottomBar, .topBar] {
                    for held in [false, true] {
                        if case .show = Interaction(slot, form: form).release(after: duration, holdFired: held) {
                            XCTFail("\(slot) in \(form) switched after \(duration) s")
                        }
                    }
                }
            }
        }
    }

    // MARK: VoiceOver

    private typealias Spoken = GameControlAccessibility
    private let english = Locale(identifier: "en_US")

    func testTheTimeIsSpokenInFullUnits() {
        XCTAssertEqual(Spoken.spokenDuration(42, locale: english), "42 seconds")
        XCTAssertEqual(Spoken.spokenDuration(1, locale: english), "1 second")
        XCTAssertEqual(Spoken.spokenDuration(0, locale: english), "0 seconds")
        XCTAssertEqual(Spoken.spokenDuration(61.9, locale: english), "1 minute, 1 second", "Truncated as the digits are")
        XCTAssertEqual(Spoken.spokenDuration(3600, locale: english), "1 hour")
        XCTAssertEqual(Spoken.spokenDuration(5400, locale: english), "1 hour, 30 minutes")
        XCTAssertEqual(Spoken.spokenDuration(45000, locale: english), "12 hours, 30 minutes")
    }

    func testVoiceOverSaysTheDrawnStates() {
        let chip = Spoken(.chip(gameID: 7, plusN: 3, hasDot: false), form: .bottomBar, name: "HarborMist",
                          timeLeft: 42, locale: english)
        XCTAssertEqual(chip, Spoken(label: "HarborMist, your move in your live game, 42 seconds left",
                                    value: "3 more in Activity", hint: "Switches to that game.",
                                    updatesFrequently: true, offersOpenActivity: true))
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 0, hasDot: false), form: .topBar, name: "HarborMist",
                              timeLeft: 8, isSuddenDeath: true, locale: english).label,
                       "HarborMist, your move in your live game, sudden death, 8 seconds left")
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 0, hasDot: true), form: .bottomBar, name: "HarborMist",
                              timeLeft: 42, locale: english).value, "New activity waiting")
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 2, hasDot: true), form: .bottomBar, name: "HarborMist",
                              timeLeft: 42, locale: english).value, "2 more in Activity, New activity waiting")
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 1, hasDot: false), form: .bottomBar, name: "HarborMist",
                              timeLeft: 5400, locale: english),
                       Spoken(label: "HarborMist, your move in your live game, 1 hour, 30 minutes left",
                              value: "1 more in Activity", hint: "Switches to that game.",
                              updatesFrequently: true, offersOpenActivity: true))
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 0, hasDot: false), form: .bottomBar, name: "HarborMist",
                              locale: english),
                       Spoken(label: "HarborMist, your move in your live game", value: nil,
                              hint: "Switches to that game.", updatesFrequently: false, offersOpenActivity: true),
                       "Without a countdown")
        XCTAssertEqual(Spoken(.gameStarted(gameID: 8, plusN: 3, hasDot: false), form: .bottomBar, name: "CedarWave",
                              timeLeft: 42, locale: english),
                       Spoken(label: "Game started with CedarWave", value: "3 more in Activity", hint: "Opens that game.",
                              updatesFrequently: false, offersOpenActivity: true))
        XCTAssertEqual(Spoken(.gameOverCard(challengeID: 9, plusN: 2), form: .bottomBar, name: "OrbitFox", locale: english),
                       Spoken(label: "Challenge from OrbitFox", value: "2 more waiting", hint: "Opens Activity.",
                              updatesFrequently: false, offersOpenActivity: false))
        XCTAssertNil(Spoken(.gameOverCard(challengeID: 9, plusN: 0), form: .topBar, name: "OrbitFox").value)
        XCTAssertEqual(Spoken(.base(plusN: 3), form: .bottomBar),
                       Spoken(label: "Active games", value: "3 waiting", hint: nil,
                              updatesFrequently: false, offersOpenActivity: false))
        XCTAssertEqual(Spoken(.base(plusN: 0), form: .topBar).label, "Active games",
                       "The base keeps the label journeys find it by.")
        XCTAssertNil(Spoken(.base(plusN: 0), form: .topBar).value)
        XCTAssertEqual(Spoken(.dot, form: .bottomBar),
                       Spoken(label: "Active games", value: "New activity waiting", hint: nil,
                              updatesFrequently: false, offersOpenActivity: false))
        XCTAssertEqual(Spoken(.dot, form: .bottomBar, allowsPicker: false).label, "Activity")
        XCTAssertEqual(Spoken(.inbox(count: 3), form: .topBar),
                       Spoken(label: "Activity", value: "3 waiting", hint: nil,
                              updatesFrequently: false, offersOpenActivity: false))
        XCTAssertEqual(Spoken(.inbox(count: 1), form: .bottomBar).value, "1 waiting")
        XCTAssertEqual(Spoken.openActivity, "Open Activity")
    }

    func testVoiceOverInZenSaysTheChipWithoutAValue() {
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 0, hasDot: false), form: .topBar, isZen: true,
                              name: "HarborMist", timeLeft: 42, locale: english),
                       Spoken(label: "HarborMist, your move in your live game, 42 seconds left", value: nil,
                              hint: "Switches to that game.", updatesFrequently: true, offersOpenActivity: false))
        XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 0, hasDot: false), form: .mac, isZen: true,
                              name: "HarborMist", timeLeft: 42, locale: english),
                       Spoken(label: "HarborMist, your move in your live game", value: nil,
                              hint: "Switches to that game.", updatesFrequently: false, offersOpenActivity: false),
                       "The Mac's Zen item: no time in a native label")
    }

    func testTheNativeLabelCarriesTheCountButNoTime() {
        for form in [GameControlForm.rail, .mac, .narrowTopBar] {
            let chip = Spoken(.chip(gameID: 7, plusN: 2, hasDot: false), form: form, name: "HarborMist",
                              timeLeft: 42, locale: english)
            XCTAssertEqual(chip, Spoken(label: "HarborMist, your move in your live game, 2 more in Activity", value: nil,
                                        hint: "Opens Activity.", updatesFrequently: false, offersOpenActivity: false))
            XCTAssertEqual(Spoken(.chip(gameID: 7, plusN: 2, hasDot: false), form: form, name: "HarborMist",
                                  timeLeft: 41, locale: english), chip, "\(form): a tick never relabels it")
            XCTAssertEqual(Spoken(.gameStarted(gameID: 8, plusN: 0, hasDot: false), form: form, name: "CedarWave").label,
                           "Game started with CedarWave")
            XCTAssertEqual(Spoken(.gameOverCard(challengeID: 9, plusN: 2), form: form, name: "OrbitFox").label,
                           "Challenge from OrbitFox, 2 more waiting")
            XCTAssertEqual(Spoken(.base(plusN: 3), form: form).label, "Active games, 3 waiting")
            XCTAssertEqual(Spoken(.dot, form: form).label, "Active games, New activity waiting")
            XCTAssertEqual(Spoken(.inbox(count: 3), form: form, allowsPicker: false).label, "Activity, 3 waiting")
            XCTAssertEqual(Spoken(.base(plusN: 0), form: form).hint, "Opens Activity.")
        }
        let floorChip = Spoken(.chip(gameID: 7, plusN: 3, hasDot: true), form: .bottomBar, windowClass: floor,
                               name: "HarborMist", timeLeft: 42, locale: english)
        XCTAssertEqual(floorChip, Spoken(label: "HarborMist, your move in your live game, 3 more in Activity, New activity waiting",
                                         value: nil, hint: "Opens Activity.", updatesFrequently: false,
                                         offersOpenActivity: false), "The floor shows the icon alone, as the native items do.")
    }

    // MARK: Zen in compact layouts

    func testCompactLandscapeZenPutsTheCircleUnderExitWhereTheChipWouldReachOverTheBoard() {
        typealias Corner = GameControlZenCorner
        func corner(_ size: CGSize, trailingInset: CGFloat = 0, verticalToolbar: Bool = false) -> Corner {
            let plan = GameDetailLayoutPlan(size: size, compact: true, zen: true, analyze: false, chat: false,
                                            hidesBoard: false, keyboard: false, accessibility: false,
                                            foldsClock: false, usesVerticalToolbar: verticalToolbar)
            return Corner(column: size.width - plan[.board].maxX, trailingInset: trailingInset)
        }
        // The Zen layouts measured, where the platter lay over the board's
        // corner (by 96 pt in Duo Closed landscape and 21.5 pt on the SE),
        // and where it cleared the board.
        XCTAssertEqual(corner(CGSize(width: 678, height: 466), verticalToolbar: true), .circle(showsCountdown: true),
                       "Duo Closed landscape: a 78 pt column holds the 76 pt button")
        XCTAssertEqual(corner(CGSize(width: 667, height: 375)), .circle(showsCountdown: true),
                       "The iPhone SE in landscape: a 154 pt column")
        XCTAssertEqual(corner(CGSize(width: 750, height: 402), trailingInset: 62), .barChip,
                       "The iPhone 17 Pro in landscape: 182 pt beside the board and 62 beyond the content")

        XCTAssertEqual(Corner(column: Corner.barChipRoom, trailingInset: 0), .barChip)
        XCTAssertEqual(Corner(column: Corner.barChipRoom - 62, trailingInset: 62), .barChip,
                       "The bar puts the platter beyond the content beside a Dynamic Island")
        XCTAssertEqual(Corner(column: Corner.barChipRoom - 0.5, trailingInset: 0), .circle(showsCountdown: true))
        XCTAssertEqual(Corner(column: 76, trailingInset: 0), .circle(showsCountdown: true))
        XCTAssertEqual(Corner(column: 75.5, trailingInset: 100), .circle(showsCountdown: false),
                       "The circle stays inside the content")
        XCTAssertEqual(Corner(column: 44, trailingInset: 0), .circle(showsCountdown: false))
        XCTAssertEqual(Corner(column: 43.5, trailingInset: 0), .noRoom)
        XCTAssertEqual(Corner.width(showsCountdown: true), 76)
        XCTAssertEqual(Corner.width(showsCountdown: false), 44)
    }

    func testAnIPadsCompactZenMovesTheCircleUnderExitWhereBesideItWouldReachOverTheClocks() {
        typealias Corner = GameControlZenCorner
        /// An iPad's compact window, its content from the window's top to
        /// 10 pt above its bottom, with the fixture's 156 pt chips, and Exit
        /// 16 pt from the content's top and 24 from its trailing edge.
        func corner(window: CGSize) -> (corner: Corner?, column: CGFloat, plan: GameDetailLayoutPlan) {
            let size = CGSize(width: window.width, height: window.height - 10)
            let plan = GameDetailLayoutPlan(size: size, compact: true, zen: true, analyze: false, chat: false,
                                            hidesBoard: false, keyboard: false, accessibility: false,
                                            foldsClock: false, zenBoardCenterY: window.height / 2,
                                            narrowChipWidth: 156)
            let column = size.width - plan[.board].maxX
            let exit = CGRect(x: size.width - 24 - 44, y: 16, width: 44, height: 44)
            let corner = Corner(contentExit: exit, countdownBelow: window.width > window.height, width: size.width,
                                column: column, occupied: [plan[.clocks], plan[.board], plan[.actions]])
            return (corner, column, plan)
        }
        // The window measured: barely wider than tall, so the clocks sit above
        // the board, and the circle beside Exit reached over the white clock
        // and the board's top. The 96 pt column under Exit holds it.
        let measured = corner(window: CGSize(width: 524, height: 486))
        XCTAssertEqual(measured.plan[.board], CGRect(x: 96, y: 84, width: 332, height: 332), "As drawn")
        XCTAssertEqual(measured.plan[.clocks], CGRect(x: 102, y: 8, width: 320, height: 68), "As drawn")
        XCTAssertEqual(measured.column, 96)
        XCTAssertEqual(measured.corner, .circle(showsCountdown: true))
        XCTAssertEqual(Corner.columnFrame(showsCountdown: true, width: 524, column: 96, top: 68),
                       CGRect(x: 438, y: 68, width: 76, height: 70), "Clear of the clocks, which end at 422")
        XCTAssertEqual(corner(window: CGSize(width: 486, height: 486)).corner, .circle(showsCountdown: true),
                       "A square window")
        // Wider, the board is centred between columns and the circle stays
        // beside Exit; tall, the board's centring takes the clocks below
        // Exit's band.
        XCTAssertNil(corner(window: CGSize(width: 582, height: 486)).corner)
        XCTAssertNil(corner(window: CGSize(width: 375, height: 800)).corner)
        // A portrait window not much taller than wide keeps its clocks at the
        // top: the circle alone where the column holds it, else none.
        XCTAssertEqual(corner(window: CGSize(width: 486, height: 540)).corner, .circle(showsCountdown: false))
        XCTAssertEqual(corner(window: CGSize(width: 486, height: 600)).corner, .noRoom)

        XCTAssertEqual(Corner.besideExitFrame(CGRect(x: 456, y: 16, width: 44, height: 44), countdownBelow: true),
                       CGRect(x: 378, y: 16, width: 76, height: 70), "2 pt before Exit, as drawn")
        XCTAssertEqual(Corner.besideExitFrame(CGRect(x: 766, y: 16, width: 44, height: 44), countdownBelow: false),
                       CGRect(x: 624, y: 16, width: 124, height: 44), "The circle 18 pt before Exit, as drawn")
    }

    func testAnIPadsHalfScreenZenKeepsTheCircleAloneBesideExitWhereItStaysClearOfTheClocks() {
        typealias Corner = GameControlZenCorner
        /// An iPad window, its content from `top` below the window's top to
        /// `bottom` above its bottom, with the fixture's 156 pt chips, and
        /// Exit 16 pt from the content's top and 24 from its trailing edge.
        func corner(_ width: CGFloat, _ height: CGFloat, top: CGFloat, bottom: CGFloat)
            -> (corner: Corner?, exit: CGRect, plan: GameDetailLayoutPlan) {
            let size = CGSize(width: width, height: height - top - bottom)
            let plan = GameDetailLayoutPlan(size: size, compact: true, zen: true, analyze: false, chat: false,
                                            hidesBoard: false, keyboard: false, accessibility: false,
                                            foldsClock: false, zenBoardCenterY: height / 2 - top,
                                            narrowChipWidth: 156)
            let exit = CGRect(x: width - 24 - 44, y: 16, width: 44, height: 44)
            let corner = Corner(contentExit: exit, countdownBelow: width > height, width: width,
                                column: width - plan[.board].maxX,
                                occupied: [plan[.clocks], plan[.board], plan[.actions]])
            return (corner, exit, plan)
        }
        // Half of an 11-inch iPad in landscape, measured: the clocks sit
        // above the board, the board fills the width, and the circle alone
        // stays beside Exit, 10 pt clear of the white clock.
        let half = corner(600, 834, top: 0, bottom: 20)
        XCTAssertEqual(half.plan[.clocks], CGRect(x: 140, y: 41, width: 320, height: 68), "As drawn")
        XCTAssertEqual(half.plan[.board], CGRect(x: 0, y: 117, width: 600, height: 600), "As drawn")
        XCTAssertEqual(half.corner, .besideExitAlone)
        let circle = Corner.besideExitAloneFrame(half.exit)
        XCTAssertEqual(circle, CGRect(x: 470, y: 16, width: 44, height: 44), "18 pt before Exit, at its top")
        XCTAssertEqual(circle.minX - half.plan[.clocks].maxX, 10)
        // Half of an iPad mini in landscape: within 8 pt of the clock, and
        // no column.
        XCTAssertEqual(corner(561.5, 744, top: 0, bottom: 20).corner, .noRoom)
        // The cramped windows keep the column, which comes first.
        XCTAssertEqual(corner(524, 486, top: 0, bottom: 10).corner, .circle(showsCountdown: true))
        XCTAssertEqual(corner(489, 541, top: 10, bottom: 10).corner, .circle(showsCountdown: false))
        // Portrait halves (11-inch, 13-inch, mini), a landscape third and
        // iPadOS 18.6's narrow Stage Manager window keep the circle and its
        // countdown beside Exit; wider windows are regular and never reach
        // the rule.
        let besideExit: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (412, 1210, 0, 20), (511, 1376, 0, 20), (367, 1133, 0, 20), (400, 834, 0, 20), (456, 915, 24, 25),
        ]
        for (width, height, top, bottom) in besideExit {
            XCTAssertNil(corner(width, height, top: top, bottom: bottom).corner, "\(width) × \(height)")
        }
        // The clearance, both ways: 8 pt all round.
        let exit = CGRect(x: 532, y: 16, width: 44, height: 44)
        let lone = Corner.besideExitAloneFrame(exit)
        func clock(endingAt maxX: CGFloat) -> [CGRect] { [CGRect(x: 0, y: 0, width: maxX, height: 100)] }
        XCTAssertEqual(Corner(contentExit: exit, countdownBelow: false, width: 600, column: 0,
                              occupied: clock(endingAt: lone.minX - 8)), .besideExitAlone)
        XCTAssertEqual(Corner(contentExit: exit, countdownBelow: false, width: 600, column: 0,
                              occupied: clock(endingAt: lone.minX - 7.5)), .noRoom)
        XCTAssertEqual(Corner(contentExit: exit, countdownBelow: false, width: 600, column: 44,
                              occupied: clock(endingAt: lone.minX - 7.5)), .circle(showsCountdown: false),
                       "Then the column alone")
    }

    #if DEBUG
    // MARK: A window's first read

    private typealias Fixtures = ActivityFixtures
    private typealias State = SurroundUITestContract.ActivityFixtureState
    private typealias ID = SurroundUITestContract.ActivityFixtureID
    private let clock = ActivityFixtures.Clock(reference: 1_794_220_920)   // 9 Nov 2026, 10:42 UTC
    private var suites = [String]()

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites.removeAll()
        super.tearDown()
    }

    /// The plain offline journey's start, as `OGSService.offlineUITestInstance()` builds it.
    private func journeyState() throws -> OGSService.BootstrapState {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "game-26268404", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var data = try decoder.decode(OGSGame.self, from: Data(contentsOf: url))
        data.players.black.username = "OrbitFox"
        data.players.white.username = "PuzzleHeron"
        let game = Game(ogsGame: data)
        game.ogsRawData = [:]
        var state = OGSService.BootstrapState()
        state.user = try XCTUnwrap(game.whitePlayer)
        state.isLoggedIn = true
        state.socketStatus = .connected
        state.isLoadingOverview = false
        state.activeGames[SurroundUITestContract.fixtureGameID] = game
        state.finishedGamesSnapshot = []
        return state
    }

    /// A window's service as `selected` starts it, before anything publishes,
    /// with Game Detail's game, 26268404.
    private func openWindow(_ selected: State) throws -> (ogs: OGSService, game: Game, seed: Fixtures.Seed) {
        var state = try journeyState()
        let seed = Fixtures.apply(selected, to: &state, clock: clock)
        let suite = "com.honganhkhoa.Surround.GameControlModelTests.\(UUID().uuidString)"
        suites.append(suite)
        let service = OGSService(
            environment: OGSEnvironment(rootURL: URL(string: "https://ogs.test")!),
            httpClient: OGSOfflineRejectingHTTPClient(), preferences: UserDefaults(suiteName: suite)!,
            ogsWebsocket: OGSOfflineNoOpWebsocket(), connectsAutomatically: false,
            usesSurroundOverviewService: false, enablesAppSideEffects: false, startsTimers: false,
            installsObservers: false, initialState: state)
        Fixtures.finish(selected, service: service)
        let game = try XCTUnwrap(service.activeGames[SurroundUITestContract.fixtureGameID], "\(selected)")
        return (service, game, seed)
    }

    private func firstSlot(_ selected: State, _ context: Context = .home) throws -> GameControlSlot? {
        let window = try openWindow(selected)
        return GameControlSlot(ogs: window.ogs, showing: window.game, context: context,
                               startedGames: window.seed.startedGames, now: clock.now)
    }

    func testAWindowsFirstReadGivesEachSlot() throws {
        let harborMist = ID.harborMistGameID
        XCTAssertEqual(try firstSlot(.liveYourMove), .chip(gameID: harborMist, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.several), .chip(gameID: harborMist, plusN: 0, hasDot: true))
        XCTAssertEqual(try firstSlot(.several, Context(isZen: true)), .chip(gameID: harborMist, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.gameStarted), .gameStarted(gameID: ID.startedGameID, plusN: 0, hasDot: false))
        XCTAssertEqual(try firstSlot(.challengeReceived), .dot)
        XCTAssertEqual(try firstSlot(.nothingLeads), .base(plusN: 3))
        XCTAssertEqual(try firstSlot(.nothingLeads, Context(allowsPicker: false)), .inbox(count: 3))
        XCTAssertEqual(try firstSlot(.nothingWaiting), .base(plusN: 0))
        XCTAssertNil(try firstSlot(.nothingWaiting, Context(allowsPicker: false)))
        XCTAssertEqual(try firstSlot(.rematchOffered), .base(plusN: 1))
        XCTAssertEqual(try firstSlot(.rematchOffered, Context(cardChallengeID: ID.rematchChallengeID)),
                       .gameOverCard(challengeID: ID.rematchChallengeID, plusN: 0))
    }

    func testTheWindowsStartedGamesAndTimeAreInputs() throws {
        let window = try openWindow(.gameStarted)
        let started = window.seed.startedGames
        XCTAssertEqual(GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                                       startedGames: [:], now: clock.now),
                       .base(plusN: 0), "Without the window's started games it is a live game on their move.")
        XCTAssertEqual(GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                                       startedGames: started, now: clock.now + Model.startedLeadDuration),
                       .base(plusN: 0), "It leads for 30 s.")
    }

    func testTheGameOnScreenCountsAsOverTheMomentItEnds() throws {
        let window = try openWindow(.challengeReceived)
        func slot() -> GameControlSlot? {
            GameControlSlot(ogs: window.ogs, showing: window.game, context: .home,
                            startedGames: window.seed.startedGames, now: clock.now)
        }
        XCTAssertEqual(slot(), .dot)
        window.game.gamePhase = .finished
        XCTAssertTrue(window.ogs.liveGames.contains { $0 === window.game }, "The service still lists it as live.")
        XCTAssertEqual(slot(), .base(plusN: 1), "Game over releases what waited, read from the game itself.")
    }

    func testSignedOutThereIsNoSlot() throws {
        let window = try openWindow(.several)
        window.ogs.user = nil
        for context in [Context.home, Context(isZen: true), Context(allowsPicker: false)] {
            XCTAssertNil(GameControlSlot(ogs: window.ogs, showing: window.game, context: context,
                                         startedGames: window.seed.startedGames, now: clock.now), "\(context)")
        }
    }
    #endif
}
