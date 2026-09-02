import Foundation
import Testing
@testable import TDMSpots

@Test("Gzip inflates a short fixed-Huffman member")
func gzipInflatesShortString() throws {
    // Generated with: python3 - <<'PY'
    // import gzip, io, base64
    // bio=io.BytesIO()
    // with gzip.GzipFile(fileobj=bio, mode='wb', compresslevel=9, mtime=0) as f: f.write(b'The decisive moment is patient.\n')
    // print(base64.b64encode(bio.getvalue()).decode())
    // PY
    let compressed = try decodedBase64("H4sIAAAAAAAC/wvJSFVISU3OLM4sS1XIzc9NzStRyCxWKEgsyQQy9bgAjRwEECAAAAA=")
    let decompressed = try Gzip.decompress(compressed)
    #expect(String(data: decompressed, encoding: .utf8) == "The decisive moment is patient.\n")
}

@Test("Gzip inflates dynamic-Huffman JSON-like data")
func gzipInflatesDynamicHuffmanBlock() throws {
    // Generated with: python3 - <<'PY'
    // import gzip, io, base64
    // data=(b'{"spot":"corner","light":"gold","frame":[1,2,3],"note":"wait"}\n'*160)
    // bio=io.BytesIO()
    // with gzip.GzipFile(fileobj=bio, mode='wb', compresslevel=9, mtime=0) as f: f.write(data)
    // print(base64.b64encode(bio.getvalue()).decode())
    // PY
    let compressed = try decodedBase64("""
    H4sIAAAAAAAC/+3LMQ6CQBRAwd5j/HobseMqxoIgIAmyZt3Egnh38RpkyveS2eL9yjXa6HNZhxIplnl6/MeUl/ueY+meQ7TXc2rS5ZZizXXP+HRzje9pw3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx3Ecx/Ej8h/YW4txYCcAAA==
    """)
    let expected = String(repeating: #"{"spot":"corner","light":"gold","frame":[1,2,3],"note":"wait"}"# + "\n", count: 160)
    #expect(String(data: try Gzip.decompress(compressed), encoding: .utf8) == expected)
}

@Test("Gzip inflates a stored incompressible member")
func gzipInflatesStoredBlock() throws {
    // Generated with: python3 - <<'PY'
    // import gzip, io, base64
    // data=bytes(((i*73+19)&0xff) for i in range(128))
    // bio=io.BytesIO()
    // with gzip.GzipFile(fileobj=bio, mode='wb', compresslevel=0, mtime=0) as f: f.write(data)
    // print(base64.b64encode(bio.getvalue()).decode())
    // PY
    let compressed = try decodedBase64("""
    H4sIAAAAAAAA/wGAAH//E1yl7jeAyRJbpO02f8gRWqPsNX7HEFmi6zR9xg9YoeozfMUOV6DpMnvEDVaf6DF6wwxVnucwecILVJ3mL3jBClOc5S53wAlSm+Qtdr8IUZrjLHW+B1CZ4it0vQZPmOEqc7wFTpfgKXK7BE2W3yhxugNMld4ncLkCS5TdJm+4AUoTkteegAAAAA==
    """)
    let expected = Data((0..<128).map { UInt8(($0 * 73 + 19) & 0xff) })
    #expect(try Gzip.decompress(compressed) == expected)
}

@Test("Gzip skips a file-name header")
func gzipInflatesFileNameHeaderMember() throws {
    // Generated with: python3 - <<'PY'
    // import gzip, io, base64
    // bio=io.BytesIO()
    // with gzip.GzipFile(filename='street-note.txt', fileobj=bio, mode='wb', compresslevel=9, mtime=0) as f: f.write(b'filename header survives\n')
    // print(base64.b64encode(bio.getvalue()).decode())
    // PY
    let compressed = try decodedBase64("H4sICAAAAAAC/3N0cmVldC1ub3RlLnR4dABLy8xJzUvMTVXISE1MSS1SKC4tKsssSy3mAgBkzjnBGQAAAA==")
    #expect(String(data: try Gzip.decompress(compressed), encoding: .utf8) == "filename header survives\n")
}

@Test("Gzip rejects a corrupted trailer checksum")
func gzipRejectsCorruptedChecksum() throws {
    // Generated with the short-string command above, then flipped bit 0 of the trailer CRC.
    let compressed = try decodedBase64("H4sIAAAAAAAC/wvJSFVISU3OLM4sS1XIzc9NzStRyCxWKEgsyQQy9bgAjBwEECAAAAA=")
    do {
        _ = try Gzip.decompress(compressed)
        Issue.record("Expected a checksum mismatch")
    } catch let error as GzipError {
        #expect(error == .checksumMismatch)
    }
}

private func decodedBase64(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value.filter { !$0.isWhitespace }) else {
        throw TestDataError.invalidBase64
    }
    return data
}

private enum TestDataError: Error {
    case invalidBase64
}
