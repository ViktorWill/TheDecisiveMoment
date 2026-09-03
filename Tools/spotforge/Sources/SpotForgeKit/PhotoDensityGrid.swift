import Foundation
import TDMCore

/// Geotagged Commons photos, binned into equal-area-ish cells.
///
/// The grid is the pipeline's answer to "where have people actually stood and
/// made pictures", and it is also what the heatmap layer draws. Counting into
/// cells once, rather than asking Commons per candidate, is what keeps the cost
/// bounded: thousands of candidates share a few thousand cells.
public struct PhotoDensityGrid: Sendable, Equatable {
    public struct Cell: Hashable, Sendable {
        public var latIndex: Int
        public var lonIndex: Int
    }

    /// Cell edge length. 250 m is about the distance a photographer would call
    /// "here" rather than "over there".
    public let cellMetres: Double
    public private(set) var counts: [Cell: Int] = [:]

    /// Metres per degree of latitude, spherical Earth. Longitude is scaled by
    /// `cos(latitude)` at the grid's reference latitude, so cells stay roughly
    /// square over one city.
    static let metresPerDegreeLatitude = 111_320.0
    private let referenceLatitudeRad: Double

    public init(cellMetres: Double = 250, referenceLatitude: Double = 0) {
        self.cellMetres = cellMetres
        self.referenceLatitudeRad = referenceLatitude * .pi / 180
    }

    public var cellDegreesLatitude: Double {
        cellMetres / Self.metresPerDegreeLatitude
    }

    public var cellDegreesLongitude: Double {
        let scale = max(0.01, cos(referenceLatitudeRad))
        return cellMetres / (Self.metresPerDegreeLatitude * scale)
    }

    public func cell(for coordinate: Coordinate) -> Cell {
        Cell(
            latIndex: Int((coordinate.latitude / cellDegreesLatitude).rounded(.down)),
            lonIndex: Int((coordinate.longitude / cellDegreesLongitude).rounded(.down))
        )
    }

    public func center(of cell: Cell) -> Coordinate {
        Coordinate(
            latitude: (Double(cell.latIndex) + 0.5) * cellDegreesLatitude,
            longitude: (Double(cell.lonIndex) + 0.5) * cellDegreesLongitude
        )
    }

    public mutating func add(_ coordinate: Coordinate, count: Int = 1) {
        counts[cell(for: coordinate), default: 0] += count
    }

    /// A candidate's density: its own cell plus its eight neighbours, which is
    /// a square of about 750 m — the radius reported in the score detail.
    public func count(around coordinate: Coordinate) -> Int {
        let origin = cell(for: coordinate)
        var total = 0
        for latOffset in -1...1 {
            for lonOffset in -1...1 {
                total += counts[Cell(latIndex: origin.latIndex + latOffset, lonIndex: origin.lonIndex + lonOffset)] ?? 0
            }
        }
        return total
    }

    /// The radius the count describes, for the score's detail sentence: half the
    /// three-by-three block the count is taken over.
    public var neighbourhoodRadiusMetres: Double {
        cellMetres * 1.5
    }

    public var totalPhotos: Int {
        counts.values.reduce(0, +)
    }

    /// The cells worth publishing as candidates in their own right, densest
    /// first, so the choice does not depend on dictionary ordering.
    public func denseCells(minimumCount: Int) -> [(cell: Cell, count: Int)] {
        counts
            .filter { $0.value >= minimumCount }
            .sorted {
                $0.value == $1.value
                    ? ($0.key.latIndex, $0.key.lonIndex) < ($1.key.latIndex, $1.key.lonIndex)
                    : $0.value > $1.value
            }
            .map { (cell: $0.key, count: $0.value) }
    }

    /// Sample points covering `bbox` on a lattice of `spacingMetres`.
    public func samplePoints(in bbox: BoundingBox, spacingMetres: Double) -> [Coordinate] {
        let latStep = spacingMetres / Self.metresPerDegreeLatitude
        let lonStep = spacingMetres / (Self.metresPerDegreeLatitude * max(0.01, cos(referenceLatitudeRad)))
        guard latStep > 0, lonStep > 0 else { return [] }

        var points: [Coordinate] = []
        var latitude = bbox.minLat + latStep / 2
        while latitude < bbox.maxLat + latStep / 2 {
            var longitude = bbox.minLon + lonStep / 2
            while longitude < bbox.maxLon + lonStep / 2 {
                points.append(Coordinate(latitude: min(latitude, bbox.maxLat), longitude: min(longitude, bbox.maxLon)))
                longitude += lonStep
            }
            latitude += latStep
        }
        return points
    }
}
