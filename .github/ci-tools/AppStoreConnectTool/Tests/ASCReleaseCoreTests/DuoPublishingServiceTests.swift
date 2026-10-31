import CryptoKit
import Foundation
import XCTest
@testable import ASCReleaseCore

final class DuoPublishingServiceTests: XCTestCase {
    func testEditableContextUsesForwardOwnershipPathsAndRejectsWrongResources() throws {
        let set = DuoPublishSet(version: "3.0", bundleID: "com.example.App", appID: "app", assetLibraryID: "library",
            versionID: "version", localizationID: "locale", locale: "en-US", sourceManifestSHA256: String(repeating: "a", count: 64),
            catalog: [], images: [], reviewedBaseline: [])
        for fault in ["none", "app-id", "library-type", "released-target", "locale"] {
            let transport = DuoServiceTransport { request in
                XCTAssertEqual(request.httpMethod, "GET")
                let response: JSONValue
                switch request.url!.path {
                case "/v1/apps/app": response = .object(["data": .object(["type": .string("apps"),
                    "id": .string(fault == "app-id" ? "other" : "app"), "attributes": .object(["bundleId": .string("com.example.App")])])])
                case "/v1/apps/app/assetLibrary": response = .object(["data": .object([
                    "type": .string(fault == "library-type" ? "other" : "appAssetLibraries"), "id": .string("library")])])
                case "/v1/apps/app/appStoreVersions": response = .object(["data": .array([.object([
                    "type": .string("appStoreVersions"), "id": .string("version"), "attributes": .object([
                        "versionString": .string("3.0"), "platform": .string("IOS"),
                        "appVersionState": .string(fault == "released-target" ? "READY_FOR_DISTRIBUTION" : "PREPARE_FOR_SUBMISSION")])])])])
                case "/v1/appStoreVersions/version/appStoreVersionLocalizations": response = .object(["data": .array([.object([
                    "type": .string("appStoreVersionLocalizations"), "id": .string("locale"),
                    "attributes": .object(["locale": .string(fault == "locale" ? "fr-FR" : "en-US")])])])])
                default: throw DuoExecutionFailure.drift("Undocumented reverse ownership path")
                }
                return TransportResponse(data: try JSONEncoder().encode(response), statusCode: 200)
            }
            let service = ASCDuoPublishingService(client: client(transport))
            if fault == "none" { try service.verifyEditableTarget(set); XCTAssertEqual(transport.count, 4) }
            else { XCTAssertThrowsError(try service.verifyEditableTarget(set)) }
        }
    }

    func testMutationHTTPRejectionAndAmbiguityAreSingleAttempt() throws {
        for status in [400, 408, 429, 500] {
            let transport = DuoServiceTransport { _ in TransportResponse(data: Data(), statusCode: status) }
            let service = ASCDuoPublishingService(client: client(transport))
            let request = DuoAssetLibraryRequest(method: "PATCH", path: "/v1/appAssetLibraryImages/image", body: .object([
                "data": .object(["type": .string("appAssetLibraryImages"), "id": .string("image"), "attributes": .object(["uploaded": .bool(true)])])]))
            XCTAssertThrowsError(try service.send(request)) { error in
                if status == 400 {
                    guard case DuoExecutionFailure.rejected = error else { return XCTFail("\(error)") }
                } else {
                    guard case DuoExecutionFailure.uncertain = error else { return XCTFail("\(error)") }
                }
            }
            XCTAssertEqual(transport.count, 1)
        }
    }

    func testSingleAttemptUploadKeepsExactBytesAndNoJWT() throws {
        let data = Data([1, 2, 3, 4])
        let transport = DuoServiceTransport { request in
            XCTAssertEqual(request.httpBody, Data([2, 3]))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return TransportResponse(data: Data(), statusCode: 500)
        }
        let service = ASCDuoPublishingService(client: client(transport))
        let operation = UploadOperation(method: "PUT", url: "https://upload.example/chunk", offset: 1, length: 2, requestHeaders: [])
        XCTAssertThrowsError(try service.upload(operation, bytes: data))
        XCTAssertEqual(transport.count, 1)
    }

    func testServiceRefusesArchiveDeleteAndMismatchedCommitWithoutHTTP() throws {
        let transport = DuoServiceTransport { _ in XCTFail("Forbidden mutation reached transport"); return TransportResponse(data: Data(), statusCode: 500) }
        let service = ASCDuoPublishingService(client: client(transport))
        let bodies: [JSONValue] = [
            .object(["data": .object(["type": .string("appAssetLibraryImages"), "id": .string("image"), "attributes": .object(["archived": .bool(true)])])]),
            .object(["data": .object(["type": .string("appAssetLibraryImages"), "id": .string("different"), "attributes": .object(["uploaded": .bool(true)])])]),
            .object(["data": .object(["type": .string("appAssetLibraryImages"), "id": .string("image"), "attributes": .object(["uploaded": .bool(true), "sourceFileChecksum": .string("legacy")])])])]
        for body in bodies { XCTAssertThrowsError(try service.send(DuoAssetLibraryRequest(method: "PATCH", path: "/v1/appAssetLibraryImages/image", body: body))) }
        for path in ["/v1/appAssetLibraryImages/image", "/v1/appAssetLibraryPlacements/..", "/v1//appAssetLibraryPlacements/image"] {
            XCTAssertThrowsError(try service.send(DuoAssetLibraryRequest(method: "DELETE", path: path, body: .null)))
        }
        XCTAssertEqual(transport.count, 0)
    }

    func testImageReadRequiresExactRequestedResourceIdentity() throws {
        let transport = DuoServiceTransport { _ in
            let data = try JSONEncoder().encode(JSONValue.object(["data": .object(["type": .string("appAssetLibraryImages"), "id": .string("other")])]))
            return TransportResponse(data: data, statusCode: 200)
        }
        XCTAssertThrowsError(try ASCDuoPublishingService(client: client(transport)).image(id: "expected"))
        XCTAssertEqual(transport.count, 1)
    }

    func testPlacementReaderRequestsExplicitImageRelationship() throws {
        let transport = DuoServiceTransport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "include" }?.value, "image")
            let value: JSONValue = .object(["data": .array([])])
            return TransportResponse(data: try JSONEncoder().encode(value), statusCode: 200)
        }
        XCTAssertTrue(try ASCDuoPublishingService(client: client(transport)).placements(localizationID: "locale", group: "group").isEmpty)
        XCTAssertEqual(transport.count, 1)
    }

    private func client(_ transport: HTTPTransport) -> ASCAPIClient {
        ASCAPIClient(credentials: ASCCredentials(keyId: "unit", issuerId: "unit", privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation),
                     transport: transport, maxRetries: 4)
    }
}

private final class DuoServiceTransport: HTTPTransport, @unchecked Sendable {
    var count = 0
    let handler: (URLRequest) throws -> TransportResponse
    init(_ handler: @escaping (URLRequest) throws -> TransportResponse) { self.handler = handler }
    func send(_ request: URLRequest) throws -> TransportResponse { count += 1; return try handler(request) }
}
