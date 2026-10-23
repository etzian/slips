import Foundation

/// The key a merchant's history is filed under: case, accents, punctuation, store numbers and legal
/// suffixes removed, so "ÉPICERIE FICTIVE #0042" and "Epicerie Fictive inc." share one memory.
public enum MerchantName {
    static let legalSuffixes: Set<String> = ["inc", "ltee", "ltd", "llc", "enr", "senc", "corp", "co", "limitee", "limited"]
    static let storeWords: Set<String> = ["no", "num", "store", "magasin", "succ", "succursale"]

    public static func normalize(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let words = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var tokens = String(words).split(separator: " ").map(String.init)
        // Store numbers: any token with a digit, and the word that introduces it.
        tokens.removeAll { $0.contains(where: \.isNumber) }
        while let last = tokens.last, legalSuffixes.contains(last) || storeWords.contains(last) { tokens.removeLast() }
        tokens.removeAll { storeWords.contains($0) }
        return tokens.joined(separator: " ")
    }
}
