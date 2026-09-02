import Testing
@testable import TDMCore

@Test("Bundle schema version is the v1 format described in docs/DATA-BUNDLES.md")
func bundleSchemaVersionIsOne() {
    #expect(TDMCore.bundleSchemaVersion == 1)
}
