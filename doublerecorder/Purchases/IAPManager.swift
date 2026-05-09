import StoreKit
import Foundation

final class IAPManager: NSObject {

    static let shared = IAPManager()

    static let productID = "lifetime_unlock_duo_video"

    private(set) var product: SKProduct?
    private var productsRequest: SKProductsRequest?

    /// 购买完成/恢复完成后在主线程回调
    var onPurchaseSuccess: (() -> Void)?
    /// 购买/恢复失败时在主线程回调（nil = 用户取消）
    var onPurchaseFailed:  ((Error?) -> Void)?
    /// 恢复完成但未找到该产品时回调
    var onRestoreNotFound: (() -> Void)?

    private(set) var priceString: String?

    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        fetchProduct()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    // MARK: - Fetch Product

    func fetchProduct() {
        let request = SKProductsRequest(productIdentifiers: [Self.productID])
        request.delegate = self
        productsRequest = request
        request.start()
    }

    // MARK: - Purchase

    func purchase() {
        guard SKPaymentQueue.canMakePayments() else {
            onPurchaseFailed?(NSError(domain: "IAPManager", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "设备不允许内购"]))
            return
        }
        guard let product else {
            // 还未获取到产品，先 fetch 再购买
            fetchProduct()
            // 保存购买意图，fetchProduct 成功后自动触发
            pendingPurchase = true
            return
        }
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    private var pendingPurchase = false

    // MARK: - Restore (非消耗型用 restoreCompletedTransactions)

    func restore() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

// MARK: - SKProductsRequestDelegate

extension IAPManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest,
                         didReceive response: SKProductsResponse) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.product = response.products.first
            if let p = self.product {
                let fmt = NumberFormatter()
                fmt.numberStyle = .currency
                fmt.locale = p.priceLocale
                self.priceString = fmt.string(from: p.price)
                NotificationCenter.default.post(name: .iapProductLoaded, object: nil)
            }
            if self.pendingPurchase, let product = self.product {
                self.pendingPurchase = false
                let payment = SKPayment(product: product)
                SKPaymentQueue.default().add(payment)
            }
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.pendingPurchase = false
        }
    }
}

// MARK: - SKPaymentTransactionObserver

extension IAPManager: SKPaymentTransactionObserver {

    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                unlockPro()
                queue.finishTransaction(transaction)
            case .restored:
                if transaction.original?.payment.productIdentifier == Self.productID {
                    unlockPro()
                }
                queue.finishTransaction(transaction)
            case .failed:
                queue.finishTransaction(transaction)
                let err = transaction.error
                // SKError.paymentCancelled (code 2) → 用户主动取消，不算错误
                let isCancelled = (err as? SKError)?.code == .paymentCancelled
                DispatchQueue.main.async { [weak self] in
                    self?.onPurchaseFailed?(isCancelled ? nil : err)
                }
            case .purchasing, .deferred:
                break
            @unknown default:
                break
            }
        }
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // 恢复完成时检查是否真的解锁了
        if !AppSettings.shared.isProUser {
            DispatchQueue.main.async { [weak self] in
                self?.onRestoreNotFound?()
            }
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onPurchaseFailed?(error)
        }
    }

    private func unlockPro() {
        AppSettings.shared.isProUser = true
        // 同时清除钥匙串计数（解锁后不再限制）
        KeychainHelper.shared.resetRecordingCount()
        DispatchQueue.main.async { [weak self] in
            self?.onPurchaseSuccess?()
        }
    }
}
