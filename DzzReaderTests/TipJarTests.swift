import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import DzzReader

/// The 支持 tips against DzzReader.storekit (GBR storefront), run in-process with SKTestSession.
@Suite(.serialized) @MainActor struct TipJarTests {
    let session: SKTestSession

    init() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "DzzReader", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    @Test func loadsAllFourTipsWithPoundPrices() async {
        let jar = TipJar()
        await jar.load()
        #expect(jar.products.count == 4)
        #expect(jar.products[.small]?.price == Decimal(string: "0.99"))
        #expect(jar.products[.coffee]?.price == Decimal(string: "2.99"))
        #expect(jar.products[.support]?.price == Decimal(string: "4.99"))
        #expect(jar.products[.generous]?.price == Decimal(string: "9.99"))
        #expect(jar.products[.small]?.type == .consumable)
        #expect(jar.products[.small]?.priceFormatStyle.currencyCode == "GBP")
    }

    @Test func purchaseThanksAndCanRepeat() async {
        let jar = TipJar()
        await jar.load()
        await jar.buy(.coffee)
        #expect(jar.status == .thanked)
        jar.status = .idle
        await jar.buy(.coffee)   // consumable: a second tip is allowed
        #expect(jar.status == .thanked)
    }

    @Test func failedPurchaseReportsError() async throws {
        let jar = TipJar()
        await jar.load()
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        await jar.buy(.small)
        guard case .failed = jar.status else {
            Issue.record("expected failure, got \(jar.status)")
            return
        }
    }
}

private final class BundleToken {}
