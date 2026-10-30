// Opt-in credential transport for local Beta simulator testing.
// No credential is accepted through launch arguments, environment, or plaintext files.
#if (DEBUG && OGS_BETA && MAIN_APP && targetEnvironment(simulator)) || BETA_SIMULATOR_LOGIN_BRIDGE_TESTS
import Foundation
import CryptoKit
import Darwin

enum BetaSimulatorLoginContract {
    static let bundleID = "com.honganhkhoa.Surround.Beta"
    static let origin = "https://beta.online-go.com"
    static let sharedInfo = Data("surround-beta-simulator-login-v1".utf8)
    static let maximumPasswordBytes = 4_096
    // Allow JSON escaping, encryption and base64 overhead for every valid password.
    static let maximumRequestBytes = 128 * 1_024

    struct Launch {
        let runID: String
        let username: String
        let probe: Bool
        let replaceAccount: Bool
    }

    static func launch(arguments: [String], bundleID: String?, origin: String,
                       socketOrigin: String, offline: Bool) -> Launch? {
        guard bundleID == self.bundleID, origin == self.origin,
              socketOrigin == "wss://beta.online-go.com", !offline,
              arguments.filter({ $0 == "--surround-beta-login-bridge" }).count == 1,
              arguments.filter({ $0 == "--surround-beta-login-account" }).count == 1,
              let runIndex = arguments.firstIndex(of: "--surround-beta-login-bridge"),
              arguments.indices.contains(runIndex + 1),
              let uuid = UUID(uuidString: arguments[runIndex + 1]),
              let accountIndex = arguments.firstIndex(of: "--surround-beta-login-account"),
              arguments.indices.contains(accountIndex + 1) else { return nil }
        let username = arguments[accountIndex + 1]
        guard username.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$",
                             options: .regularExpression) != nil else { return nil }
        return Launch(runID: uuid.uuidString, username: username,
                      probe: arguments.contains("--surround-beta-login-probe"),
                      replaceAccount: arguments.contains("--surround-beta-login-replace-account"))
    }

    struct Request: Codable {
        let version: Int
        let publicKey: String
        let ciphertext: String
    }

    struct Credentials: Codable {
        let username: String
        let password: String
    }

    enum InvalidRequest: Error { case invalid }

    static func decrypt(_ data: Data, key: Curve25519.KeyAgreement.PrivateKey,
                        runID: String, username: String) throws -> Credentials {
        guard data.count <= maximumRequestBytes else { throw InvalidRequest.invalid }
        let request = try JSONDecoder().decode(Request.self, from: data)
        guard request.version == 1,
              let publicData = Data(base64Encoded: request.publicKey),
              let ciphertext = Data(base64Encoded: request.ciphertext) else {
            throw InvalidRequest.invalid
        }
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicData)
        let shared = try key.sharedSecretFromKeyAgreement(with: publicKey)
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(runID.utf8), sharedInfo: sharedInfo,
            outputByteCount: 32)
        var plaintext = try AES.GCM.open(
            AES.GCM.SealedBox(combined: ciphertext), using: symmetricKey,
            authenticating: Data("\(runID):\(username)".utf8))
        defer { plaintext.resetBytes(in: plaintext.indices) }
        let credentials = try JSONDecoder().decode(Credentials.self, from: plaintext)
        guard credentials.username == username, !credentials.password.isEmpty,
              credentials.password.utf8.count <= maximumPasswordBytes else { throw InvalidRequest.invalid }
        return credentials
    }
}

#if DEBUG && OGS_BETA && MAIN_APP && targetEnvironment(simulator)
import Combine

/// A single process accepts one encrypted request, then closes. This never runs
/// in offline fixtures, production builds, devices, Catalyst, or Release builds.
final class BetaSimulatorLoginBridge {
    private static var started = false
    private static var active: BetaSimulatorLoginBridge?

    static func startIfRequested(service: OGSService) {
        guard !started, service.acceptsBetaSimulatorLoginCredentials,
              let launch = BetaSimulatorLoginContract.launch(
            arguments: ProcessInfo.processInfo.arguments,
            bundleID: Bundle.main.bundleIdentifier,
            origin: OGSEnvironment.current.rootURL.absoluteString,
            socketOrigin: OGSEnvironment.current.websocketURL.absoluteString,
            offline: SurroundUITestContract.isEnabled) else { return }
        started = true
        let bridge = BetaSimulatorLoginBridge(service: service, launch: launch)
        active = bridge
        bridge.start()
    }

    private struct Ready: Encodable {
        let version = 1
        let origin = BetaSimulatorLoginContract.origin
        let bundleID = BetaSimulatorLoginContract.bundleID
        let runID: String
        let username: String
        let publicKey: String
        let expiresAt: Double
    }

    private struct Outcome: Encodable {
        let version = 1
        let runID: String
        let username: String
        let status: String
        let httpAuthenticated: Bool
        let webSocketAuthenticated: Bool
        let persistedSession: Bool
    }

    private let service: OGSService
    private let launch: BetaSimulatorLoginContract.Launch
    private let directory: URL
    private var key: Curve25519.KeyAgreement.PrivateKey?
    private var subscription: AnyCancellable?
    private var finished = false
    private var httpAuthenticated = false
    private var socketCheckStarted = false
    private var ownsDirectory = false
    private let deadline = ProcessInfo.processInfo.systemUptime + 90

    private init(service: OGSService, launch: BetaSimulatorLoginContract.Launch) {
        self.service = service
        self.launch = launch
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("surround-beta-login-bridge", isDirectory: true)
            .appendingPathComponent(launch.runID, isDirectory: true)
    }

    private func start() {
        do {
            let parent = directory.deletingLastPathComponent()
            guard mkdir(parent.path, 0o700) == 0 || errno == EEXIST else {
                return finish("failed")
            }
            var info = stat()
            guard lstat(parent.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                  info.st_uid == getuid(), (info.st_mode & 0o077) == 0,
                  mkdir(directory.path, 0o700) == 0 else {
                return finish("failed")
            }
            ownsDirectory = true
            key = Curve25519.KeyAgreement.PrivateKey()
            try write(Ready(runID: launch.runID, username: launch.username,
                            publicKey: key!.publicKey.rawRepresentation.base64EncodedString(),
                            expiresAt: Date().timeIntervalSince1970 + 90), name: "ready.json")
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
                self?.finish("timeout")
            }
            if launch.probe {
                verifyHTTP()
            } else if service.isLoggedIn,
                      service.user?.username != launch.username, !launch.replaceAccount {
                finish("rejected")
            } else {
                pollRequest()
            }
        } catch { finish("failed") }
    }

    private func pollRequest() {
        guard !finished else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return finish("timeout") }
        let requestURL = directory.appendingPathComponent("request.json")
        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.pollRequest() }
            return
        }
        do {
            guard let key else { return finish("rejected") }
            let data = try readRequest(requestURL)
            try FileManager.default.removeItem(at: requestURL)
            let credentials = try BetaSimulatorLoginContract.decrypt(
                data, key: key, runID: launch.runID, username: launch.username)
            self.key = nil
            subscription = service.login(username: credentials.username, password: credentials.password)
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure = completion { self?.finish("rejected") }
                }, receiveValue: { [weak self] config in
                    guard let self, !finished else { return }
                    guard config.user.username == launch.username, config.user.anonymous == false else {
                        service.logout()
                        return finish("rejected")
                    }
                    // Avoid cancelling the login publisher inside its own receiveValue.
                    DispatchQueue.main.async { [weak self] in self?.verifyHTTP() }
                })
        } catch { finish("rejected") }
    }

    private func verifyHTTP() {
        guard !finished else { return }
        subscription = service.fetchUIConfig()
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure = completion { self?.finish("failed") }
            }, receiveValue: { [weak self] config in
                guard let self, !finished else { return }
                guard config.user.username == launch.username, config.user.anonymous == false,
                      service.isLoggedIn, service.user?.id == config.user.id else {
                    if !launch.probe { service.logout() }
                    return finish("rejected")
                }
                httpAuthenticated = true
                waitForSocket()
            })
    }

    private func waitForSocket() {
        guard !finished, !socketCheckStarted else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return finish("timeout") }
        guard service.socketStatus == .connected, service.isWebsocketAuthenticated else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.waitForSocket() }
            return
        }
        socketCheckStarted = true
        service.verifyBetaSimulatorSocketIdentity(username: launch.username) { [weak self] verified in
            DispatchQueue.main.async {
                self?.finish(verified ? "authenticated" : "failed", socketAuthenticated: verified)
            }
        }
    }

    private func finish(_ status: String, socketAuthenticated: Bool = false) {
        guard !finished else { return }
        finished = true
        subscription?.cancel()
        subscription = nil
        key = nil
        let persisted = service.preferences[.ogsSessionId] != nil
            && service.preferences[.ogsUIConfig]?.user.username == launch.username
        if ownsDirectory {
            for name in ["request.json", "ready.json"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            try? write(Outcome(runID: launch.runID, username: launch.username, status: status,
                               httpAuthenticated: httpAuthenticated,
                               webSocketAuthenticated: socketAuthenticated,
                               persistedSession: persisted), name: "result.json")
        }
        Self.active = nil
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        let url = directory.appendingPathComponent(name)
        let staging = directory.appendingPathComponent("\(name).\(UUID().uuidString).tmp")
        let descriptor = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw BetaSimulatorLoginContract.InvalidRequest.invalid }
        defer { close(descriptor); try? FileManager.default.removeItem(at: staging) }
        try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(descriptor) == 0, rename(staging.path, url.path) == 0 else {
            throw BetaSimulatorLoginContract.InvalidRequest.invalid
        }
    }

    private func readRequest(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw BetaSimulatorLoginContract.InvalidRequest.invalid }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0,
              info.st_size > 0, info.st_size <= BetaSimulatorLoginContract.maximumRequestBytes else {
            throw BetaSimulatorLoginContract.InvalidRequest.invalid
        }
        let data = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readDataToEndOfFile()
        guard data.count == Int(info.st_size) else { throw BetaSimulatorLoginContract.InvalidRequest.invalid }
        return data
    }
}
#endif
#endif
