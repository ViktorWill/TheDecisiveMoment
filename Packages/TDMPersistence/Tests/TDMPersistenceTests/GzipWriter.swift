import Foundation

/// A gzip writer good enough for a fixture: stored (uncompressed) deflate
/// blocks, RFC 1951 §3.2.4.
///
/// The suite needs bundles it can bend — a truncated one, one whose checksum is
/// wrong — and building them here keeps the tests free of a second copy of the
/// fixture and free of any network. `TDMSpots.Gzip` only reads.
enum GzipWriter {
    static func compress(_ data: Data) -> Data {
        var output = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        let bytes = [UInt8](data)

        if bytes.isEmpty {
            output.append(contentsOf: [0x01, 0x00, 0x00, 0xff, 0xff])
        } else {
            var offset = 0
            while offset < bytes.count {
                let length = min(0xffff, bytes.count - offset)
                let isFinal: UInt8 = offset + length == bytes.count ? 1 : 0
                output.append(isFinal)
                output.append(UInt8(length & 0xff))
                output.append(UInt8((length >> 8) & 0xff))
                let complement = ~UInt16(length)
                output.append(UInt8(complement & 0xff))
                output.append(UInt8((complement >> 8) & 0xff))
                output.append(contentsOf: bytes[offset..<(offset + length)])
                offset += length
            }
        }

        var crc = CRC32.checksum(bytes)
        var size = UInt32(truncatingIfNeeded: UInt64(bytes.count))
        for _ in 0..<4 {
            output.append(UInt8(crc & 0xff))
            crc >>= 8
        }
        for _ in 0..<4 {
            output.append(UInt8(size & 0xff))
            size >>= 8
        }
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
