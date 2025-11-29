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
    case night = "kl 00-06\nNatt"
    case morning = "kl 06-12\nMorgon"
    case day = "kl 12-18\nDag"
    case evening = "kl 18-24\nKväll"
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
