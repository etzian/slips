import Foundation
import Testing
@testable import SlipsCore

/// Synthetic OCR transcripts in `Tests/Fixtures/ocr/`: one row per line, ` | ` separates observations on
/// the same row (label left, amount right), a trailing ` @0.3` sets the recogniser's confidence,
/// `---page---` starts a new page. Each `.json` names the fields that must match exactly.
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/ocr")

    static var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }.sorted()
    }

    static func lines(_ name: String) throws -> [OCRLine] {
        let text = try String(contentsOf: directory.appendingPathComponent("\(name).txt"), encoding: .utf8)
        var result: [OCRLine] = []
        var page = 0, row = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) where !raw.isEmpty {
            if raw == "---page---" { page += 1; row = 0; continue }
            var line = String(raw)
            var confidence = 1.0
            if let at = line.range(of: " @0.", options: .backwards) {
                confidence = Double("0." + line[at.upperBound...]) ?? 1
                line = String(line[..<at.lowerBound])
            }
            let parts = line.components(separatedBy: " | ")
            let y = 0.02 + Double(row) * 0.03
            for (i, part) in parts.enumerated() {
                let x = i == 0 ? 0.05 : 0.70
                result.append(OCRLine(text: part, box: NormalizedRect(x: x, y: y, width: i == 0 ? 0.6 : 0.25, height: 0.025),
                                      page: page, confidence: confidence))
            }
            row += 1
        }
        return result
    }

    struct Expected: Decodable {
        let required: [String]
        let fields: [String: JSONValue]
        let low_confidence: [String]
    }

    enum JSONValue: Decodable, Equatable, CustomStringConvertible {
        case int(Int), string(String), null
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null } else if let i = try? c.decode(Int.self) { self = .int(i) } else { self = .string(try c.decode(String.self)) }
        }
        var description: String {
            switch self {
            case .int(let i): "\(i)"
            case .string(let s): s
            case .null: "nil"
            }
        }
    }

    static func expected(_ name: String) throws -> Expected {
        try JSONDecoder().decode(Expected.self, from: Data(contentsOf: directory.appendingPathComponent("\(name).json")))
    }
}

extension Extraction {
    /// (value, confidence) of a field by its fixture name.
    func lookup(_ field: String) -> (Fixtures.JSONValue, Double?) {
        func int(_ f: ExtractedField<Int>?) -> (Fixtures.JSONValue, Double?) { (f.map { .int($0.value) } ?? .null, f?.confidence) }
        func str(_ f: ExtractedField<String>?) -> (Fixtures.JSONValue, Double?) { (f.map { .string($0.value) } ?? .null, f?.confidence) }
        switch field {
        case "merchant": return str(merchant)
        case "date": return (date.map { .string($0.value.iso) } ?? .null, date?.confidence)
        case "subtotal": return int(subtotal)
        case "gst": return int(gst)
        case "qst": return int(qst)
        case "hst": return int(hst)
        case "tip": return int(tip)
        case "total": return int(total)
        case "currency": return str(currency)
        case "card_last4": return str(cardLast4)
        case "supplier_gst_no": return str(supplierGstNo)
        case "supplier_qst_no": return str(supplierQstNo)
        default: return (.string("unknown field \(field)"), nil)
        }
    }
}

@Suite struct ParserFixtureTests {
    static let today = CalendarDay(year: 2026, month: 10, day: 23)!

    @Test func atLeastTwentyFiveFixtures() {
        #expect(Fixtures.names.count >= 25)
    }

    @Test(arguments: Fixtures.names)
    func requiredFieldsMatch(_ name: String) throws {
        let expected = try Fixtures.expected(name)
        let extraction = SlipParser.parse(try Fixtures.lines(name), today: Self.today)
        for field in expected.required {
            let want = try #require(expected.fields[field], "\(name): required field \(field) has no expected value")
            #expect(extraction.lookup(field).0 == want, "\(name): \(field)")
        }
        for field in expected.low_confidence {
            let confidence = try #require(extraction.lookup(field).1, "\(name): \(field) missing")
            #expect(confidence < ExtractedField<Int>.lowConfidence, "\(name): \(field) should be low confidence")
        }
        for field in expected.required where !expected.low_confidence.contains(field) {
            if let confidence = extraction.lookup(field).1 {
                #expect(confidence >= ExtractedField<Int>.lowConfidence, "\(name): \(field) unexpectedly low (\(confidence))")
            }
        }
    }

    /// Non-required expected values are reported, not enforced: they show where the parser is weak.
    @Test func optionalFieldsScore() throws {
        var hits = 0, total = 0
        for name in Fixtures.names {
            let expected = try Fixtures.expected(name)
            let extraction = SlipParser.parse(try Fixtures.lines(name), today: Self.today)
            for (field, want) in expected.fields {
                total += 1
                if extraction.lookup(field).0 == want { hits += 1 }
            }
        }
        #expect(Double(hits) / Double(max(total, 1)) >= 0.95, "\(hits)/\(total)")
    }
}

@Suite struct ParserUnitTests {
    @Test func amountFormats() {
        #expect(SlipParser.amounts(in: "TOTAL 12.34") == [1234])
        #expect(SlipParser.amounts(in: "TOTAL 12,34 $") == [1234])
        #expect(SlipParser.amounts(in: "TOTAL 1 234,56") == [123_456])
        #expect(SlipParser.amounts(in: "Total $1,234.56") == [123_456])
        #expect(SlipParser.amounts(in: "TVQ 9,975% 4,39") == [439])
        #expect(SlipParser.amounts(in: "RABAIS -2,00") == [-200])
        #expect(SlipParser.amounts(in: "35,123 L @ 1,659").isEmpty)
        #expect(SlipParser.amounts(in: "TPS 5%").isEmpty)
    }

    @Test func dateFormats() {
        let today = CalendarDay(year: 2026, month: 10, day: 23)
        func d(_ s: String) -> String? { SlipParser.date(in: SlipParser.Row.normalize(s), today: today)?.0.iso }
        #expect(d("2026-10-20") == "2026-10-20")
        #expect(d("20/10/2026") == "2026-10-20")
        #expect(d("10/20/26") == "2026-10-20")
        #expect(d("20 oct. 2026") == "2026-10-20")
        #expect(d("20 déc. 2025") == "2025-12-20")
        #expect(d("Oct 20, 2026") == "2026-10-20")
        #expect(d("1 août 2026") == "2026-08-01")
        #expect(d("20-OCT-26") == "2026-10-20")
        #expect(d("31/02/2026") == nil)
    }

    @Test func futureReadingLoses() {
        let today = CalendarDay(year: 2026, month: 10, day: 23)
        // 03/11/2026: 3 November (future) or 11 March (past) → March.
        #expect(SlipParser.date(in: "03/11/2026", today: today)?.0.iso == "2026-03-11")
    }

    @Test func registrationNumbersNormalised() {
        let rows = OCRRow.rows(from: [OCRLine(text: "TPS# 100000000RT0001", box: .init(x: 0, y: 0, width: 1, height: 0.02)),
                                      OCRLine(text: "TVQ# 1000000000 TQ 0001", box: .init(x: 0, y: 0.1, width: 1, height: 0.02))])
            .map(SlipParser.Row.init)
        #expect(SlipParser.gstNumber(rows)?.value == "100000000 RT0001")
        #expect(SlipParser.qstNumber(rows)?.value == "1000000000 TQ0001")
    }

    @Test func rowsMergeObservationsOnTheSameLine() {
        let rows = OCRRow.rows(from: [
            OCRLine(text: "12,34", box: .init(x: 0.7, y: 0.501, width: 0.2, height: 0.02)),
            OCRLine(text: "TOTAL", box: .init(x: 0.05, y: 0.5, width: 0.2, height: 0.02)),
            OCRLine(text: "MERCI", box: .init(x: 0.05, y: 0.6, width: 0.2, height: 0.02)),
        ])
        #expect(rows.map(\.text) == ["TOTAL 12,34", "MERCI"])
    }

    @Test func applyCopiesFieldsIntoSlip() throws {
        var slip = Slip(profileId: UUID(), pdfPath: "x", pdfSha256: String(repeating: "f", count: 64), pageCount: 1)
        let lines = try Fixtures.lines("03_restaurant_tip_fr")
        slip.apply(SlipParser.parse(lines), ocrText: SlipParser.text(of: lines))
        #expect(slip.total == 5818)
        #expect(slip.tip == 759)
        #expect(slip.merchant == "RESTO FICTIF")
        #expect(slip.extraction?.total?.value == 5818)
        #expect(slip.ocrText?.contains("POURBOIRE") == true)
    }
}
