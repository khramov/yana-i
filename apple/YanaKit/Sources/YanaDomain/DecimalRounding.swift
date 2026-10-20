import Foundation

extension Decimal {
    /// Rounded to `scale` fractional digits (half away from zero). For display and test comparisons only.
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }
}
