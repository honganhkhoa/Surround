//
//  TimeUtilitiesTests.swift
//  SurroundTests
//

import XCTest

final class TimeUtilitiesTests: XCTestCase {
    private let supportedLocalizations = [
        "en",
        "fr",
        "ja",
        "vi",
        "zh-Hans",
        "zh-Hant",
        "ko",
    ]

    // The catalog abbreviates some English forms ("5 days left" ships as "5 days",
    // "%lldh left" pluralizes), and the unit-test bundle can only resolve the
    // source-language fallback. Expectations for those strings are therefore built
    // through String(localized:) with the same templates the code uses, so they
    // hold both here and in the shipping app. The bare minute/second and
    // hour/minute forms are source-language identical and asserted literally.

    func testUnderAnHourUsesMinutesAndSeconds() {
        XCTAssertEqual(timeString(timeLeft: -5), "00:00")
        XCTAssertEqual(timeString(timeLeft: 0), "00:00")
        XCTAssertEqual(timeString(timeLeft: 59), "00:59")
        XCTAssertEqual(timeString(timeLeft: 3599), "59:59")
    }

    func testUnderADayUsesHoursAndMinutes() {
        XCTAssertEqual(timeString(timeLeft: 3600), "1h 00m")
        XCTAssertEqual(timeString(timeLeft: 5 * 3600 + 4 * 60 + 59), "5h 04m")
        XCTAssertEqual(timeString(timeLeft: 86399), "23h 59m")
    }

    func testOneToTwoDaysCollapsesIntoHours() {
        XCTAssertEqual(timeString(timeLeft: 86400), hoursLeft(24))
        XCTAssertEqual(timeString(timeLeft: 86400 + 3 * 3600 + 59 * 60), hoursLeft(27))
    }

    func testMoreThanTwoDaysUsesDaysAndHours() {
        XCTAssertEqual(timeString(timeLeft: 2 * 86400), daysLeft(2))
        XCTAssertEqual(timeString(timeLeft: 2 * 86400 + 3600), daysAndHours(2, 1))
        XCTAssertEqual(timeString(timeLeft: 10 * 86400 + 5 * 3600), daysAndHours(10, 5))
    }

    func testTimeIntervalOverloadTruncatesFractionalSeconds() {
        XCTAssertEqual(timeString(timeLeft: TimeInterval(61.9)), "01:01")
        XCTAssertEqual(timeString(timeLeft: TimeInterval(-0.5)), "00:00")
    }

    func testPreferredLocalizationPreservesChineseScript() {
        XCTAssertEqual(preferredLocalization(for: "zh-Hans-CN"), "zh-Hans")
        XCTAssertEqual(preferredLocalization(for: "zh_CN"), "zh-Hans")
        XCTAssertEqual(preferredLocalization(for: "zh-Hant-TW"), "zh-Hant")
        XCTAssertEqual(preferredLocalization(for: "zh_TW"), "zh-Hant")
        XCTAssertEqual(preferredLocalization(for: "zh_HK"), "zh-Hant")
    }

    func testPreferredLocalizationMatchesKoreanAndExistingLanguages() {
        XCTAssertEqual(preferredLocalization(for: "ko-KR"), "ko")
        XCTAssertEqual(preferredLocalization(for: "fr-CA"), "fr")
        XCTAssertEqual(preferredLocalization(for: "ja-JP"), "ja")
        XCTAssertEqual(preferredLocalization(for: "vi-VN"), "vi")
    }

    func testPreferredLocalizationFallsBackToDevelopmentLanguage() {
        XCTAssertEqual(preferredLocalization(for: "es-ES"), "en")
    }

    private func hoursLeft(_ hours: Int) -> String {
        String(localized: "\(hours)h left")
    }

    private func daysLeft(_ days: Int) -> String {
        String(localized: "\(days) days left")
    }

    private func daysAndHours(_ days: Int, _ hours: Int) -> String {
        String(localized: "\(daysLeft(days)) \(hoursLeft(hours))")
    }

    private func preferredLocalization(for localeIdentifier: String) -> String? {
        LocalizationBundleResolver.preferredLocalization(
            for: Locale(identifier: localeIdentifier),
            from: supportedLocalizations
        )
    }
}
