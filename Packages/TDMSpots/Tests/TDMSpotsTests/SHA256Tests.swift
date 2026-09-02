import Foundation
import Testing
@testable import TDMSpots

@Test("SHA-256 matches the empty-message NIST vector")
func sha256EmptyString() {
    // NIST FIPS 180-4 publishes these canonical SHA-256 example digests.
    #expect(SHA256.hexDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
}

@Test("SHA-256 matches the abc NIST vector")
func sha256ABC() {
    #expect(SHA256.hexDigest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test("SHA-256 matches the 448-bit two-block NIST vector")
func sha256TwoBlockMessage() {
    let message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    #expect(SHA256.hexDigest(Data(message.utf8)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
}
