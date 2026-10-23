import Foundation
import GRDB

/// Where a slip stands with its destinations, for the library's badges and filter.
public enum DeliveryState: String, Sendable, CaseIterable, Codable {
    /// No destination besides the library.
    case localOnly = "local_only"
    case delivered
    case waiting
    /// Failed or signed out somewhere: the user has to act.
    case problem
}

/// The library's filters (plan P11). Nil means "any".
public struct LibraryFilter: Sendable, Hashable {
    public var search: String = ""
    public var kind: Kind?
    public var enterpriseId: UUID?
    public var subcategoryId: UUID?
    public var paymentMethodId: UUID?
    public var status: SlipStatus?
    public var delivery: DeliveryState?
    public var withWarnings = false
    public var from: CalendarDay?
    public var to: CalendarDay?

    public init() {}

    /// Something besides the profile narrows the list (the empty state then offers to clear it).
    public var isActive: Bool {
        self != LibraryFilter()
    }
}

public struct LibraryItem: Sendable, Hashable, Identifiable {
    public var slip: Slip
    public var delivery: DeliveryState
    public var id: UUID { slip.id }

    /// The day the library files it under: the slip's date, else the capture day.
    public var day: CalendarDay { slip.txnDate ?? CalendarDay(slip.capturedAt, calendar: NamingRule.utc) }
}

public struct LibraryMonth: Sendable, Hashable, Identifiable {
    public var year: Int
    public var month: Int
    public var items: [LibraryItem]
    public var id: Int { year * 100 + month }
}

public struct LibraryQuery: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func observe(profile: UUID, filter: LibraryFilter) -> AsyncThrowingStream<[LibraryMonth], any Error> {
        database.observe { db in Self.months(try Self.items(profile: profile, filter: filter, in: db)) }
    }

    public func items(profile: UUID, filter: LibraryFilter) throws -> [LibraryItem] {
        try database.writer.read { db in try Self.items(profile: profile, filter: filter, in: db) }
    }

    static func items(profile: UUID, filter f: LibraryFilter, in db: Database) throws -> [LibraryItem] {
        var clauses = ["s.profile_id = ?"]
        var args: [any DatabaseValueConvertible] = [profile]
        if let match = ftsQuery(f.search) {
            clauses.append("s.rowid IN (SELECT rowid FROM slips_fts WHERE slips_fts MATCH ?)")
            args.append(match)
        }
        if let k = f.kind { clauses.append("s.kind = ?"); args.append(k.rawValue) }
        if let e = f.enterpriseId { clauses.append("s.enterprise_id = ?"); args.append(e) }
        if let c = f.subcategoryId { clauses.append("s.subcategory_id = ?"); args.append(c) }
        if let p = f.paymentMethodId { clauses.append("s.payment_method_id = ?"); args.append(p) }
        if let st = f.status { clauses.append("s.status = ?"); args.append(st.rawValue) }
        if f.withWarnings { clauses.append(#"(s.checks LIKE '%"warning"%' OR s.checks LIKE '%"blocking"%')"#) }
        // Filed under the slip's day, or the capture day when it has none.
        let day = "coalesce(s.txn_date, substr(s.captured_at, 1, 10))"
        if let from = f.from { clauses.append("\(day) >= ?"); args.append(from.iso) }
        if let to = f.to { clauses.append("\(day) <= ?"); args.append(to.iso) }
        let sql = """
            SELECT s.*,
              (SELECT count(*) FROM deliveries d WHERE d.slip_id = s.id) AS n_all,
              (SELECT count(*) FROM deliveries d WHERE d.slip_id = s.id AND d.status = 'done') AS n_done,
              (SELECT count(*) FROM deliveries d WHERE d.slip_id = s.id AND d.status IN ('failed', 'needs_auth')) AS n_problem
            FROM slips s WHERE \(clauses.joined(separator: " AND "))
            ORDER BY \(day) DESC, s.captured_at DESC
            """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        let items = try rows.map { row -> LibraryItem in
            let slip = try Slip(row: row)
            let all: Int = row["n_all"], done: Int = row["n_done"], problem: Int = row["n_problem"]
            let state: DeliveryState = all == 0 ? .localOnly : problem > 0 ? .problem : done == all ? .delivered : .waiting
            return LibraryItem(slip: slip, delivery: state)
        }
        guard let wanted = f.delivery else { return items }
        return items.filter { $0.delivery == wanted }
    }

    /// Words of the search box as an FTS5 query: each word a prefix, all required. Quotes and FTS
    /// syntax typed by the user are neutralised.
    static func ftsQuery(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation || $0.isSymbol })
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    static func months(_ items: [LibraryItem]) -> [LibraryMonth] {
        var result: [LibraryMonth] = []
        for item in items {
            let d = item.day
            if let last = result.last, last.year == d.year, last.month == d.month {
                result[result.count - 1].items.append(item)
            } else {
                result.append(LibraryMonth(year: d.year, month: d.month, items: [item]))
            }
        }
        return result
    }
}
