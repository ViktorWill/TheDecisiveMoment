import Foundation

/// The command line, parsed. Kept out of the executable target so it can be
/// tested: an argument bug is a build that quietly did the wrong thing.
public enum CommandLineInterface {
    public enum Command: Sendable {
        case build(BuildRequest)
        case validate(directory: String)
    }

    public static let usage = """
    Usage:
      spotforge build --city <id> [--city <id>…] | --all [options]
      spotforge validate [<directory>]

    Build options:
      --out <dir>        Where bundles are written. Default: bundles/v1.
      --cities <path>    City declarations. Default: data/cities.yml.
      --curated <dir>    Curated canon files. Default: data/curated.
      --cache <dir>      Response cache. Default: .cache.
      --fixtures <dir>   Build from recorded responses; touches no network.
      --report           Print the per-source summary.
      --strict           Exit non-zero when a source returned nothing or the
                         bundle missed its size budget.
      --size-budget <n>  Compressed ceiling per city. Plain bytes, or a KB/MB
                         suffix: 8MB, 1536KB, 8388608 are all accepted.
      --no-photos        Skip the representative-image pass.

    spotforge runs at build time only. The app never calls a spot data source.
    """

    public static func parse(_ arguments: some Sequence<String>) throws -> Command {
        var remaining = Array(arguments)
        guard let verb = remaining.first else { throw ArgumentError.noCommand }
        remaining.removeFirst()

        switch verb {
        case "build":
            return .build(try parseBuild(remaining))
        case "validate":
            let directory = remaining.first { !$0.hasPrefix("--") } ?? "bundles/v1"
            return .validate(directory: directory)
        case "--help", "-h", "help":
            throw ArgumentError.helpRequested
        default:
            throw ArgumentError.unknownCommand(verb)
        }
    }

    private static func parseBuild(_ arguments: [String]) throws -> BuildRequest {
        var cities: [String] = []
        var all = false
        var request = BuildRequest(scope: .allCities)

        var index = 0
        func value(for option: String) throws -> String {
            guard index < arguments.count else { throw ArgumentError.missingValue(option: option) }
            defer { index += 1 }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--city": cities.append(try value(for: "--city"))
            case "--all": all = true
            case "--out": request.outputDirectory = try value(for: "--out")
            case "--cities": request.citiesPath = try value(for: "--cities")
            case "--curated": request.curatedDirectory = try value(for: "--curated")
            case "--cache": request.cacheDirectory = try value(for: "--cache")
            case "--fixtures": request.fixturesDirectory = try value(for: "--fixtures")
            case "--report": request.printsReport = true
            case "--strict": request.strict = true
            case "--no-photos": request.fetchesPhotos = false
            case "--size-budget":
                let text = try value(for: "--size-budget")
                guard let bytes = byteCount(text) else {
                    throw ArgumentError.invalidValue(option: "--size-budget", value: text)
                }
                request.sizeBudgetBytes = bytes
            default: throw ArgumentError.unknownOption(argument)
            }
        }

        if all && !cities.isEmpty { throw ArgumentError.conflictingScope }
        if !all && cities.isEmpty { throw ArgumentError.noScope }
        request.scope = all ? .allCities : .cities(cities)
        return request
    }

    /// A byte count written the way a person would: a budget at this scale is
    /// unreadable in bytes, and `8MB` and `8388608` should mean the same thing.
    /// Nil for anything that is not a positive count, so a typo is refused
    /// rather than silently becoming a budget of zero.
    static func byteCount(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        // MB before KB before B: every suffix here ends in "B".
        for (suffix, multiplier) in [("MB", 1024 * 1024), ("KB", 1024), ("B", 1)]
        where trimmed.hasSuffix(suffix) {
            let number = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            guard let value = Int(number), value > 0 else { return nil }
            let (bytes, overflowed) = value.multipliedReportingOverflow(by: multiplier)
            return overflowed ? nil : bytes
        }
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }
}

public enum ArgumentError: Error, Equatable, CustomStringConvertible {
    case noCommand
    case unknownCommand(String)
    case helpRequested
    case missingValue(option: String)
    case unknownOption(String)
    case noScope
    case conflictingScope
    case invalidValue(option: String, value: String)

    public var description: String {
        switch self {
        case .noCommand:
            "Nothing to do: pass `build` or `validate`."
        case .unknownCommand(let verb):
            "Unknown command `\(verb)`."
        case .helpRequested:
            "" // The caller prints the usage.
        case .missingValue(let option):
            "\(option) needs a value."
        case .unknownOption(let option):
            "Unknown option \(option)."
        case .noScope:
            "Nothing to build: pass --city <id> (repeatable) or --all."
        case .conflictingScope:
            "--city and --all are mutually exclusive."
        case let .invalidValue(option, value):
            "\(option) does not accept `\(value)`. Expected a positive byte count, optionally suffixed KB or MB."
        }
    }
}
