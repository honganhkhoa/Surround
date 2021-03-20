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
}

class SurroundService: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    static var shared = SurroundService()
    
//    static let sgsRoot = "http://192.168.1.16:8000"
    static let sgsRoot = "https://surround.honganhkhoa.com"
    
    private var sgsRoot = SurroundService.sgsRoot
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
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
            AF.request(
                "\(self.sgsRoot)/register",
                method: .post,
                parameters: parameters,
                headers: headers
            ).validate().responseJSON { response in
                switch response.result {
                case .success:
                    if let responseData = response.value as? [String: Any] {
                        if let accessToken = responseData["accessToken"] as? String {
                            userDefaults[.sgsAccessToken] = accessToken
                            if let receiptData = parameters["receiptData"] as? String {
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
    private var productsRequest: SKProductsRequest?
    @Published private(set) var supporterProducts: [SKProduct] = []
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
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.supporterProducts = response.products.sorted(by: { $0.price.compare($1.price) == .orderedAscending })
            self.fetchingProducts = false
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.fetchError = error
            self.fetchingProducts = false
        }
    }
    
    func fetchProducts() {
        fetchingProducts = true
        productsRequest = SKProductsRequest(productIdentifiers: supporterProductIds)
        productsRequest?.delegate = self
        productsRequest?.start()
    }
    
    func initializeProductsForPreview() {
        supporterProducts = []
        for (index, price) in ["0.49", "1.99", "4.99", "9.99"].enumerated() {
            let product = MockSKProduct(price: Decimal(string: price)!, index: index)
            supporterProducts.append(product)
        }
    }

    func subscribe(to product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
        processingTransaction = true
        processingProductIds.insert(product.productIdentifier)
    }
    
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
        processingTransaction = true
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        processingTransaction = false
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        processingTransaction = false
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        var restoredTransactions = [SKPaymentTransaction]()
        for transaction in transactions {
            let productId = transaction.payment.productIdentifier
            print("\(productId): \(transaction.transactionState)")
            switch transaction.transactionState {
            case .purchased:
                userDefaults[.supporterProductId] = productId
                userDefaults[.supporterProductExpiryDate] = nil
                processingProductIds.remove(productId)
                SKPaymentQueue.default().finishTransaction(transaction)
                processingTransaction = false
            case .purchasing:
                processingProductIds.insert(transaction.payment.productIdentifier)
            case .restored:
                restoredTransactions.append(transaction)
            case .failed:
                if userDefaults[.supporterProductId] == productId {
                    userDefaults[.supporterProductId] = nil
                }
                processingProductIds.remove(productId)
                SKPaymentQueue.default().finishTransaction(transaction)
                processingTransaction = false
            case .deferred:
                processingProductIds.insert(transaction.payment.productIdentifier)
            @unknown default:
                break
            }
        }
        if restoredTransactions.count > 0 {
            restoredTransactions.sort(by: { $0.transactionDate ?? Date.distantPast < $1.transactionDate ?? Date.distantPast })
            if let lastTransaction = restoredTransactions.last {
                userDefaults[.supporterProductId] = lastTransaction.payment.productIdentifier
                userDefaults[.supporterProductExpiryDate] = nil
            }
            for transaction in restoredTransactions {
                SKPaymentQueue.default().finishTransaction(transaction)
            }
            processingTransaction = false
        }
    }
    
    func receiptData() -> String? {
        if let receiptURL = Bundle.main.appStoreReceiptURL, FileManager.default.fileExists(atPath: receiptURL.path) {
            do {
                let receiptData = try Data(contentsOf: receiptURL, options: .alwaysMapped)
                let receiptString = receiptData.base64EncodedString(options: [])
                return receiptString
            } catch {
                return nil
            }
        }
        return nil
    }
}

class MonthlySubscriptionPeriod: SKProductSubscriptionPeriod {
    private let _numberOfUnits: Int
    private let _unit: SKProduct.PeriodUnit

    override init() {
        _numberOfUnits = 1
        _unit = .year
    }

    override var numberOfUnits: Int {
        self._numberOfUnits
    }

    override var unit: SKProduct.PeriodUnit {
        self._unit
    }
}

class MockSKProduct: SKProduct {
    private var _subscriptionPeriod: SKProductSubscriptionPeriod

    init(price: Decimal, index: Int) {
        _subscriptionPeriod = MonthlySubscriptionPeriod()
        super.init()
        self.setValue(price, forKey: "price")
        self.setValue("com.honganhkhoa.Surround.SurroundSupporter\(index + 1)", forKey: "productIdentifier")
        self.setValue(Locale(identifier: "en_US"), forKey: "priceLocale")
    }

    override var subscriptionPeriod: SKProductSubscriptionPeriod? {
        get {
            _subscriptionPeriod
        }
    }
}
