import Foundation

/// Why a gzip member could not be inflated.
public enum GzipError: Error, Equatable, Sendable {
    /// The magic bytes are absent, so treating the payload as a spot bundle
    /// would hide a caller-side format mix-up.
    case notGzip
    /// Gzip only standardises DEFLATE. Other methods need a different
    /// decoder, not a best-effort interpretation.
    case unsupportedCompressionMethod(UInt8)
    /// Reserved header bits change the container contract and are rejected
    /// rather than silently ignored.
    case unsupportedFlags(UInt8)
    /// A length field or terminator points past the bytes the caller provided.
    case truncated
    /// The RFC 1951 bitstream is malformed.
    case invalidDeflateStream(reason: String)
    /// The stored CRC does not match the inflated bytes.
    case checksumMismatch
    /// The stored size does not match the inflated byte count modulo 2³².
    case sizeMismatch
    /// The member inflates to more than the caller allowed. A few kilobytes of
    /// DEFLATE can expand to gigabytes, and a city bundle is a static file from
    /// a CDN that anyone on the path could have substituted, so the ceiling is
    /// enforced while inflating rather than discovered afterwards.
    case decompressedSizeLimitExceeded(limit: Int)
}

public enum Gzip {
    /// `docs/DATA-BUNDLES.md`, "Size budget": spotforge's compressed ceiling is
    /// 8 MB per city. This spot JSON has measured at ~12.3x compression (New
    /// York: 6,292,570 B decompressed from 511,975 B gzipped), so a city that
    /// actually fills the budget could legitimately decompress to ~98 MB. This
    /// limit needs to clear that with real margin for a denser city, while
    /// staying well short of a phone's memory — it is not a mirror of the
    /// compressed budget, since the two are in different modules and a
    /// malicious file is under no obligation to respect either one; it is the
    /// most this app will ever inflate one gzip member to, full stop.
    public static let defaultDecompressedSizeLimit = 128 * 1024 * 1024

    public static func decompress(_ data: Data, maximumDecompressedBytes: Int = defaultDecompressedSizeLimit) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw GzipError.truncated }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw GzipError.notGzip }
        guard bytes.count >= 18 else { throw GzipError.truncated }
        guard bytes[2] == 8 else { throw GzipError.unsupportedCompressionMethod(bytes[2]) }

        let flags = bytes[3]
        guard flags & 0xe0 == 0 else { throw GzipError.unsupportedFlags(flags) }

        var index = 10
        if flags & 0x04 != 0 {
            let extraLength = try littleEndianUInt16(bytes, at: index)
            index += 2 + Int(extraLength)
            guard index <= bytes.count - 8 else { throw GzipError.truncated }
        }
        if flags & 0x08 != 0 {
            index = try skipNullTerminatedField(bytes, from: index)
        }
        if flags & 0x10 != 0 {
            index = try skipNullTerminatedField(bytes, from: index)
        }
        if flags & 0x02 != 0 {
            guard index + 2 <= bytes.count - 8 else { throw GzipError.truncated }
            let stored = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            let actual = UInt16(truncatingIfNeeded: CRC32.checksum(Array(bytes[..<index])))
            guard stored == actual else { throw GzipError.checksumMismatch }
            index += 2
        }

        let trailerStart = bytes.count - 8
        guard index <= trailerStart else { throw GzipError.truncated }

        let inflated = try Deflate.inflate(Array(bytes[index..<trailerStart]), limit: maximumDecompressedBytes)
        let storedCRC = try littleEndianUInt32(bytes, at: trailerStart)
        let storedSize = try littleEndianUInt32(bytes, at: trailerStart + 4)
        guard CRC32.checksum(inflated) == storedCRC else { throw GzipError.checksumMismatch }
        guard UInt32(truncatingIfNeeded: UInt64(inflated.count)) == storedSize else { throw GzipError.sizeMismatch }
        return Data(inflated)
    }

    private static func skipNullTerminatedField(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index <= bytes.count - 8 {
            if bytes[index] == 0 { return index + 1 }
            index += 1
        }
        throw GzipError.truncated
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], at index: Int) throws -> UInt16 {
        guard index + 2 <= bytes.count else { throw GzipError.truncated }
        return UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at index: Int) throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw GzipError.truncated }
        return UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}

private enum Deflate {
    static func inflate(_ bytes: [UInt8], limit: Int) throws -> [UInt8] {
        var reader = BitReader(bytes)
        var output: [UInt8] = []
        var isFinalBlock = false

        while !isFinalBlock {
            isFinalBlock = try reader.readBits(1) == 1
            switch try reader.readBits(2) {
            case 0:
                try inflateStoredBlock(&reader, into: &output, limit: limit)
            case 1:
                let fixed = fixedDecoders
                try inflateCompressedBlock(&reader, into: &output, literalLength: fixed.literalLength, distance: fixed.distance, limit: limit)
            case 2:
                let dynamic = try dynamicDecoders(&reader)
                try inflateCompressedBlock(&reader, into: &output, literalLength: dynamic.literalLength, distance: dynamic.distance, limit: limit)
            default:
                throw GzipError.invalidDeflateStream(reason: "reserved block type")
            }
        }

        return output
    }

    private static func inflateStoredBlock(_ reader: inout BitReader, into output: inout [UInt8], limit: Int) throws {
        reader.alignToByte()
        let length = try reader.readAlignedUInt16()
        let complement = try reader.readAlignedUInt16()
        guard length == ~complement else {
            throw GzipError.invalidDeflateStream(reason: "stored block length check failed")
        }
        guard output.count + Int(length) <= limit else {
            throw GzipError.decompressedSizeLimitExceeded(limit: limit)
        }
        output.append(contentsOf: try reader.readAlignedBytes(count: Int(length)))
    }

    private static func inflateCompressedBlock(
        _ reader: inout BitReader,
        into output: inout [UInt8],
        literalLength: HuffmanDecoder,
        distance: HuffmanDecoder?,
        limit: Int
    ) throws {
        while true {
            let symbol = try literalLength.decode(&reader)
            switch symbol {
            case 0...255:
                guard output.count < limit else {
                    throw GzipError.decompressedSizeLimitExceeded(limit: limit)
                }
                output.append(UInt8(symbol))
            case 256:
                return
            case 257...285:
                let lengthIndex = symbol - 257
                let length = lengthBases[lengthIndex] + (try reader.readBits(lengthExtras[lengthIndex]))
                guard let distance else {
                    throw GzipError.invalidDeflateStream(reason: "length code without a distance table")
                }
                let distanceSymbol = try distance.decode(&reader)
                guard distanceSymbol < distanceBases.count else {
                    throw GzipError.invalidDeflateStream(reason: "invalid distance code")
                }
                let offset = distanceBases[distanceSymbol] + (try reader.readBits(distanceExtras[distanceSymbol]))
                guard offset > 0, offset <= output.count else {
                    throw GzipError.invalidDeflateStream(reason: "copy distance is outside the output window")
                }
                guard output.count + length <= limit else {
                    throw GzipError.decompressedSizeLimitExceeded(limit: limit)
                }
                for _ in 0..<length {
                    output.append(output[output.count - offset])
                }
            default:
                throw GzipError.invalidDeflateStream(reason: "invalid literal/length code")
            }
        }
    }

    private static let fixedDecoders: (literalLength: HuffmanDecoder, distance: HuffmanDecoder) = {
        var lengths = Array(repeating: 8, count: 288)
        for symbol in 144...255 { lengths[symbol] = 9 }
        for symbol in 256...279 { lengths[symbol] = 7 }
        let literalLength = try! HuffmanDecoder(lengths: lengths)
        let distance = try! HuffmanDecoder(lengths: Array(repeating: 5, count: 32))
        return (literalLength, distance)
    }()

    private static func dynamicDecoders(_ reader: inout BitReader) throws
        -> (literalLength: HuffmanDecoder, distance: HuffmanDecoder?) {
        let literalLengthCount = try reader.readBits(5) + 257
        let distanceCount = try reader.readBits(5) + 1
        let codeLengthCount = try reader.readBits(4) + 4
        // RFC 1951 §3.2.7 defines 286 literal/length and 30 distance codes;
        // the encodings above can express more, and those values are reserved.
        guard literalLengthCount <= 286, distanceCount <= 30 else {
            throw GzipError.invalidDeflateStream(reason: "reserved dynamic table size")
        }

        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengthLengths = Array(repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengthLengths[order[index]] = try reader.readBits(3)
        }
        let codeLengthDecoder = try HuffmanDecoder(lengths: codeLengthLengths)

        var lengths: [Int] = []
        lengths.reserveCapacity(literalLengthCount + distanceCount)
        while lengths.count < literalLengthCount + distanceCount {
            let symbol = try codeLengthDecoder.decode(&reader)
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else {
                    throw GzipError.invalidDeflateStream(reason: "repeat code has no previous length")
                }
                lengths.append(contentsOf: repeatElement(previous, count: try reader.readBits(2) + 3))
            case 17:
                lengths.append(contentsOf: repeatElement(0, count: try reader.readBits(3) + 3))
            case 18:
                lengths.append(contentsOf: repeatElement(0, count: try reader.readBits(7) + 11))
            default:
                throw GzipError.invalidDeflateStream(reason: "invalid code-length code")
            }
            guard lengths.count <= literalLengthCount + distanceCount else {
                throw GzipError.invalidDeflateStream(reason: "too many dynamic code lengths")
            }
        }

        let literalLengths = Array(lengths[..<literalLengthCount])
        guard literalLengths[256] > 0 else {
            throw GzipError.invalidDeflateStream(reason: "missing end-of-block code")
        }
        let distanceLengths = Array(lengths[literalLengthCount...])
        let distanceDecoder = distanceLengths.contains(where: { $0 > 0 })
            ? try HuffmanDecoder(lengths: distanceLengths)
            : nil
        return (try HuffmanDecoder(lengths: literalLengths), distanceDecoder)
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

private struct BitReader {
    private let bytes: [UInt8]
    private var byteIndex = 0
    private var bitIndex = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func readBit() throws -> Int {
        guard byteIndex < bytes.count else { throw GzipError.truncated }
        let bit = Int((bytes[byteIndex] >> bitIndex) & 1)
        bitIndex += 1
        if bitIndex == 8 {
            bitIndex = 0
            byteIndex += 1
        }
        return bit
    }

    mutating func readBits(_ count: Int) throws -> Int {
        var value = 0
        for shift in 0..<count {
            value |= try readBit() << shift
        }
        return value
    }

    mutating func alignToByte() {
        if bitIndex != 0 {
            bitIndex = 0
            byteIndex += 1
        }
    }

    mutating func readAlignedUInt16() throws -> UInt16 {
        guard bitIndex == 0, byteIndex + 2 <= bytes.count else { throw GzipError.truncated }
        defer { byteIndex += 2 }
        return UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
    }

    mutating func readAlignedBytes(count: Int) throws -> [UInt8] {
        guard bitIndex == 0, byteIndex + count <= bytes.count else { throw GzipError.truncated }
        defer { byteIndex += count }
        return Array(bytes[byteIndex..<byteIndex + count])
    }
}

private struct HuffmanDecoder {
    private let table: [Int: Int]
    private let maxBits: Int

    init(lengths: [Int]) throws {
        guard let maxBits = lengths.max(), maxBits > 0 else {
            throw GzipError.invalidDeflateStream(reason: "empty Huffman table")
        }
        guard maxBits <= 15, lengths.allSatisfy({ $0 >= 0 }) else {
            throw GzipError.invalidDeflateStream(reason: "invalid Huffman code length")
        }

        var counts = Array(repeating: 0, count: maxBits + 1)
        for length in lengths where length > 0 {
            counts[length] += 1
        }

        // Kraft: a canonical Huffman table must use its code space exactly.
        // An over-subscribed table decodes ambiguously and an incomplete one
        // leaves bit patterns undefined, so both are rejected here rather than
        // surfacing later as a plausible-looking wrong byte. The single
        // exception RFC 1951 allows is a one-code distance table.
        var remainingCodeSpace = 1
        for bits in 1...maxBits {
            remainingCodeSpace <<= 1
            remainingCodeSpace -= counts[bits]
            guard remainingCodeSpace >= 0 else {
                throw GzipError.invalidDeflateStream(reason: "over-subscribed Huffman table")
            }
        }
        let usedSymbols = counts[1...].reduce(0, +)
        guard remainingCodeSpace == 0 || usedSymbols == 1 else {
            throw GzipError.invalidDeflateStream(reason: "incomplete Huffman table")
        }

        var nextCode = Array(repeating: 0, count: maxBits + 1)
        var code = 0
        for bits in 1...maxBits {
            code = (code + counts[bits - 1]) << 1
            nextCode[bits] = code
        }

        var table: [Int: Int] = [:]
        for (symbol, length) in lengths.enumerated() where length > 0 {
            let assignedCode = nextCode[length]
            nextCode[length] += 1
            let key = Self.key(code: Self.reversedBits(assignedCode, count: length), length: length)
            guard table[key] == nil else {
                throw GzipError.invalidDeflateStream(reason: "duplicate Huffman code")
            }
            table[key] = symbol
        }

        self.table = table
        self.maxBits = maxBits
    }

    func decode(_ reader: inout BitReader) throws -> Int {
        var code = 0
        for length in 1...maxBits {
            code |= try reader.readBit() << (length - 1)
            if let symbol = table[Self.key(code: code, length: length)] {
                return symbol
            }
        }
        throw GzipError.invalidDeflateStream(reason: "unknown Huffman code")
    }

    private static func key(code: Int, length: Int) -> Int {
        (length << 16) | code
    }

    private static func reversedBits(_ value: Int, count: Int) -> Int {
        var result = 0
        for index in 0..<count {
            result = (result << 1) | ((value >> index) & 1)
        }
        return result
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1 == 1) ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
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
