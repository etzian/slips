import Foundation

/// An amount in integer minor units (cents) with its ISO 4217 currency. Never a floating point value.
public struct Money: Hashable, Codable, Sendable {
    public var minorUnits: Int
    public var currency: String

    public init(minorUnits: Int, currency: String) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// The value as a `Decimal`, for `FormatStyle.currency(code:)`. Assumes two decimals, which holds
    /// for CAD, USD and EUR; a zero-decimal currency would need its own exponent.
    public var decimal: Decimal {
        Decimal(minorUnits) / Decimal(Self.scale(for: currency))
    }

    /// Minor units of a decimal amount typed by the user, rounded half away from zero.
    public static func minorUnits(from decimal: Decimal, currency: String) -> Int {
        var scaled = decimal * Decimal(scale(for: currency))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func scale(for currency: String) -> Int {
        switch currency.uppercased() {
        case "JPY", "KRW": 1
        default: 100
        }
    }
}
