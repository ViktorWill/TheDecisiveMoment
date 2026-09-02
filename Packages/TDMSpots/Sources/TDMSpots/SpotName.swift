import Foundation

/// Name comparison for the dedupe rule in `docs/SPOTFORGE.md` §7.
///
/// Two sources describing the same place rarely agree on the name: OSM says
/// "Washington Square Park", Wikidata says "Washington Square", a curated entry
/// says "Washington Sq.". Normalisation removes the parts that never carry the
/// distinction, and Jaro-Winkler scores what is left.
public enum SpotName {
    /// Generic words that are dropped from the tail of a name. They describe the
    /// kind of place, which the `kind` field already carries, so keeping them
    /// only adds agreement where there is none.
    static let genericSuffixes: Set<String> = [
        "square", "sq", "plaza", "place", "park", "gardens", "garden",
        "market", "marketplace", "station", "bridge", "steps", "stairs",
        "street", "st", "avenue", "ave", "road", "rd", "lane", "boulevard", "blvd",
        "the"
    ]

    /// Casefolded, diacritic-stripped, punctuation-collapsed, suffix-stripped.
    ///
    /// The suffix strip is repeated, so "Washington Square Park" and
    /// "Washington Square" both reduce to "washington".
    public static func normalized(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let cleaned = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var tokens = cleaned.split(separator: " ").map(String.init)
        while let last = tokens.last, genericSuffixes.contains(last), tokens.count > 1 {
            tokens.removeLast()
        }
        while let first = tokens.first, first == "the", tokens.count > 1 {
            tokens.removeFirst()
        }
        return tokens.joined(separator: " ")
    }

    /// Jaro-Winkler similarity, `0…1`, over the normalised forms.
    ///
    /// Jaro-Winkler rather than edit distance because it rewards a shared
    /// prefix, and place names differ far more often at the end than at the
    /// start.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        jaroWinkler(Array(normalized(lhs)), Array(normalized(rhs)))
    }

    static func jaroWinkler(_ lhs: [Character], _ rhs: [Character], prefixScale: Double = 0.1) -> Double {
        let jaroScore = jaro(lhs, rhs)
        guard jaroScore > 0.7 else { return jaroScore }

        var prefix = 0
        for (a, b) in zip(lhs, rhs) {
            if a != b { break }
            prefix += 1
            if prefix == 4 { break }
        }
        return jaroScore + Double(prefix) * prefixScale * (1 - jaroScore)
    }

    static func jaro(_ lhs: [Character], _ rhs: [Character]) -> Double {
        if lhs.isEmpty && rhs.isEmpty { return 1 }
        if lhs.isEmpty || rhs.isEmpty { return 0 }

        let window = max(max(lhs.count, rhs.count) / 2 - 1, 0)
        var lhsMatched = [Bool](repeating: false, count: lhs.count)
        var rhsMatched = [Bool](repeating: false, count: rhs.count)
        var matches = 0

        for (index, character) in lhs.enumerated() {
            let lower = max(0, index - window)
            let upper = min(index + window + 1, rhs.count)
            guard lower < upper else { continue }
            for other in lower..<upper where !rhsMatched[other] && rhs[other] == character {
                lhsMatched[index] = true
                rhsMatched[other] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }

        var transpositions = 0
        var rhsIndex = 0
        for index in 0..<lhs.count where lhsMatched[index] {
            while !rhsMatched[rhsIndex] { rhsIndex += 1 }
            if lhs[index] != rhs[rhsIndex] { transpositions += 1 }
            rhsIndex += 1
        }

        let m = Double(matches)
        return (m / Double(lhs.count) + m / Double(rhs.count) + (m - Double(transpositions) / 2) / m) / 3
    }
}
