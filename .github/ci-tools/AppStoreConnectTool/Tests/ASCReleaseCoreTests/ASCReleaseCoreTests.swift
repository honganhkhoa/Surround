import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ASCReleaseCore

final class ASCReleaseCoreTests: XCTestCase {
    func testJSONValueAnyInitializerDistinguishesNumbersFromBooleans() throws {
        let raw = try JSONSerialization.jsonObject(with: Data("[0,1,false,true]".utf8))

        XCTAssertEqual(
            try JSONValue(any: raw),
            .array([.number(0), .number(1), .bool(false), .bool(true)])
        )
    }

    func testFileIOAtomicallyOverwritesExistingArtifact() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("artifact.json")
            try FileIO.writeJSONValue(.object(["value": .string("first")]), to: url)
            try FileIO.writeJSONValue(.object(["value": .string("second")]), to: url)
            XCTAssertEqual(try FileIO.readJSON(at: url)["value"], .string("second"))
        }
    }

    func testReleaseValidationPreservesExplicitNullAndReadsEveryLocaleFile() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try FileIO.writeJSONValue(.object([
                "schemaVersion": .number(1),
                "bundleId": .string("com.example.App"),
                "platform": .string("IOS"),
                "localizations": .array([
                    .object([
                        "appStoreLocale": .string("en-US"),
                        "screenshotConfiguration": .string("en-US"),
                    ]),
                    .object([
                        "appStoreLocale": .string("zh-Hant"),
                        "screenshotConfiguration": .string("zh-Hant-TW"),
                    ]),
                ]),
            ]), to: configURL)
            try FileIO.write(data: Data("English notes\n".utf8), to: directory.appendingPathComponent("en.txt"))
            try FileIO.write(data: Data("繁體中文說明\n".utf8), to: directory.appendingPathComponent("zh.txt"))
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "schemaVersion": .number(1),
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("en.txt"),
                        "marketingUrl": .null,
                    ]),
                    "zh-Hant": .object([
                        "whatsNewFile": .string("zh.txt"),
                        "name": .string("圍棋天地"),
                    ]),
                ]),
            ]), to: releaseURL)

            let normalized = try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )
            XCTAssertEqual(normalized.version, "2.1")
            XCTAssertEqual(normalized.localizations.map(\.whatsNew), ["English notes", "繁體中文說明"])
            XCTAssertEqual(normalized.localizations[0].versionMetadata["marketingUrl"], .null)
            XCTAssertEqual(normalized.localizations[1].appMetadata["name"], .string("圍棋天地"))
        }
    }

    func testKeywordsLimitAccepts100MultibyteUTF16CodeUnits() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(data: Data("Notes".utf8), to: directory.appendingPathComponent("notes.txt"))
            let keywords = String(repeating: "界", count: 100)
            XCTAssertEqual(keywords.count, 100)
            XCTAssertEqual(keywords.utf16.count, 100)
            XCTAssertEqual(keywords.utf8.count, 300)
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "keywords": .string(keywords),
                    ]),
                ]),
            ]), to: releaseURL)

            let normalized = try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )
            XCTAssertEqual(normalized.localizations[0].versionMetadata["keywords"], .string(keywords))
        }
    }

    func testKeywordsLimitAccepts100UTF16CodeUnitsAcrossThaiCombiningSequences() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(data: Data("Notes".utf8), to: directory.appendingPathComponent("notes.txt"))
            let keywords = String(repeating: "กำ", count: 50)
            XCTAssertEqual(keywords.count, 50)
            XCTAssertEqual(keywords.unicodeScalars.count, 100)
            XCTAssertEqual(keywords.utf16.count, 100)
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "keywords": .string(keywords),
                    ]),
                ]),
            ]), to: releaseURL)

            let normalized = try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )
            XCTAssertEqual(normalized.localizations[0].versionMetadata["keywords"], .string(keywords))
        }
    }

    func testKeywordsLimitRejects102UTF16CodeUnitsAcrossThaiCombiningSequences() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(data: Data("Notes".utf8), to: directory.appendingPathComponent("notes.txt"))
            let keywords = String(repeating: "กำ", count: 51)
            XCTAssertEqual(keywords.count, 51)
            XCTAssertEqual(keywords.unicodeScalars.count, 102)
            XCTAssertEqual(keywords.utf16.count, 102)
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "keywords": .string(keywords),
                    ]),
                ]),
            ]), to: releaseURL)

            XCTAssertThrowsError(try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("102 UTF-16 code units; maximum is 100"))
            }
        }
    }

    func testKeywordsLimitRejects101UTF16CodeUnits() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(data: Data("Notes".utf8), to: directory.appendingPathComponent("notes.txt"))
            let keywords = String(repeating: "界", count: 101)
            XCTAssertEqual(keywords.count, 101)
            XCTAssertEqual(keywords.utf16.count, 101)
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "keywords": .string(keywords),
                    ]),
                ]),
            ]), to: releaseURL)

            XCTAssertThrowsError(try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("101 UTF-16 code units; maximum is 100"))
            }
        }
    }

    func testReleaseValidationRejectsUnknownTopLevelAndNestedKeys() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(
                data: Data("Notes".utf8),
                to: directory.appendingPathComponent("notes.txt")
            )
            let releaseURL = directory.appendingPathComponent("release.json")

            func assertRejected(_ value: JSONValue, containing expected: String) throws {
                try FileIO.writeJSONValue(value, to: releaseURL)
                XCTAssertThrowsError(try ReleaseValidator.normalize(
                    releaseURL: releaseURL,
                    configurationURL: configURL
                )) { error in
                    XCTAssertTrue(
                        error.localizedDescription.contains(expected),
                        "Unexpected error: \(error)"
                    )
                }
            }

            try assertRejected(.object([
                "version": .string("2.1"),
                "unexpected": .bool(true),
                "localizations": .object([
                    "en-US": .object(["whatsNewFile": .string("notes.txt")]),
                ]),
            ]), containing: "Unknown fields in release")

            try assertRejected(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "versionMetadata": .object(["releaseType": .string("MANUAL")]),
                    ]),
                ]),
            ]), containing: "Unknown fields in versionMetadata")

            try assertRejected(.object([
                "version": .string("2.1"),
                "localizations": .object([
                    "en-US": .object([
                        "whatsNewFile": .string("notes.txt"),
                        "appMetadata": .object(["keywords": .string("go")]),
                    ]),
                ]),
            ]), containing: "Unknown fields in appMetadata")

            try assertRejected(.object([
                "version": .string("2.1"),
                "versionMetadata": .object(["releaseType": .string("MANUAL")]),
                "localizations": .object([
                    "en-US": .object(["whatsNewFile": .string("notes.txt")]),
                ]),
            ]), containing: "Unknown fields in top-level versionMetadata")
        }
    }

    func testReleaseValidationRejectsDuplicateCopyright() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            try FileIO.write(
                data: Data("Notes".utf8),
                to: directory.appendingPathComponent("notes.txt")
            )
            let releaseURL = directory.appendingPathComponent("release.json")
            try FileIO.writeJSONValue(.object([
                "version": .string("2.1"),
                "copyright": .string("2026 Example"),
                "versionMetadata": .object([
                    "copyright": .string("2026 Example"),
                ]),
                "localizations": .object([
                    "en-US": .object(["whatsNewFile": .string("notes.txt")]),
                ]),
            ]), to: releaseURL)

            XCTAssertThrowsError(try ReleaseValidator.normalize(
                releaseURL: releaseURL,
                configurationURL: configURL
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("copyright is specified twice"))
            }
        }
    }

    func testReleaseMetadataFilesMustBeRelativeRegularDescendants() throws {
        try withTemporaryDirectory { directory in
            let package = directory.appendingPathComponent("release-package")
            try FileManager.default.createDirectory(
                at: package,
                withIntermediateDirectories: true
            )
            let configURL = directory.appendingPathComponent("locales.json")
            try writeSingleLocaleConfig(to: configURL)
            let secretURL = directory.appendingPathComponent("secret.txt")
            try FileIO.write(data: Data("secret".utf8), to: secretURL)
            let releaseURL = package.appendingPathComponent("release.json")

            func assertPathRejected(_ path: String, containing expected: String) throws {
                try FileIO.writeJSONValue(.object([
                    "version": .string("2.1"),
                    "localizations": .object([
                        "en-US": .object(["whatsNewFile": .string(path)]),
                    ]),
                ]), to: releaseURL)
                XCTAssertThrowsError(try ReleaseValidator.normalize(
                    releaseURL: releaseURL,
                    configurationURL: configURL
                )) { error in
                    XCTAssertTrue(
                        error.localizedDescription.contains(expected),
                        "Unexpected error: \(error)"
                    )
                }
            }

            try assertPathRejected(secretURL.path, containing: "must be a relative path")
            try assertPathRejected("../secret.txt", containing: "must resolve to a file inside")

            let externalLink = package.appendingPathComponent("linked-secret.txt")
            try FileManager.default.createSymbolicLink(
                at: externalLink,
                withDestinationURL: secretURL
            )
            try assertPathRejected(
                "linked-secret.txt",
                containing: "must resolve to a file inside"
            )

            let directoryReference = package.appendingPathComponent("notes-directory")
            try FileManager.default.createDirectory(
                at: directoryReference,
                withIntermediateDirectories: true
            )
            try assertPathRejected(
                "notes-directory",
                containing: "must resolve to a regular file"
            )
        }
    }

    func testAPIClientFollowsPaginationAndUsesBearerJWT() throws {
        let transport = MockTransport { request in
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url?.query == nil {
                return .json(200, """
                {"data":[{"type":"widgets","id":"one"}],
                 "links":{"next":"https://example.test/v1/widgets?page=2"}}
                """)
            }
            return .json(200, #"{"data":[{"type":"widgets","id":"two"}],"links":{}}"#)
        }
        let key = P256.Signing.PrivateKey()
        let client = ASCAPIClient(
            credentials: ASCCredentials(
                keyId: "KEY",
                issuerId: "00000000-0000-0000-0000-000000000000",
                privateKeyPEM: key.pemRepresentation
            ),
            baseURL: URL(string: "https://example.test")!,
            transport: transport,
            maxRetries: 0
        )
        let resources = try client.list(path: "/v1/widgets")
        XCTAssertEqual(resources.compactMap { $0["id"]?.stringValue }, ["one", "two"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testAPIClientRejectsCrossOriginPaginationBeforeSendingJWT() throws {
        let transport = MockTransport { _ in
            .json(200, """
            {"data":[{"type":"widgets","id":"one"}],
             "links":{"next":"https://attacker.example/v1/widgets?page=2"}}
            """)
        }
        let client = makeAPIClient(
            baseURL: URL(string: "https://example.test")!,
            transport: transport,
            maxRetries: 0
        )

        XCTAssertThrowsError(try client.list(path: "/v1/widgets")) { error in
            XCTAssertTrue(error.localizedDescription.contains("cross-origin"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testSnapshotCapturesSeparateCompleteLiveAndDraftAppInfo() throws {
        func appInfoDetail(id: String, state: String, suffix: String) -> String {
            """
            {"data":{"type":"appInfos","id":"\(id)","attributes":{
              "state":"\(state)","appStoreAgeRating":"FOUR_PLUS","kidsAgeBand":null},
              "relationships":{
                "ageRatingDeclaration":{"data":{"type":"ageRatingDeclarations","id":"rating-\(suffix)"}},
                "appInfoLocalizations":{"data":[{"type":"appInfoLocalizations","id":"info-loc-\(suffix)"}]},
                "primaryCategory":{"data":{"type":"appCategories","id":"games"}},
                "primarySubcategoryOne":{"data":{"type":"appCategories","id":"board"}},
                "primarySubcategoryTwo":{"data":null},"secondaryCategory":{"data":null},
                "secondarySubcategoryOne":{"data":null},"secondarySubcategoryTwo":{"data":null}
              }},"included":[
                {"type":"appInfoLocalizations","id":"info-loc-\(suffix)","attributes":{
                  "locale":"en-US","name":"Example","subtitle":"Play Go",
                  "privacyPolicyUrl":"https://example.com/privacy",
                  "privacyChoicesUrl":null,"privacyPolicyText":null}},
                {"type":"appCategories","id":"games","attributes":{}},
                {"type":"appCategories","id":"board","attributes":{}},
                {"type":"ageRatingDeclarations","id":"rating-\(suffix)","attributes":{
                  "gambling":false,"unrestrictedWebAccess":false}}
              ]}
            """
        }

        let transport = MockTransport { request in
            switch request.url?.path {
            case "/v1/apps":
                return .json(200, #"{"data":[{"type":"apps","id":"app"}]}"#)
            case "/v1/apps/app/appStoreVersions":
                return .json(200, #"{"data":[{"type":"appStoreVersions","id":"source-version","attributes":{"versionString":"2.2","platform":"IOS","appVersionState":"READY_FOR_DISTRIBUTION","releaseType":"AFTER_APPROVAL"}}]}"#)
            case "/v1/appStoreVersions/source-version/appStoreVersionLocalizations":
                return .json(200, #"{"data":[{"type":"appStoreVersionLocalizations","id":"source-locale","attributes":{"locale":"en-US","description":"Description","keywords":"go","supportUrl":"https://example.com/support","whatsNew":"Old"}}]}"#)
            case "/v1/appStoreVersionLocalizations/source-locale/appScreenshotSets":
                return .json(200, #"{"data":[]}"#)
            case "/v1/apps/app/appInfos":
                return .json(200, #"{"data":[{"type":"appInfos","id":"live-info","attributes":{"state":"READY_FOR_DISTRIBUTION"}},{"type":"appInfos","id":"draft-info","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}]}"#)
            case "/v1/appInfos/live-info":
                XCTAssertEqual(
                    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "limit[appInfoLocalizations]" })?
                        .value,
                    "50"
                )
                return .json(200, appInfoDetail(
                    id: "live-info",
                    state: "READY_FOR_DISTRIBUTION",
                    suffix: "live"
                ))
            case "/v1/appInfos/draft-info":
                return .json(200, appInfoDetail(
                    id: "draft-info",
                    state: "PREPARE_FOR_SUBMISSION",
                    suffix: "draft"
                ))
            default:
                XCTFail("Unexpected snapshot request \(request.url?.absoluteString ?? "")")
                return .json(500, #"{"errors":[{"detail":"unexpected"}]}"#)
            }
        }
        let release = NormalizedRelease(
            version: "2.2.1",
            bundleId: "com.example.App",
            platform: "IOS",
            sourceReleasePath: "/release.json",
            sourceDigest: "source",
            localizations: [NormalizedLocaleRelease(
                appStoreLocale: "en-US",
                screenshotConfiguration: "en-US",
                whatsNew: "New",
                versionMetadata: ["whatsNew": .string("New")],
                appMetadata: [:],
                sourceFiles: [:]
            )],
            versionMetadata: [:]
        )

        let snapshot = try SnapshotService(
            client: makeAPIClient(transport: transport, maxRetries: 0)
        ).capture(release: release)
        XCTAssertEqual(snapshot.sourceAppInfo?.id, "live-info")
        XCTAssertEqual(snapshot.targetAppInfo?.id, "draft-info")
        XCTAssertEqual(snapshot.appInfo?.id, "draft-info")
        XCTAssertEqual(snapshot.sourceAppInfo?.details?.primaryCategoryId, "games")
        XCTAssertEqual(snapshot.targetAppInfo?.details?.primarySubcategoryOneId, "board")
        XCTAssertEqual(
            snapshot.sourceAppInfo?.details?.ageRatingDeclarationAttributes["gambling"],
            .bool(false)
        )
        XCTAssertEqual(try SnapshotService.fingerprint(snapshot: snapshot), snapshot.fingerprint)
    }

    func testPOSTDoesNotRetryAmbiguousHTTPResponses() throws {
        for statusCode in [429, 503] {
            let transport = MockTransport { _ in
                .json(statusCode, #"{"errors":[{"detail":"try later"}]}"#)
            }
            let client = makeAPIClient(transport: transport, maxRetries: 3)

            XCTAssertThrowsError(try client.request(
                method: "POST",
                path: "/v1/widgets",
                body: .object(["data": .object([:])])
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("not retried"))
                XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testPOSTDoesNotRetryAmbiguousNetworkFailure() throws {
        let transport = MockTransport { _ in throw URLError(.timedOut) }
        let client = makeAPIClient(transport: transport, maxRetries: 3)

        XCTAssertThrowsError(try client.request(
            method: "POST",
            path: "/v1/widgets",
            body: .object(["data": .object([:])])
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("not retried"))
            XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testIdempotentRequestStillRetriesTransientResponse() throws {
        var callCount = 0
        let transport = MockTransport { _ in
            callCount += 1
            if callCount == 1 {
                return TransportResponse(
                    data: Data(#"{"errors":[{"detail":"try later"}]}"#.utf8),
                    statusCode: 503,
                    headers: ["retry-after": "0"]
                )
            }
            return .json(200, #"{"data":{"type":"widgets","id":"one"}}"#)
        }
        let client = makeAPIClient(transport: transport, maxRetries: 1)

        let response = try client.request(method: "GET", path: "/v1/widgets/one")
        XCTAssertEqual(response?["data"]?["id"]?.stringValue, "one")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSingleAttemptPATCHDoesNotRetryTransientResponse() throws {
        let transport = MockTransport { _ in
            TransportResponse(
                data: Data(#"{"errors":[{"detail":"try later"}]}"#.utf8),
                statusCode: 503,
                headers: ["retry-after": "0"]
            )
        }
        let client = makeAPIClient(transport: transport, maxRetries: 3)

        XCTAssertThrowsError(try client.request(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/locale-one",
            body: .object(["data": .object([:])]),
            retryPolicy: .singleAttempt
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTP 503"))
            XCTAssertTrue(error.localizedDescription.contains("not retried"))
            XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testSingleAttemptPATCHDoesNotRetryNetworkFailure() throws {
        let transport = MockTransport { _ in throw URLError(.timedOut) }
        let client = makeAPIClient(transport: transport, maxRetries: 3)

        XCTAssertThrowsError(try client.request(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/locale-one",
            body: .object(["data": .object([:])]),
            retryPolicy: .singleAttempt
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("not retried"))
            XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testDefaultPATCHStillRetriesTransientResponse() throws {
        var callCount = 0
        let transport = MockTransport { _ in
            callCount += 1
            if callCount == 1 {
                return TransportResponse(
                    data: Data(#"{"errors":[{"detail":"try later"}]}"#.utf8),
                    statusCode: 503,
                    headers: ["retry-after": "0"]
                )
            }
            return .json(200, #"{"data":{"type":"appStoreVersionLocalizations","id":"locale-one"}}"#)
        }
        let client = makeAPIClient(transport: transport, maxRetries: 1)

        let response = try client.request(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/locale-one",
            body: .object(["data": .object([:])])
        )
        XCTAssertEqual(response?["data"]?["id"]?.stringValue, "locale-one")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testUploadUsesExactSliceAndNoJWT() throws {
        let transport = MockTransport { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.httpBody, Data([2, 3, 4]))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "yes")
            return TransportResponse(data: Data(), statusCode: 200)
        }
        let client = ASCAPIClient(
            credentials: ASCCredentials(keyId: "unused", issuerId: "unused", privateKeyPEM: "unused"),
            transport: transport,
            maxRetries: 0
        )
        try client.upload(
            operation: UploadOperation(
                method: "PUT",
                url: "https://upload.example.test/chunk",
                offset: 2,
                length: 3,
                requestHeaders: [UploadHeader(name: "X-Test", value: "yes")]
            ),
            fileData: Data([0, 1, 2, 3, 4, 5])
        )
    }

    func testManifestValidatesCaptureAndScreenshotOrientation() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("config.json")
            try FileIO.writeJSONValue(.object([
                "bundleId": .string("com.example.App"),
                "localizations": .array([.object([
                    "appStoreLocale": .string("en-US"),
                    "screenshotConfiguration": .string("en-US"),
                ])]),
                "screenshotFamilies": .array([
                    .object([
                        "name": .string("iphone-6.9"), "directory": .string("iphone-6.9"),
                        "displayType": .string("APP_IPHONE_67"), "expectedCount": .number(1),
                        "pixelWidth": .number(101), "pixelHeight": .number(201),
                        "additionalPixelSizes": .array([.object([
                            "pixelWidth": .number(100), "pixelHeight": .number(200),
                        ])]),
                    ]),
                    .object([
                        "name": .string("ipad-13"), "directory": .string("ipad-13"),
                        "displayType": .string("APP_IPAD_PRO_3GEN_129"), "expectedCount": .number(1),
                        "pixelWidth": .number(200), "pixelHeight": .number(100),
                    ]),
                ]),
            ]), to: configURL)
            let normalized = NormalizedRelease(
                version: "2.1", bundleId: "com.example.App", platform: "IOS",
                sourceReleasePath: "/release.json", sourceDigest: "source",
                localizations: [NormalizedLocaleRelease(
                    appStoreLocale: "en-US", screenshotConfiguration: "en-US", whatsNew: "Notes",
                    versionMetadata: ["whatsNew": .string("Notes")], appMetadata: [:], sourceFiles: [:]
                )], versionMetadata: [:]
            )
            let releaseURL = directory.appendingPathComponent("normalized.json")
            try FileIO.writeJSON(normalized, to: releaseURL)
            let remoteLocale = RemoteLocalization(
                id: "loc", locale: "en-US", attributes: ["locale": .string("en-US")], screenshotSets: []
            )
            let version = RemoteVersion(
                id: "version", versionString: "2.1", state: "PREPARE_FOR_SUBMISSION",
                attributes: ["versionString": .string("2.1")], localizations: [remoteLocale]
            )
            let appInfo = RemoteAppInfo(
                id: "info", state: "PREPARE_FOR_SUBMISSION",
                localizations: [RemoteAppInfoLocalization(
                    id: "info-loc", locale: "en-US", attributes: ["locale": .string("en-US")]
                )]
            )
            let snapshotDraft = RemoteSnapshot(
                capturedAt: "now", fingerprint: "", appId: "app", bundleId: "com.example.App",
                platform: "IOS", requestedVersion: "2.1", targetVersion: version,
                sourceVersion: version, appInfo: appInfo
            )
            let snapshot = RemoteSnapshot(
                capturedAt: snapshotDraft.capturedAt,
                fingerprint: try SnapshotService.fingerprint(snapshot: snapshotDraft),
                appId: snapshotDraft.appId, bundleId: snapshotDraft.bundleId,
                platform: snapshotDraft.platform, requestedVersion: snapshotDraft.requestedVersion,
                targetVersion: snapshotDraft.targetVersion, sourceVersion: snapshotDraft.sourceVersion,
                appInfo: snapshotDraft.appInfo
            )
            let snapshotURL = directory.appendingPathComponent("snapshot.json")
            try FileIO.writeJSON(snapshot, to: snapshotURL)
            let metadataURL = directory.appendingPathComponent("capture.json")
            try FileIO.writeJSONValue(.object([
                "locales": .array([.string("en-US")]),
                "expectedScreenshotCount": .number(2),
                "devices": .object(["iphone-6.9": .object([:]), "ipad-13": .object([:])]),
                "scenes": .object([
                    "iphone-6.9": .array([.string("01")]),
                    "ipad-13": .array([.string("01")]),
                ]),
            ]), to: metadataURL)
            let screenshotRoot = directory.appendingPathComponent("screenshots/en-US")
            try FileIO.write(data: png(width: 100, height: 200), to: screenshotRoot.appendingPathComponent("iphone-6.9/01.png"))
            try FileIO.write(data: png(width: 200, height: 100), to: screenshotRoot.appendingPathComponent("ipad-13/01.png"))
            let manifestURL = directory.appendingPathComponent("manifest.json")
            let reviewURL = directory.appendingPathComponent("review.html")
            let manifest = try ManifestBuilder.build(
                releaseURL: releaseURL, configurationURL: configURL, screenshotsRoot: directory.appendingPathComponent("screenshots"),
                captureMetadataURL: metadataURL, remoteSnapshotURL: snapshotURL,
                outputURL: manifestURL, reviewHTMLURL: reviewURL
            )
            try ManifestBuilder.verify(manifest)
            XCTAssertEqual(manifest.localizations.flatMap(\.screenshotSets).flatMap(\.screenshots).count, 2)
            XCTAssertEqual(manifest.localizations[0].screenshotSets[0].pixelWidth, 100)
            XCTAssertEqual(manifest.localizations[0].screenshotSets[0].pixelHeight, 200)
            XCTAssertTrue(try String(contentsOf: reviewURL).contains("→"))
        }
    }

    func testImageValidationRejectsCorruptDimensionsAlphaAndOrientation() throws {
        let valid = try png(width: 10, height: 20)
        XCTAssertNoThrow(try ImageValidation.validateScreenshot(
            valid, pixelWidth: 10, pixelHeight: 20, context: "valid"
        ))
        XCTAssertThrowsError(try ImageValidation.validateScreenshot(
            valid.prefix(valid.count / 2), pixelWidth: 10, pixelHeight: 20, context: "truncated"
        ))
        XCTAssertThrowsError(try ImageValidation.validateScreenshot(
            valid, pixelWidth: 11, pixelHeight: 20, context: "dimensions"
        ))
        XCTAssertThrowsError(try ImageValidation.validateScreenshot(
            png(width: 10, height: 20, hasAlpha: true),
            pixelWidth: 10, pixelHeight: 20, context: "alpha"
        ))
        XCTAssertThrowsError(try ImageValidation.validateScreenshot(
            png(width: 10, height: 20, orientation: 6),
            pixelWidth: 10, pixelHeight: 20, context: "orientation"
        ))
    }

    func testOpaqueAlphaNormalizationRejectsTransparencyAndProducesAlphaFreePNG() throws {
        let opaqueAlpha = try png(
            width: 10,
            height: 20,
            hasAlpha: true,
            alphaByte: 255
        )
        XCTAssertTrue(try ImageValidation.decodePNG(
            opaqueAlpha,
            context: "opaque alpha input"
        ).hasAlpha)

        let normalized = try ImageValidation.removingOpaqueAlphaChannel(
            from: opaqueAlpha,
            context: "opaque alpha input"
        )
        let decoded = try ImageValidation.validateScreenshot(
            normalized,
            pixelWidth: 10,
            pixelHeight: 20,
            context: "normalized opaque alpha"
        )
        XCTAssertFalse(decoded.hasAlpha)

        XCTAssertThrowsError(try ImageValidation.removingOpaqueAlphaChannel(
            from: png(width: 10, height: 20, hasAlpha: true, alphaByte: 128),
            context: "transparent input"
        ))
        let alphaFree = try png(width: 10, height: 20)
        XCTAssertEqual(
            try ImageValidation.removingOpaqueAlphaChannel(
                from: alphaFree,
                context: "already alpha free"
            ),
            alphaFree
        )
    }

    private func writeSingleLocaleConfig(to url: URL) throws {
        try FileIO.writeJSONValue(.object([
            "bundleId": .string("com.example.App"),
            "localizations": .array([.object([
                "appStoreLocale": .string("en-US"),
                "screenshotConfiguration": .string("en-US"),
            ])]),
        ]), to: url)
    }

    private func makeAPIClient(
        baseURL: URL = URL(string: "https://example.test")!,
        transport: HTTPTransport,
        maxRetries: Int
    ) -> ASCAPIClient {
        ASCAPIClient(
            credentials: ASCCredentials(
                keyId: "KEY",
                issuerId: "00000000-0000-0000-0000-000000000000",
                privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation
            ),
            baseURL: baseURL,
            transport: transport,
            maxRetries: maxRetries
        )
    }

    private func png(
        width: Int,
        height: Int,
        hasAlpha: Bool = false,
        alphaByte: UInt8 = 0x80,
        orientation: Int = 1
    ) throws -> Data {
        var bytes = [UInt8](repeating: 0x80, count: width * height * 4)
        if hasAlpha {
            for index in stride(from: 3, to: bytes.count, by: 4) {
                bytes[index] = alphaByte
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: (
                    hasAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
                ).rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw ReleaseToolError.file("Could not create test image") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw ReleaseToolError.file("Could not create PNG destination") }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: orientation,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ReleaseToolError.file("Could not encode test PNG")
        }
        return output as Data
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASCReleaseCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let handler: (URLRequest) throws -> TransportResponse
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    init(handler: @escaping (URLRequest) throws -> TransportResponse) { self.handler = handler }

    func send(_ request: URLRequest) throws -> TransportResponse {
        lock.lock(); requests.append(request); lock.unlock()
        return try handler(request)
    }
}

private extension TransportResponse {
    static func json(_ statusCode: Int, _ string: String) -> TransportResponse {
        TransportResponse(
            data: Data(string.utf8), statusCode: statusCode,
            headers: ["content-type": "application/json"]
        )
    }
}
