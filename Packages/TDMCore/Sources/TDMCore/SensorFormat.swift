import Foundation

/// The size of the frame the lens draws on, `docs/EXPOSURE-MODEL.md` §6.
///
/// One M in the roster is not full frame, which is why this is a type rather
/// than a constant: the M8 is APS-H, so its circle of confusion is smaller and
/// every hyperfocal it produces is a third longer than the same lens on an M6.
/// Rendering the full-frame band for an M8 user would be a quiet, confident lie.
///
/// Dimensions are millimetres.
public struct SensorFormat: Sendable, Hashable, Codable {
    public var name: String
    public var widthMillimetres: Double
    public var heightMillimetres: Double

    public init(name: String, widthMillimetres: Double, heightMillimetres: Double) {
        self.name = name
        self.widthMillimetres = widthMillimetres
        self.heightMillimetres = heightMillimetres
    }

    /// 36 × 24 mm — every M in the roster except the M8.
    public static let fullFrame = SensorFormat(
        name: "Full frame",
        widthMillimetres: 36,
        heightMillimetres: 24
    )

    /// APS-H, 27 × 18 mm — the M8, and only the M8.
    public static let apsH = SensorFormat(
        name: "APS-H",
        widthMillimetres: 27,
        heightMillimetres: 18
    )

    /// The frame diagonal, millimetres. 43.27 mm full frame, 32.45 mm APS-H.
    public var diagonalMillimetres: Double {
        (widthMillimetres * widthMillimetres + heightMillimetres * heightMillimetres).squareRoot()
    }

    /// How much smaller than full frame this format is: 1.0, or 1.333 on APS-H.
    ///
    /// This is framing information and nothing else. It never reaches the
    /// exposure solver — a smaller frame changes what is in the picture, not how
    /// much light falls on it.
    public var cropFactor: Double {
        SensorFormat.fullFrame.diagonalMillimetres / diagonalMillimetres
    }

    /// Circle of confusion for the format, millimetres: `0.030 × d / d_35`.
    ///
    /// 0.0300 mm full frame, 0.0225 mm on APS-H. Scaling by the diagonal and
    /// dividing the full-frame value by the crop factor agree to four decimals,
    /// so there is nothing to choose between the two conventions.
    public var circleOfConfusionMillimetres: Double {
        SensorFormat.fullFrameCircleOfConfusionMillimetres
            * diagonalMillimetres / SensorFormat.fullFrame.diagonalMillimetres
    }

    /// The full-frame circle of confusion, millimetres. 0.025 mm is the stricter
    /// standard, and a body may carry it instead; nothing hardcodes either.
    public static let fullFrameCircleOfConfusionMillimetres = 0.030

    public var isFullFrame: Bool { cropFactor < 1.001 }

    /// What a focal length frames like on this body, millimetres: a 35 mm lens
    /// on an M8 gives the field of view of a 47 mm on an M6.
    ///
    /// Framing only. Passing this to a depth-of-field or exposure calculation
    /// would be wrong twice over — the lens is still a 35 mm.
    public func equivalentFocalLengthMillimetres(_ focalLengthMillimetres: Double) -> Double {
        focalLengthMillimetres * cropFactor
    }
}
