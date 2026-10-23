import Foundation

/// A minimal ZIP writer (stored entries, no compression: PDFs are compressed already). Enough for
/// every unzip tool; no dependency. Entries over 4 GB are not supported (ZIP64), which no export reaches.
public struct ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0
    private var names = Set<String>()

    public init() {}

    public enum ZipError: Error, Equatable {
        case duplicateName(String)
        case tooLarge
    }

    /// Adds a file. `name` uses `/` for folders and is stored as UTF-8.
    public mutating func add(_ name: String, contents: Data, modified: Date = Date()) throws {
        guard names.insert(name).inserted else { throw ZipError.duplicateName(name) }
        guard contents.count < Int(UInt32.max), data.count < Int(UInt32.max) else { throw ZipError.tooLarge }
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(contents)
        let (time, date) = Self.dosDateTime(modified)
        let offset = UInt32(data.count)

        var local = Data()
        local.append(le32: 0x0403_4b50)
        local.append(le16: 20)           // version needed
        local.append(le16: 0x0800)       // UTF-8 names
        local.append(le16: 0)            // stored
        local.append(le16: time)
        local.append(le16: date)
        local.append(le32: crc)
        local.append(le32: UInt32(contents.count))
        local.append(le32: UInt32(contents.count))
        local.append(le16: UInt16(nameBytes.count))
        local.append(le16: 0)
        local.append(nameBytes)
        data.append(local)
        data.append(contents)

        var entry = Data()
        entry.append(le32: 0x0201_4b50)
        entry.append(le16: 20)           // made by
        entry.append(le16: 20)
        entry.append(le16: 0x0800)
        entry.append(le16: 0)
        entry.append(le16: time)
        entry.append(le16: date)
        entry.append(le32: crc)
        entry.append(le32: UInt32(contents.count))
        entry.append(le32: UInt32(contents.count))
        entry.append(le16: UInt16(nameBytes.count))
        entry.append(le16: 0)            // extra
        entry.append(le16: 0)            // comment
        entry.append(le16: 0)            // disk
        entry.append(le16: 0)            // internal attributes
        entry.append(le32: 0)            // external attributes
        entry.append(le32: offset)
        entry.append(nameBytes)
        central.append(entry)
        count += 1
    }

    /// The archive bytes.
    public func finish() -> Data {
        var out = data
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: count)
        out.append(le16: count)
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)
        return out
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = NamingRule.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max((c.year ?? 1980) - 1980, 0), month: Int = c.month ?? 1, dayOfMonth: Int = c.day ?? 1
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let day = UInt16((year << 9) | (month << 5) | dayOfMonth)
        return (time, day)
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }

    mutating func append(le32 v: UInt32) {
        for i in 0..<4 { append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }
}
