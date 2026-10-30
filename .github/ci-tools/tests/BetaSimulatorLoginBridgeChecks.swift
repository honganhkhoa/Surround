// Standalone synthetic checks; never reads Keychain or contacts OGS.
import Foundation
import CryptoKit

@main
struct BetaSimulatorLoginBridgeChecks {
    static func main() throws {
        let runID = UUID().uuidString
        let arguments = ["app", "--surround-beta-login-bridge", runID,
                         "--surround-beta-login-account", "test-user"]
        func parse(_ arguments: [String], bundle: String = BetaSimulatorLoginContract.bundleID,
                   origin: String = BetaSimulatorLoginContract.origin,
                   socket: String = "wss://beta.online-go.com", offline: Bool = false) -> Bool {
            BetaSimulatorLoginContract.launch(arguments: arguments, bundleID: bundle,
                origin: origin, socketOrigin: socket, offline: offline) != nil
        }
        precondition(parse(arguments))
        precondition(!parse(arguments, bundle: "com.honganhkhoa.Surround"))
        precondition(!parse(arguments, origin: "https://online-go.com"))
        precondition(!parse(arguments, socket: "wss://online-go.com"))
        precondition(!parse(arguments, offline: true))
        precondition(!parse(arguments + ["--surround-beta-login-bridge", runID]))
        precondition(!parse(["--surround-beta-login-bridge", "../escape", "--surround-beta-login-account", "test-user"]))
        precondition(!parse(["--surround-beta-login-bridge", runID, "--surround-beta-login-account", "../escape"]))
        let maximumUsername = String(repeating: "u", count: 64)
        precondition(parse(["--surround-beta-login-bridge", runID,
                            "--surround-beta-login-account", maximumUsername]))
        precondition(!parse(["--surround-beta-login-bridge", runID,
                             "--surround-beta-login-account", maximumUsername + "u"]))

        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let key = try sender.sharedSecretFromKeyAgreement(with: recipient.publicKey)
            .hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(runID.utf8),
                sharedInfo: BetaSimulatorLoginContract.sharedInfo, outputByteCount: 32)
        func encrypt(username: String, password: String, version: Int = 1,
                     authenticatedUsername: String = "test-user") throws -> Data {
            let plaintext = try JSONEncoder().encode(BetaSimulatorLoginContract.Credentials(
                username: username, password: password))
            let box = try AES.GCM.seal(plaintext, using: key,
                authenticating: Data("\(runID):\(authenticatedUsername)".utf8))
            return try JSONEncoder().encode(BetaSimulatorLoginContract.Request(version: version,
                publicKey: sender.publicKey.rawRepresentation.base64EncodedString(),
                ciphertext: box.combined!.base64EncodedString()))
        }
        let request = try encrypt(username: "test-user", password: "SYNTHETIC_SECRET_CANARY")
        let credentials = try BetaSimulatorLoginContract.decrypt(request, key: recipient,
            runID: runID, username: "test-user")
        precondition(credentials.username == "test-user")
        precondition(credentials.password == "SYNTHETIC_SECRET_CANARY")
        precondition(!String(decoding: request, as: UTF8.self).contains("SYNTHETIC_SECRET_CANARY"))

        // Each NUL byte becomes six JSON bytes before encryption and base64.
        // This valid maximum-length password exceeded the former 32 KiB cap.
        let maximumPassword = String(repeating: "\u{0000}",
            count: BetaSimulatorLoginContract.maximumPasswordBytes)
        let maximumRequest = try encrypt(username: maximumUsername, password: maximumPassword,
                                         authenticatedUsername: maximumUsername)
        precondition(maximumRequest.count > 32_768)
        precondition(maximumRequest.count <= BetaSimulatorLoginContract.maximumRequestBytes)
        let maximumCredentials = try BetaSimulatorLoginContract.decrypt(maximumRequest, key: recipient,
            runID: runID, username: maximumUsername)
        precondition(maximumCredentials.username == maximumUsername)
        precondition(maximumCredentials.password == maximumPassword)

        func rejects(_ data: Data, run: String = runID, username: String = "test-user") {
            do {
                _ = try BetaSimulatorLoginContract.decrypt(data, key: recipient, runID: run, username: username)
                preconditionFailure("Invalid request accepted")
            } catch { }
        }
        rejects(request, run: UUID().uuidString)
        rejects(request, username: "different-user")
        rejects(try encrypt(username: "different-user", password: "synthetic"))
        rejects(try encrypt(username: "test-user", password: ""))
        rejects(try encrypt(username: "test-user", password: maximumPassword + "a"))
        rejects(try encrypt(username: "test-user", password: "synthetic", version: 2))

        // Keep the envelope valid so only the transport-size limit rejects it.
        var paddedRequest = request
        paddedRequest.append(Data(repeating: 0x20,
            count: BetaSimulatorLoginContract.maximumRequestBytes - request.count))
        let paddedCredentials = try BetaSimulatorLoginContract.decrypt(paddedRequest, key: recipient,
            runID: runID, username: "test-user")
        precondition(paddedCredentials.password == "SYNTHETIC_SECRET_CANARY")
        paddedRequest.append(0x20)
        _ = try JSONDecoder().decode(BetaSimulatorLoginContract.Request.self, from: paddedRequest)
        rejects(paddedRequest)
        rejects(Data("{}".utf8))
        print("Beta simulator login contract: synthetic guard and encryption checks passed")
    }
}
