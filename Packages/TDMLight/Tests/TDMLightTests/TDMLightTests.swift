import Testing
@testable import TDMLight

@Test("EV values are reported against ISO 100")
func referenceISOIsOneHundred() {
    #expect(TDMLight.referenceISO == 100)
}
