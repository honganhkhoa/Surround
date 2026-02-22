//
//  SurroundService.swift
//  Surround
//
//  Created by Anh Khoa Hong on 10/28/20.
//

import Foundation
import Alamofire
import Combine
import StoreKit

enum SurroundServiceError: Error {
    case notLoggedIn
    case failedVerification
}

struct SupporterProduct: Identifiable {
    let id: String
    let displayPrice: String
}

class SurroundService: NSObject, ObservableObject {
    static var shared = SurroundService()
    
//    static let sgsRoot = "http://192.168.1.118:8000"
    static let sgsRoot = "https://surround.honganhkhoa.com"
    
    private var sgsRoot = SurroundService.sgsRoot
    private var transactionUpdatesTask: Task<Void, Never>?
    private var storeProductsById = [String: Product]()
    
    private override init() {
        super.init()
        transactionUpdatesTask = observeTransactionUpdates()
    }
    
    func isProductionEnvironment() -> Bool {
        if let provisionPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
            if let provisionData = try? Data(contentsOf: URL(fileURLWithPath: provisionPath)) {
                if let provisionString = String(data: provisionData, encoding: .ascii) {
                    let noBlankProvisionString = provisionString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\t", with: "")
//                    print(noBlankProvisionString)
                    return !noBlankProvisionString.contains("<key>aps-environment</key><string>development</string>")
                }
            }
        }
        return true
    }
    
    func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifierData = Mirror(reflecting: systemInfo.machine).children
        let identifierUnicodes: [UnicodeScalar] = identifierData.compactMap {
            guard let value = $0.value as? Int8, value > 0 else {
                return nil
            }
            let unicode = UnicodeScalar(UInt8(value))
            return unicode.isASCII ? unicode : nil
        }
        return String(String.UnicodeScalarView(identifierUnicodes))
    }
    
    func getPushSettingsString() -> String {
        let pushSettingsKey: [SettingKey<Bool>] = [
            .notificationOnUserTurn,
            .notificationOnTimeRunningOut,
            .notificationOnNewGame,
            .notiticationOnGameEnd,
            .notificationOnChallengeReceived
        ]
        var pushSettings = [String: Bool]()
        for settingKey in pushSettingsKey {
            pushSettings[settingKey.mainName] = userDefaults[settingKey]
        }
        if let pushSettingsData = try? JSONSerialization.data(withJSONObject: pushSettings) {
            return String(data: pushSettingsData, encoding: .utf8) ?? ""
        }
        return ""
    }
    
    func registerDeviceIfLoggedIn(pushToken: Data) {
        if let uiconfig = userDefaults[.ogsUIConfig],
           let ogsSessionId = userDefaults[.ogsSessionId],
           let ogsCsrfToken = uiconfig.csrfToken {
            let ogsUserId = uiconfig.user.id
            let ogsUsername = uiconfig.user.username
            var headers = HTTPHeaders()
            if let accessToken = userDefaults[.sgsAccessToken] {
                headers = [.authorization(accessToken)]
            }
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-1"
            let pushSettings = getPushSettingsString()
            var parameters: Parameters = [
                "ogsUserId": ogsUserId,
                "ogsUsername": ogsUsername,
                "ogsCsrfToken": ogsCsrfToken,
                "ogsSessionId": ogsSessionId,
                "pushToken": pushToken.map { String(format: "%02hhx", $0) }.joined(),
                "production": isProductionEnvironment(),
                "version": version,
                "pushSettings": pushSettings,
                "deviceModelIdentifier": self.deviceModelIdentifier()
            ]
            if let receiptData = self.receiptData() {
                if userDefaults[.lastSentReceiptData] != receiptData {
                    parameters["receiptData"] = receiptData
                }
            }
            if let ogsCsrfCookie = userDefaults[.ogsCsrfCookie] {
                parameters["ogsCsrfCookie"] = ogsCsrfCookie
            }
            Task {
                var parametersWithStoreKit2Data = parameters
                if let renewalInfo = await self.supporterRenewalInfoJSONString() {
                    parametersWithStoreKit2Data["renewalInfo"] = renewalInfo
                }
                AF.request(
                    "\(self.sgsRoot)/register",
                    method: .post,
                    parameters: parametersWithStoreKit2Data,
                    headers: headers
                ).validate().responseJSON { response in
                    switch response.result {
                    case .success:
                        if let responseData = response.value as? [String: Any] {
                            if let accessToken = responseData["accessToken"] as? String {
                                userDefaults[.sgsAccessToken] = accessToken
                                if let receiptData = parametersWithStoreKit2Data["receiptData"] as? String {
                                    userDefaults[.lastSentReceiptData] = receiptData
                                }
                            }
                            if let supporterExpiryTimestamp = responseData["supporterExpires"] as? Double {
                                userDefaults[.supporterProductExpiryDate] = Date(timeIntervalSince1970: supporterExpiryTimestamp)
                            }
                        }
                    case .failure(let error):
                        print(error)
                    }
                }
            }
        }
    }
    
    func unregisterDevice() {
        if let accessToken = userDefaults[.sgsAccessToken] {
            AF.request(
                "\(self.sgsRoot)/unregister",
                method: .post,
                headers: [.authorization(accessToken)]
            ).validate().responseJSON(completionHandler: { _ in
                
            })
        }
    }
    
    func setPushEnabled(enabled: Bool) {
        if let accessToken = userDefaults[.sgsAccessToken] {
            AF.request(
                "\(self.sgsRoot)/enable_push",
                method: .post,
                parameters: [
                    "enabled": enabled
                ],
                headers: [.authorization(accessToken)]
            ).validate().responseJSON(completionHandler: { _ in
                
            })
        }
    }
    
    func getOGSOverview(allowsCache: Bool = false) -> AnyPublisher<[String: Any], Error> {
        return Future<[String: Any], Error> { promise in
            if let accessToken = userDefaults[.sgsAccessToken] {
                AF.request(
                    "\(self.sgsRoot)/ogs_overview",
                    parameters: ["allows_cache": allowsCache],
                    headers: [.authorization(accessToken)]
                ).validate().responseData(completionHandler: { response in
                    if case .failure(let error) = response.result {
                        promise(.failure(error))
                        return
                    }
                    if let responseValue = response.value, let json = try? JSONSerialization.jsonObject(with: responseValue) as? [String: Any] {
                        
                        promise(.success(json))
                    } else {
                        promise(.failure(OGSServiceError.invalidJSON))
                    }
                })
            } else {
                promise(.failure(SurroundServiceError.notLoggedIn))
            }
        }.eraseToAnyPublisher()
    }
    
    // - Subscriptions
    private var supporterProductIds = Set([1, 2, 3, 4].map { "com.honganhkhoa.Surround.SurroundSupporter\($0)" })
    @Published private(set) var supporterProducts: [SupporterProduct] = []
    @Published private(set) var fetchingProducts = false
    @Published private(set) var fetchError: Error?
    @Published private(set) var processingProductIds = Set<String>()
    @Published private(set) var processingTransaction = false

    var supporterProductId: String? {
        guard let productId = userDefaults[.supporterProductId] else {
            return nil
        }
        
        if let expiryDate = userDefaults[.supporterProductExpiryDate] {
            if expiryDate < Date() {
                return nil
            }
        }
        
        return productId
    }
    
    func fetchProducts() {
        fetchingProducts = true
        fetchError = nil
        Task {
            do {
                let products = try await Product.products(for: supporterProductIds)
                let sortedProducts = products.sorted { $0.price < $1.price }
                let productsById = Dictionary(uniqueKeysWithValues: sortedProducts.map { ($0.id, $0) })
                let productsForDisplay = sortedProducts.map {
                    SupporterProduct(id: $0.id, displayPrice: $0.displayPrice)
                }
                await MainActor.run {
                    self.storeProductsById = productsById
                    self.supporterProducts = productsForDisplay
                    self.fetchingProducts = false
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error
                    self.fetchingProducts = false
                }
            }
        }
    }
    
    func initializeProductsForPreview() {
        supporterProducts = [
            SupporterProduct(id: "com.honganhkhoa.Surround.SurroundSupporter1", displayPrice: "$0.49"),
            SupporterProduct(id: "com.honganhkhoa.Surround.SurroundSupporter2", displayPrice: "$1.99"),
            SupporterProduct(id: "com.honganhkhoa.Surround.SurroundSupporter3", displayPrice: "$4.99"),
            SupporterProduct(id: "com.honganhkhoa.Surround.SurroundSupporter4", displayPrice: "$9.99")
        ]
    }

    func subscribe(to product: SupporterProduct) {
        guard let storeProduct = storeProductsById[product.id] else {
            return
        }
        processingTransaction = true
        processingProductIds.insert(product.id)
        Task {
            do {
                let result = try await storeProduct.purchase()
                switch result {
                case .success(let verificationResult):
                    let transaction = try self.verify(verificationResult)
                    await MainActor.run {
                        self.updateSupporterState(with: transaction)
                        self.processingProductIds.remove(transaction.productID)
                        self.processingTransaction = false
                    }
                    await transaction.finish()
                case .pending:
                    break
                case .userCancelled:
                    await MainActor.run {
                        self.processingProductIds.remove(product.id)
                        self.processingTransaction = false
                    }
                @unknown default:
                    await MainActor.run {
                        self.processingProductIds.remove(product.id)
                        self.processingTransaction = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.processingProductIds.remove(product.id)
                    self.processingTransaction = false
                }
            }
        }
    }
    
    func restorePurchases() {
        processingTransaction = true
        Task {
            do {
                try await AppStore.sync()
                await refreshSupporterEntitlements()
            } catch {
                await MainActor.run {
                    self.processingTransaction = false
                }
            }
        }
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else {
                return
            }
            for await verificationResult in Transaction.updates {
                guard let transaction = try? self.verify(verificationResult) else {
                    continue
                }
                await MainActor.run {
                    self.updateSupporterState(with: transaction)
                    self.processingProductIds.remove(transaction.productID)
                    self.processingTransaction = false
                }
                await transaction.finish()
            }
        }
    }
    
    private func refreshSupporterEntitlements() async {
        var latestSupporterTransaction: Transaction?
        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? verify(verificationResult) else {
                continue
            }
            guard supporterProductIds.contains(transaction.productID) else {
                continue
            }
            if latestSupporterTransaction == nil || transaction.purchaseDate > latestSupporterTransaction!.purchaseDate {
                latestSupporterTransaction = transaction
            }
        }
        let latestTransaction = latestSupporterTransaction
        await MainActor.run {
            if let transaction = latestTransaction {
                self.updateSupporterState(with: transaction)
            } else {
                userDefaults[.supporterProductId] = nil
                userDefaults[.supporterProductExpiryDate] = nil
            }
            self.processingProductIds.removeAll()
            self.processingTransaction = false
        }
    }
    
    func receiptData() -> String? {
        if #unavailable(iOS 18.0) {
            if let receiptURL = Bundle.main.appStoreReceiptURL,
               FileManager.default.fileExists(atPath: receiptURL.path) {
                let receiptData = try? Data(contentsOf: receiptURL, options: .alwaysMapped)
                return receiptData?.base64EncodedString(options: [])
            }
        }
        return nil
    }
    
    private func supporterRenewalInfoJSONString() async -> String? {
        var renewalInfoObjects = [[String: Any]]()
        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? verify(verificationResult) else {
                continue
            }
            guard supporterProductIds.contains(transaction.productID) else {
                continue
            }
            guard let status = await transaction.subscriptionStatus else {
                continue
            }
            guard let renewalInfo = try? verify(status.renewalInfo) else {
                continue
            }
            guard var renewalInfoObject = try? JSONSerialization.jsonObject(with: renewalInfo.jsonRepresentation) as? [String: Any] else {
                continue
            }
            renewalInfoObject["renewalState"] = String(describing: status.state)
            renewalInfoObjects.append(renewalInfoObject)
        }
        guard renewalInfoObjects.count > 0 else {
            return nil
        }
        if let data = try? JSONSerialization.data(withJSONObject: renewalInfoObjects) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func verify<T>(_ verificationResult: VerificationResult<T>) throws -> T {
        switch verificationResult {
        case .verified(let value):
            return value
        case .unverified:
            throw SurroundServiceError.failedVerification
        }
    }
    
    @MainActor
    private func updateSupporterState(with transaction: Transaction) {
        userDefaults[.supporterProductId] = transaction.productID
        userDefaults[.supporterProductExpiryDate] = transaction.expirationDate
    }
}
