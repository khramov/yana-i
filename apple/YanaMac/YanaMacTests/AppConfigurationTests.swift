import Testing
import YanaSync
import YanaMarketData
@testable import YanaMac

struct AppConfigurationTests {
    @Test func cloudKitContainerComesFromSigningConfig() {
        #expect(AppConfiguration.cloudKitContainer.hasPrefix("iCloud."))
    }

    @Test func packageModulesLink() {
        #expect(PayloadCodec.schemaVersion == 1)
        #expect(MarketDataPolicy().maxConcurrentRequests == 4)
    }
}
