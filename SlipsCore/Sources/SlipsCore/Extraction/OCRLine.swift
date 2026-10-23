import Foundation

/// A rectangle in normalised page coordinates: origin top-left, 0…1 on both axes.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
}

/// One observation from OCR: its text, where it sits on which page, and the recogniser's confidence.
public struct OCRLine: Codable, Hashable, Sendable {
    public var text: String
    public var box: NormalizedRect
    public var page: Int
    public var confidence: Double

    public init(text: String, box: NormalizedRect, page: Int = 0, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.page = page
        self.confidence = confidence
    }
}

/// Observations merged into reading rows: same page, overlapping vertically, left to right.
public struct OCRRow: Hashable, Sendable {
    /// Index in reading order, used as the "source line" of a field.
    public var index: Int
    public var page: Int
    public var text: String
    public var confidence: Double
    /// Top of the row, 0…1 on its page.
    public var top: Double

    public static func rows(from lines: [OCRLine]) -> [OCRRow] {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { ($0.page, $0.box.midY, $0.box.x) < ($1.page, $1.box.midY, $1.box.x) }
        var groups: [[OCRLine]] = []
        for line in sorted {
            if let last = groups.last?.last, last.page == line.page,
               abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.enumerated().map { i, group in
            let ordered = group.sorted { $0.box.x < $1.box.x }
            return OCRRow(index: i, page: group[0].page,
                          text: ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " "),
                          confidence: group.map(\.confidence).min() ?? 1,
                          top: group.map(\.box.y).min() ?? 0)
        }
    }
}
