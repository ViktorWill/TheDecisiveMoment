import Foundation
import TDMCore

/// Package metadata. `generator` in every bundle carries this string, so a diff
/// of a regenerated city shows which build wrote it.
public enum SpotForge {
    public static let version = "0.1.0"
    public static var generator: String { "spotforge \(version)" }
}
