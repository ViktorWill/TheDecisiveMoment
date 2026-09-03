import Foundation

/// A gzip writer, because the pipeline publishes `.json.gz` and `TDMSpots`
/// only reads.
///
/// DEFLATE with fixed Huffman codes and a hash-chain match finder: not zlib's
/// ratio, but a pure-Swift one with no dependency and no platform difference,
/// and the output is a plain RFC 1952 member that any decompressor — including
/// `TDMSpots.Gzip` — accepts. A bundle is regenerated monthly on one runner;
/// the last few percent of compression is not worth a C dependency.
public enum GzipWriter {
    public static func compress(_ data: Data, modificationTime: UInt32 = 0) -> Data {
        var output = Data([0x1f, 0x8b, 0x08, 0x00])
        // MTIME is written as zero by default so a rebuild of identical
        // contents produces identical bytes.
        output.append(contentsOf: withUnsafeBytes(of: modificationTime.littleEndian) { Array($0) })
        output.append(contentsOf: [0x00, 0x03])  // no extra flags, unknown OS
        output.append(Deflate.compress([UInt8](data)))
        output.append(contentsOf: withUnsafeBytes(of: CRC32.checksum([UInt8](data)).littleEndian) { Array($0) })
        let size = UInt32(truncatingIfNeeded: UInt64(data.count))
        output.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        return output
    }
}

enum Deflate {
    /// Window and match limits from RFC 1951 §3.2.5.
    private static let windowSize = 32_768
    private static let minimumMatch = 3
    private static let maximumMatch = 258
    /// How far down a hash chain to look. Bounded so a file of one repeated
    /// byte does not turn the writer quadratic.
    private static let maximumChainLength = 128

    static func compress(_ bytes: [UInt8]) -> Data {
        var writer = BitWriter()
        writer.write(bits: 1, count: 1)   // final block
        writer.write(bits: 1, count: 2)   // fixed Huffman codes

        var head: [Int: Int] = [:]
        var previous = [Int](repeating: -1, count: bytes.count)
        var index = 0

        while index < bytes.count {
            var bestLength = 0
            var bestDistance = 0
            if index + minimumMatch <= bytes.count {
                let key = hash(bytes, at: index)
                var candidate = head[key] ?? -1
                var chain = 0
                while candidate >= 0, chain < maximumChainLength, index - candidate <= windowSize {
                    let length = matchLength(bytes, candidate, index)
                    if length > bestLength {
                        bestLength = length
                        bestDistance = index - candidate
                        if length == maximumMatch { break }
                    }
                    candidate = previous[candidate]
                    chain += 1
                }
                previous[index] = head[key] ?? -1
                head[key] = index
            }

            if bestLength >= minimumMatch {
                writeMatch(length: bestLength, distance: bestDistance, into: &writer)
                // Every position in the match still has to enter the hash chain,
                // or later matches lose their anchors.
                for offset in 1..<bestLength where index + offset + minimumMatch <= bytes.count {
                    let position = index + offset
                    let key = hash(bytes, at: position)
                    previous[position] = head[key] ?? -1
                    head[key] = position
                }
                index += bestLength
            } else {
                writeLiteral(bytes[index], into: &writer)
                index += 1
            }
        }

        writeSymbol(256, into: &writer)   // end of block
        return Data(writer.finish())
    }

    private static func hash(_ bytes: [UInt8], at index: Int) -> Int {
        (Int(bytes[index]) << 16) | (Int(bytes[index + 1]) << 8) | Int(bytes[index + 2])
    }

    private static func matchLength(_ bytes: [UInt8], _ candidate: Int, _ index: Int) -> Int {
        var length = 0
        let limit = min(maximumMatch, bytes.count - index)
        while length < limit, bytes[candidate + length] == bytes[index + length] {
            length += 1
        }
        return length >= minimumMatch ? length : 0
    }

    // MARK: - Fixed Huffman coding, RFC 1951 §3.2.6

    private static func writeLiteral(_ byte: UInt8, into writer: inout BitWriter) {
        writeSymbol(Int(byte), into: &writer)
    }

    private static func writeSymbol(_ symbol: Int, into writer: inout BitWriter) {
        switch symbol {
        case 0...143: writer.writeCode(0b0011_0000 + symbol, count: 8)
        case 144...255: writer.writeCode(0b1_1001_0000 + symbol - 144, count: 9)
        case 256...279: writer.writeCode(symbol - 256, count: 7)
        default: writer.writeCode(0b1100_0000 + symbol - 280, count: 8)
        }
    }

    private static func writeMatch(length: Int, distance: Int, into writer: inout BitWriter) {
        let lengthIndex = lengthBases.lastIndex { $0 <= length } ?? 0
        writeSymbol(257 + lengthIndex, into: &writer)
        let lengthExtra = lengthExtras[lengthIndex]
        if lengthExtra > 0 {
            writer.write(bits: length - lengthBases[lengthIndex], count: lengthExtra)
        }

        let distanceIndex = distanceBases.lastIndex { $0 <= distance } ?? 0
        writer.writeCode(distanceIndex, count: 5)
        let distanceExtra = distanceExtras[distanceIndex]
        if distanceExtra > 0 {
            writer.write(bits: distance - distanceBases[distanceIndex], count: distanceExtra)
        }
    }

    private static let lengthBases = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]

    private static let lengthExtras = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]

    private static let distanceBases = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
        193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
        6145, 8193, 12289, 16385, 24577
    ]

    private static let distanceExtras = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
        6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]
}

/// DEFLATE is little-endian in its extra bits and big-endian in its Huffman
/// codes, which is the classic place to get a compressor wrong: ``write(bits:count:)``
/// is for the former and ``writeCode(_:count:)`` for the latter.
struct BitWriter {
    private var bytes: [UInt8] = []
    private var current: UInt8 = 0
    private var bitCount = 0

    mutating func write(bits value: Int, count: Int) {
        for shift in 0..<count {
            append(bit: (value >> shift) & 1)
        }
    }

    mutating func writeCode(_ code: Int, count: Int) {
        for shift in stride(from: count - 1, through: 0, by: -1) {
            append(bit: (code >> shift) & 1)
        }
    }

    private mutating func append(bit: Int) {
        if bit == 1 { current |= UInt8(1 << bitCount) }
        bitCount += 1
        if bitCount == 8 {
            bytes.append(current)
            current = 0
            bitCount = 0
        }
    }

    mutating func finish() -> [UInt8] {
        if bitCount > 0 {
            bytes.append(current)
            current = 0
            bitCount = 0
        }
        return bytes
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1 == 1) ? (0xedb8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }
}
