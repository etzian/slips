import Foundation
import GRDB

/// A date on a slip: a calendar day with no time and no time zone, stored as `YYYY-MM-DD`.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    /// Returns nil when the day does not exist in the Gregorian calendar.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysIn(month: month, year: year),
              (1900...9999).contains(year)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The day of `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!
        month = c.month!
        day = c.day!
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    /// Noon of this day in `calendar`'s time zone, a safe instant for formatting and arithmetic.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = CalendarDay(iso: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a YYYY-MM-DD day"))
        }
        self = d
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

extension CalendarDay: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { iso.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> CalendarDay? {
        String.fromDatabaseValue(dbValue).flatMap(CalendarDay.init(iso:))
    }
}
