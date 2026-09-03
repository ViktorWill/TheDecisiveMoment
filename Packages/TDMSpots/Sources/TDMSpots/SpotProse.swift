import Foundation
import TDMCore

/// The words the map and the detail sheet put a spot into.
///
/// A rule of the design, not a formatting convenience: *scores are prose, never
/// numbers* (`design/Tokens.dc.html`). "137 photos nearby · plaza · curated"
/// tells a photographer something; "0.87" does not. Keeping the sentences here
/// makes them testable and keeps one wording for the list row, the marker's
/// accessibility label and the detail header.
public enum SpotProse {
    /// The clauses of a spot's score, in the order the design shows them.
    public static func scoreClauses(for spot: Spot) -> [String] {
        var clauses: [String] = []

        if let photos = spot.scoreFactors.first(where: { $0.kind == .photoDensity }),
           let count = leadingInteger(in: photos.detail) {
            clauses.append("\(count) photos nearby")
        }
        clauses.append(label(for: spot.kind))
        if spot.scoreFactors.contains(where: { $0.kind == .notability }) {
            clauses.append("notable")
        }
        if spot.curated {
            clauses.append("curated")
        }
        if spot.sources.contains(.local) {
            clauses.append("your pin")
        }
        return clauses
    }

    /// The line under a spot's name: `137 photos nearby · plaza · curated`.
    public static func scoreSummary(for spot: Spot) -> String {
        scoreClauses(for: spot).joined(separator: " · ")
    }

    /// The detail sheet's version, which also names the sky the spot has —
    /// `137 photos nearby · plaza · open sky`.
    public static func detailSummary(for spot: Spot) -> String {
        (scoreClauses(for: spot).filter { $0 != "curated" } + [label(for: spot.openness)])
            .joined(separator: " · ")
    }

    public static func label(for kind: SpotKind) -> String {
        switch kind {
        case .plaza: "plaza"
        case .market: "marketplace"
        case .street: "street"
        case .bridge: "bridge"
        case .stairs: "stairs"
        case .underpass: "underpass"
        case .arcade: "arcade"
        case .transit: "transit"
        case .waterfront: "waterfront"
        case .park: "park"
        case .viewpoint: "viewpoint"
        case .intersection: "intersection"
        case .landmark: "landmark"
        case .other: "spot"
        }
    }

    public static func label(for openness: Openness) -> String {
        switch openness {
        case .open: "open sky"
        case .canyon: "street canyon"
        case .covered: "covered"
        }
    }

    /// `240 m` under a kilometre, `1.1 km` over it — the two forms in
    /// `design/Map.dc.html`. Rounded to what a walk can tell apart.
    public static func distance(metres: Double) -> String {
        guard metres.isFinite, metres >= 0 else { return "—" }
        if metres < 1_000 {
            return "\(Int((metres / 10).rounded() * 10)) m"
        }
        let kilometres = metres / 1_000
        if kilometres < 10 {
            return String(format: "%.1f km", kilometres)
        }
        return "\(Int(kilometres.rounded())) km"
    }

    /// Walking pace, 80 m per minute — an unhurried city walk with a camera,
    /// and the figure `design/SpotDetail.dc.html` uses (240 m, 3 min).
    public static let walkingMetresPerMinute = 80.0

    public static func walkingTime(metres: Double) -> String {
        guard metres.isFinite, metres >= 0 else { return "—" }
        let minutes = max(1, Int((metres / walkingMetresPerMinute).rounded(.up)))
        if minutes < 60 { return "\(minutes) min walk" }
        let hours = Double(minutes) / 60
        return String(format: "%.1f h walk", hours)
    }

    /// The first run of digits in a factor's detail: the bundle writes
    /// "137 geotagged photos within 150 m", and the map wants the 137.
    static func leadingInteger(in detail: String) -> Int? {
        let digits = detail.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
