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
    case night = "Natt\n00-06"
    case morning = "Morgon\n06-12"
    case day = "Dag\n12-18"
    case evening = "Kväll\n18-24"
    case average = "MEDEL"

    var hourRange: (start: Int, end: Int)? {
        switch self {
        case .night:
            return (0, 6)
        case .morning:
            return (6, 12)
        case .day:
            return (12, 18)
        case .evening:
            return (18, 24)
        case .average:
            return nil
        }
    }
}
