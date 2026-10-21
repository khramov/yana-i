import Foundation
import Testing
@testable import YanaDomain

@Suite struct OptionContractTests {
    let pbrCall = OptionContract(underlying: "pbr", expiry: day("2027-12-17"), right: .call, strike: 27)

    @Test func occSymbolForPBRCall() {
        #expect(pbrCall.occSymbol == "PBR271217C00027000")
        #expect(pbrCall.displayName == "PBR 17DEC27 27 C")
    }

    @Test func fractionalStrike() {
        let put = OptionContract(underlying: "PBR", expiry: day("2027-12-17"), right: .put, strike: dec("27.5"))
        #expect(put.occSymbol == "PBR271217P00027500")
        #expect(put.displayName == "PBR 17DEC27 27.5 P")
    }

    @Test func parsesPaddedIBKRSymbol() {
        let parsed = OptionContract(occSymbol: "PBR   271217C00027000")
        #expect(parsed == OptionContract(underlying: "PBR", expiry: day("2027-12-17"), right: .call, strike: 27))
        #expect(OptionContract(occSymbol: "PBR271217C00027000") == parsed)
    }

    @Test func rejectsGarbage() {
        #expect(OptionContract(occSymbol: "VWCE") == nil)
        #expect(OptionContract(occSymbol: "PBR271317C00027000") == nil)
        #expect(OptionContract(occSymbol: "PBR271217X00027000") == nil)
    }
}
