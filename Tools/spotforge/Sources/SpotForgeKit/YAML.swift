import Foundation

/// A value from the YAML subset spotforge reads.
///
/// The pipeline has no third-party dependencies, and the two files it parses —
/// `data/cities.yml` and `data/curated/{city}.yml` — are written by hand in a
/// deliberately small dialect: block mappings and sequences, flow mappings and
/// sequences on one line, folded (`>`) scalars, and comments. Anything outside
/// that raises rather than being silently reinterpreted, because a curated file
/// that half-parses is worse than one that refuses to.
public enum YAMLValue: Sendable, Equatable {
    case scalar(String)
    case sequence([YAMLValue])
    case mapping([String: YAMLValue])

    public var stringValue: String? {
        if case .scalar(let text) = self { return text }
        return nil
    }

    public var doubleValue: Double? {
        stringValue.flatMap(Double.init)
    }

    public var intValue: Int? {
        stringValue.flatMap(Int.init)
    }

    public var boolValue: Bool? {
        switch stringValue?.lowercased() {
        case "true", "yes": true
        case "false", "no": false
        default: nil
        }
    }

    public var sequenceValue: [YAMLValue]? {
        if case .sequence(let items) = self { return items }
        return nil
    }

    public var mappingValue: [String: YAMLValue]? {
        if case .mapping(let entries) = self { return entries }
        return nil
    }

    public subscript(key: String) -> YAMLValue? {
        mappingValue?[key]
    }
}

/// What the parser refused, and where. The line number is the point of the
/// error: a hand-written canon file is edited by people.
public enum YAMLError: Error, Equatable, CustomStringConvertible {
    case unexpectedIndentation(line: Int)
    case expectedMappingKey(line: Int)
    case malformedFlowCollection(line: Int, reason: String)
    case duplicateKey(String, line: Int)

    public var description: String {
        switch self {
        case .unexpectedIndentation(let line):
            "line \(line): unexpected indentation."
        case .expectedMappingKey(let line):
            "line \(line): expected `key: value`."
        case let .malformedFlowCollection(line, reason):
            "line \(line): malformed inline collection (\(reason))."
        case let .duplicateKey(key, line):
            "line \(line): duplicate key `\(key)`."
        }
    }
}

/// The YAML subset parser. Line-oriented, because the subset is.
public enum YAML {
    public static func parse(_ text: String) throws -> YAMLValue {
        let lines = sourceLines(text)
        guard !lines.isEmpty else { return .mapping([:]) }
        var index = 0
        let value = try parseBlock(lines, &index, indent: lines[0].indent)
        guard index == lines.count else { throw YAMLError.unexpectedIndentation(line: lines[index].number) }
        return value
    }

    // MARK: - Lines

    struct SourceLine {
        var number: Int
        var indent: Int
        var content: String
    }

    static func sourceLines(_ text: String) -> [SourceLine] {
        text.components(separatedBy: "\n").enumerated().compactMap { offset, raw in
            let expanded = raw.replacingOccurrences(of: "\t", with: "    ")
            let indent = expanded.prefix { $0 == " " }.count
            let content = String(expanded.dropFirst(indent))
            guard !content.isEmpty, !content.hasPrefix("#") else { return nil }
            return SourceLine(number: offset + 1, indent: indent, content: stripComment(content))
        }
        .filter { !$0.content.isEmpty }
    }

    /// Trailing comments only outside quotes — a `#` inside a note is a `#`.
    static func stripComment(_ content: String) -> String {
        var quote: Character?
        var previous: Character?
        var result = ""
        for character in content {
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous == nil || previous == " " {
                break
            }
            result.append(character)
            previous = character
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Blocks

    private static func parseBlock(_ lines: [SourceLine], _ index: inout Int, indent: Int) throws -> YAMLValue {
        if lines[index].content.hasPrefix("-") {
            return try parseSequence(lines, &index, indent: indent)
        }
        return try parseMapping(lines, &index, indent: indent)
    }

    private static func parseSequence(_ lines: [SourceLine], _ index: inout Int, indent: Int) throws -> YAMLValue {
        var items: [YAMLValue] = []
        while index < lines.count, lines[index].indent == indent, lines[index].content.hasPrefix("-") {
            let line = lines[index]
            let remainder = String(line.content.dropFirst()).trimmingCharacters(in: .whitespaces)
            index += 1

            if remainder.isEmpty {
                guard index < lines.count, lines[index].indent > indent else {
                    items.append(.scalar(""))
                    continue
                }
                items.append(try parseBlock(lines, &index, indent: lines[index].indent))
                continue
            }

            if remainder.hasPrefix("{") || remainder.hasPrefix("[") {
                items.append(try Flow.parse(remainder, line: line.number))
                continue
            }

            // `- key: value` opens a mapping whose first entry sits on the dash
            // line. Re-indent that entry to where its siblings are and parse the
            // whole thing as one block mapping.
            guard remainder.contains(":") else {
                items.append(.scalar(Scalar.decode(remainder)))
                continue
            }
            let childIndent = indent + 2
            var mappingLines = [SourceLine(number: line.number, indent: childIndent, content: remainder)]
            while index < lines.count, lines[index].indent > indent {
                mappingLines.append(lines[index])
                index += 1
            }
            var mappingIndex = 0
            items.append(try parseMapping(mappingLines, &mappingIndex, indent: childIndent))
        }
        return .sequence(items)
    }

    private static func parseMapping(_ lines: [SourceLine], _ index: inout Int, indent: Int) throws -> YAMLValue {
        var entries: [String: YAMLValue] = [:]
        while index < lines.count, lines[index].indent == indent {
            let line = lines[index]
            guard !line.content.hasPrefix("-") else { break }
            guard let separator = keySeparator(in: line.content) else {
                throw YAMLError.expectedMappingKey(line: line.number)
            }
            let key = Scalar.decode(String(line.content[line.content.startIndex..<separator]))
            let remainder = String(line.content[line.content.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            index += 1
            guard entries[key] == nil else { throw YAMLError.duplicateKey(key, line: line.number) }

            if remainder == ">" || remainder == ">-" || remainder == "|" || remainder == "|-" {
                entries[key] = .scalar(parseBlockScalar(lines, &index, indent: indent, folded: remainder.hasPrefix(">")))
            } else if remainder.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    entries[key] = try parseBlock(lines, &index, indent: lines[index].indent)
                } else if index < lines.count, lines[index].indent == indent, lines[index].content.hasPrefix("-") {
                    entries[key] = try parseSequence(lines, &index, indent: indent)
                } else {
                    entries[key] = .scalar("")
                }
            } else if remainder.hasPrefix("{") || remainder.hasPrefix("[") {
                entries[key] = try Flow.parse(remainder, line: line.number)
            } else {
                entries[key] = .scalar(Scalar.decode(remainder))
            }
        }
        return .mapping(entries)
    }

    /// The `:` that ends the key: the first one followed by a space or the end
    /// of the line, and not inside quotes. `note: 8:00 sharp` keeps its colon.
    static func keySeparator(in content: String) -> String.Index? {
        var quote: Character?
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let next = content.index(after: index)
                if next == content.endIndex || content[next] == " " { return index }
            }
            index = content.index(after: index)
        }
        return nil
    }

    /// Folded (`>`) scalars join their lines with a space and turn a blank line
    /// into a paragraph break; literal (`|`) scalars keep their newlines.
    private static func parseBlockScalar(
        _ lines: [SourceLine],
        _ index: inout Int,
        indent: Int,
        folded: Bool
    ) -> String {
        var pieces: [String] = []
        while index < lines.count, lines[index].indent > indent {
            pieces.append(lines[index].content)
            index += 1
        }
        return pieces.joined(separator: folded ? " " : "\n")
    }
}

/// Inline `{…}` and `[…]`, which is how the bounding boxes and tag lists in
/// `data/cities.yml` are written.
enum Flow {
    static func parse(_ text: String, line: Int) throws -> YAMLValue {
        var scanner = Scanner(text: Array(text), line: line)
        let value = try scanner.parseValue()
        scanner.skipWhitespace()
        guard scanner.isAtEnd else {
            throw YAMLError.malformedFlowCollection(line: line, reason: "trailing characters")
        }
        return value
    }

    struct Scanner {
        let text: [Character]
        let line: Int
        var index = 0

        var isAtEnd: Bool { index >= text.count }

        mutating func skipWhitespace() {
            while index < text.count, text[index] == " " { index += 1 }
        }

        mutating func parseValue() throws -> YAMLValue {
            skipWhitespace()
            guard index < text.count else {
                throw YAMLError.malformedFlowCollection(line: line, reason: "empty value")
            }
            switch text[index] {
            case "{": return try parseMapping()
            case "[": return try parseSequence()
            default: return .scalar(Scalar.decode(try parseScalarText()))
            }
        }

        private mutating func parseMapping() throws -> YAMLValue {
            index += 1
            var entries: [String: YAMLValue] = [:]
            skipWhitespace()
            if index < text.count, text[index] == "}" { index += 1; return .mapping(entries) }
            while true {
                skipWhitespace()
                let key = Scalar.decode(try parseScalarText(stoppingAtColon: true))
                skipWhitespace()
                guard index < text.count, text[index] == ":" else {
                    throw YAMLError.malformedFlowCollection(line: line, reason: "expected `:` after \(key)")
                }
                index += 1
                guard entries[key] == nil else { throw YAMLError.duplicateKey(key, line: line) }
                entries[key] = try parseValue()
                skipWhitespace()
                guard index < text.count else {
                    throw YAMLError.malformedFlowCollection(line: line, reason: "unclosed `{`")
                }
                if text[index] == "," { index += 1; continue }
                if text[index] == "}" { index += 1; return .mapping(entries) }
                throw YAMLError.malformedFlowCollection(line: line, reason: "expected `,` or `}`")
            }
        }

        private mutating func parseSequence() throws -> YAMLValue {
            index += 1
            var items: [YAMLValue] = []
            skipWhitespace()
            if index < text.count, text[index] == "]" { index += 1; return .sequence(items) }
            while true {
                items.append(try parseValue())
                skipWhitespace()
                guard index < text.count else {
                    throw YAMLError.malformedFlowCollection(line: line, reason: "unclosed `[`")
                }
                if text[index] == "," { index += 1; continue }
                if text[index] == "]" { index += 1; return .sequence(items) }
                throw YAMLError.malformedFlowCollection(line: line, reason: "expected `,` or `]`")
            }
        }

        private mutating func parseScalarText(stoppingAtColon: Bool = false) throws -> String {
            skipWhitespace()
            guard index < text.count else {
                throw YAMLError.malformedFlowCollection(line: line, reason: "expected a value")
            }
            if text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index += 1
                var result = ""
                while index < text.count, text[index] != quote {
                    result.append(text[index])
                    index += 1
                }
                guard index < text.count else {
                    throw YAMLError.malformedFlowCollection(line: line, reason: "unterminated quote")
                }
                index += 1
                return String(quote) + result + String(quote)
            }
            var result = ""
            while index < text.count {
                let character = text[index]
                if character == "," || character == "}" || character == "]" { break }
                if stoppingAtColon, character == ":" { break }
                result.append(character)
                index += 1
            }
            return result.trimmingCharacters(in: .whitespaces)
        }
    }
}

enum Scalar {
    /// Strips matching quotes and the `~`/`null` spelling of nothing.
    static func decode(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2 {
            let first = trimmed.first
            let last = trimmed.last
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                return String(trimmed.dropFirst().dropLast())
            }
        }
        if trimmed == "~" || trimmed == "null" { return "" }
        return trimmed
    }
}
