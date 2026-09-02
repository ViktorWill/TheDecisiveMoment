import Foundation
import TDMCore

/// What a run was asked to do. No work is performed yet — the fetch, merge,
/// score, trim and write stages described in `docs/SPOTFORGE.md` land in M4.
struct Plan: Sendable {
    enum Scope: Sendable {
        case cities([String])
        case allCities
    }

    var scope: Scope
    var outputDirectory: String
}

enum ArgumentError: Error, CustomStringConvertible {
    case missingValue(option: String)
    case unknownOption(String)
    case noScope
    case conflictingScope

    var description: String {
        switch self {
        case .missingValue(let option):
            "\(option) needs a value."
        case .unknownOption(let option):
            "Unknown option \(option)."
        case .noScope:
            "Nothing to build: pass --city <id> (repeatable) or --all."
        case .conflictingScope:
            "--city and --all are mutually exclusive."
        }
    }
}

let usage = """
Usage: spotforge --city <id> [--city <id>…] | --all [--out <directory>]

  --city <id>   Build one city, by the id declared in data/cities.yml.
  --all         Build every declared city.
  --out <dir>   Where bundles are written. Default: bundles/v1.

spotforge runs at build time only. The app never calls a spot data source.
"""

func parse(_ arguments: some Sequence<String>) throws -> Plan {
    var cities: [String] = []
    var all = false
    var outputDirectory = "bundles/v1"

    let remaining = Array(arguments)
    var index = 0
    while index < remaining.count {
        let argument = remaining[index]
        index += 1
        switch argument {
        case "--city":
            guard index < remaining.count else { throw ArgumentError.missingValue(option: "--city") }
            cities.append(remaining[index])
            index += 1
        case "--out":
            guard index < remaining.count else { throw ArgumentError.missingValue(option: "--out") }
            outputDirectory = remaining[index]
            index += 1
        case "--all":
            all = true
        default:
            throw ArgumentError.unknownOption(argument)
        }
    }

    if all && !cities.isEmpty { throw ArgumentError.conflictingScope }
    if !all && cities.isEmpty { throw ArgumentError.noScope }

    return Plan(scope: all ? .allCities : .cities(cities), outputDirectory: outputDirectory)
}

func describe(_ plan: Plan) -> String {
    let subject = switch plan.scope {
    case .allCities: "every city in data/cities.yml"
    case .cities(let ids): ids.joined(separator: ", ")
    }

    return """
    spotforge plan
      cities:  \(subject)
      out:     \(plan.outputDirectory)
      schema:  v\(TDMCore.bundleSchemaVersion)
      stages:  fetch → normalise → merge → score → trim → write (gz + sha256)

    Nothing was done: the pipeline is not implemented yet.
    """
}

do {
    let plan = try parse(CommandLine.arguments.dropFirst())
    print(describe(plan))
} catch let error as ArgumentError {
    FileHandle.standardError.write(Data("spotforge: \(error.description)\n\n\(usage)\n".utf8))
    exit(2)
}
