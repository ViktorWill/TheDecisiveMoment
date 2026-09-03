import Foundation
import Testing
@testable import TDMCore

@Suite("Sensor formats — EXPOSURE-MODEL §6")
struct SensorFormatTests {
    @Test("Full frame is 36 x 24 and the M8's APS-H frame is 27 x 18")
    func dimensions() {
        #expect(SensorFormat.fullFrame.widthMillimetres == 36)
        #expect(SensorFormat.fullFrame.heightMillimetres == 24)
        #expect(SensorFormat.apsH.widthMillimetres == 27)
        #expect(SensorFormat.apsH.heightMillimetres == 18)
        #expect(SensorFormat.fullFrame.isFullFrame)
        #expect(!SensorFormat.apsH.isFullFrame)
    }

    /// The circle of confusion scales with the diagonal, because it is a
    /// fraction of the frame rather than a fixed length: 0.030 × 32.45 / 43.27.
    @Test("The circle of confusion follows the diagonal")
    func circleOfConfusion() {
        #expect(abs(SensorFormat.fullFrame.circleOfConfusionMillimetres - 0.0300) < 0.00005)
        #expect(abs(SensorFormat.apsH.circleOfConfusionMillimetres - 0.0225) < 0.00005)
    }

    @Test("A 35 mm frames like a 47 mm on APS-H, and like a 35 mm on full frame")
    func framing() {
        #expect(abs(SensorFormat.apsH.cropFactor - 1.333) <= 0.001)
        #expect(SensorFormat.fullFrame.cropFactor == 1)
        #expect(SensorFormat.apsH.equivalentFocalLengthMillimetres(35).rounded() == 47)
        #expect(SensorFormat.apsH.equivalentFocalLengthMillimetres(50).rounded() == 67)
        #expect(SensorFormat.fullFrame.equivalentFocalLengthMillimetres(50) == 50)
    }
}
