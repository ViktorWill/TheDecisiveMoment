import Testing
import TDMCore
@testable import TDMSpots

@Test("Decoder and bundle writer agree on the schema version")
func supportedSchemaVersionMatchesCore() {
    #expect(TDMSpots.supportedBundleSchemaVersion == TDMCore.bundleSchemaVersion)
}
