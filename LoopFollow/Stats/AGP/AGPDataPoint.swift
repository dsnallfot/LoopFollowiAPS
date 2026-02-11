// AGPDataPoint.swift

import Foundation
import SwiftUI

struct AGPDataPoint {
    let timeOfDay: Int
    let p5: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
}

// MARK: - Day-by-day overlay models

struct AGPDayPoint {
    /// Hours since midnight (0–24)
    let xHour: Double
    /// Stored in mg/dL (chart axis is fixed 0–360 mg/dL)
    let yMgdl: Double
}

struct AGPDaySeries {
    let dayStart: Date
    /// Calendar weekday: 1=Monday ... 7=Sunday
    let weekday: Int
    let points: [AGPDayPoint]
}

enum AGPWeekday: Int, CaseIterable {
    // ISO / Swedish weekday order: 1=Monday ... 7=Sunday
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var shortSv: String {
        switch self {
        case .monday: return "Må"
        case .tuesday: return "Ti"
        case .wednesday: return "On"
        case .thursday: return "To"
        case .friday: return "Fr"
        case .saturday: return "Lö"
        case .sunday: return "Sö"
        }
    }

    var color: Color {
        // 7 tydliga färger (en per veckodag)
        switch self {
        case .monday: return .red
        case .tuesday: return .orange
        case .wednesday: return .yellow
        case .thursday: return .green
        case .friday: return .teal
        case .saturday: return .blue
        case .sunday: return .purple
        }
    }

    static func from(isoWeekday: Int) -> AGPWeekday {
        AGPWeekday(rawValue: isoWeekday) ?? .monday
    }
}
