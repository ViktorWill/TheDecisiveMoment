import Foundation
import Testing
@testable import TDMLight

/// A UTC instant, built without a calendar so the test suite stays on the
/// cross-platform Foundation subset. Days-from-civil, Howard Hinnant's algorithm.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    let days = era * 146_097 + dayOfEra - 719_468
    let seconds = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second)
    return Date(timeIntervalSince1970: seconds)
}
