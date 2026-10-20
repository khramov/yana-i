import Foundation
import Testing
@testable import YanaDomain

@Suite struct UUIDv5Tests {
    static let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
    static let url = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!

    @Test func matchesRFCVectors() {
        #expect(UUID.v5(namespace: Self.dns, name: "www.example.com")
                == UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2"))
        #expect(UUID.v5(namespace: Self.dns, name: "python.org")
                == UUID(uuidString: "886313e1-3b8a-5372-9b90-0c9aee199e5d"))
        #expect(UUID.v5(namespace: Self.url, name: "http://python.org/")
                == UUID(uuidString: "4c565f0d-3f5a-5890-b41b-20cf47701c5e"))
    }
}

@Suite struct DerivedIdentityTests {
    let p1 = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let p2 = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    @Test func holdingIDIgnoresTickerSpacingAndCase() {
        #expect(RecordIdentity.holdingID(portfolioID: p1, ticker: " aapl ") == RecordIdentity.holdingID(portfolioID: p1, ticker: "AAPL"))
    }

    @Test func holdingIDDiffersAcrossPortfoliosAndTickers() {
        #expect(RecordIdentity.holdingID(portfolioID: p1, ticker: "AAPL") != RecordIdentity.holdingID(portfolioID: p2, ticker: "AAPL"))
        #expect(RecordIdentity.holdingID(portfolioID: p1, ticker: "AAPL") != RecordIdentity.holdingID(portfolioID: p1, ticker: "MSFT"))
    }

    @Test func goalIDDependsOnPortfolioScopeAndKey() {
        let stock = RecordIdentity.goalID(portfolioID: p1, scope: .assetClass, key: "stock")
        #expect(stock == RecordIdentity.goalID(portfolioID: p1, scope: .assetClass, key: " Stock "))
        #expect(stock != RecordIdentity.goalID(portfolioID: p2, scope: .assetClass, key: "stock"))
        #expect(RecordIdentity.goalID(portfolioID: p1, scope: .holding, key: "vti")
                == RecordIdentity.goalID(portfolioID: p1, scope: .holding, key: "VTI"))
        #expect(RecordIdentity.goalID(portfolioID: p1, scope: .holding, key: "cash")
                != RecordIdentity.goalID(portfolioID: p1, scope: .assetClass, key: "cash"))
    }

    @Test func derivedIDsAreVersion5() {
        let id = RecordIdentity.holdingID(portfolioID: p1, ticker: "AAPL")
        #expect(id.uuidString.dropFirst(14).first == "5")
    }
}
