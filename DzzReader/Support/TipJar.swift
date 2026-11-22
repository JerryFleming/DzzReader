import StoreKit
import SwiftUI

/// The four voluntary tips. Each is a consumable in-app purchase, so it can be given any number of
/// times and unlocks nothing. Prices are set in App Store Connect (and `DzzReader.storekit` for local
/// runs); `fallbackPrice` is only shown while the store hasn't answered.
enum Tip: String, CaseIterable, Identifiable {
    case small = "com.jerryfleming.dzzreader.tip.small"
    case coffee = "com.jerryfleming.dzzreader.tip.coffee"
    case support = "com.jerryfleming.dzzreader.tip.support"
    case generous = "com.jerryfleming.dzzreader.tip.generous"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "小小心意"
        case .coffee: "请杯咖啡"
        case .support: "支持一下"
        case .generous: "慷慨支持"
        }
    }

    var symbol: String {
        switch self {
        case .small: "leaf"
        case .coffee: "cup.and.saucer"
        case .support: "heart"
        case .generous: "sparkles"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .small: "£0.99"
        case .coffee: "£2.99"
        case .support: "£4.99"
        case .generous: "£9.99"
        }
    }
}

/// Loads the tip products and buys them. Tips are consumables: each finished transaction is simply
/// acknowledged, nothing is stored.
@Observable @MainActor
final class TipJar {
    enum Status: Equatable {
        case idle
        case purchasing(Tip)
        case thanked
        case failed(String)
    }

    private(set) var products: [Tip: Product] = [:]
    private(set) var loaded = false
    var status = Status.idle
    private var updates: Task<Void, Never>?

    init() {
        // Purchases that finish outside the app (Ask to Buy, interrupted payments) arrive here.
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
    }

    func load() async {
        guard !loaded else { return }
        do {
            let found = try await Product.products(for: Tip.allCases.map(\.rawValue))
            for product in found {
                if let tip = Tip(rawValue: product.id) { products[tip] = product }
            }
        } catch {
            // Leave the buttons disabled with the fallback prices; the view says the store is unavailable.
        }
        loaded = true
    }

    func buy(_ tip: Tip) async {
        guard let product = products[tip] else { return }
        status = .purchasing(tip)
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                status = .thanked
            case .success(.unverified(_, let error)):
                status = .failed(error.localizedDescription)
            case .pending, .userCancelled:
                status = .idle
            @unknown default:
                status = .idle
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
