// LoopFollow
// TIRDataPoint.swift

import Foundation

struct TIRDataPoint {
    let period: TIRPeriod
    let veryLow: Double
    let low: Double
    let inRange: Double
    let high: Double
    let veryHigh: Double
}

enum TIRPeriod: String, CaseIterable {
    case night = "kl 00-08\nNatt"
    case day = "kl 08-16\nDag"
    case evening = "kl 16-24\nKväll"
    case weekdays = "kl 00-24\nVardagar"
    case schooldays = "kl 08-16\nSkoldagar"
    case weekends = "kl 00-24\nHelg"
    case average = "MEDEL"

    /// Central display order used by charts and tables
    static var displayOrder: [TIRPeriod] {
        [.average, .night, .day, .evening]
    }

    static var weekdayDisplayOrder: [TIRPeriod] {
        [.average, .weekdays, .schooldays, .weekends]
    }

    var isAverage: Bool {
        self == .average
    }

    var hourRange: (start: Int, end: Int)? {
        switch self {
        case .night:
            return (0, 8)
        case .day:
            return (8, 16)
        case .evening:
            return (16, 24)
        default:
            return nil
        }
    }
}
