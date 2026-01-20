// LoopFollow
// TIRViewModel.swift

import Combine
import Foundation

enum TIRGraphMode {
    case hours
    case weekdays
}

class TIRViewModel: ObservableObject {
    @Published var tirData: [TIRDataPoint] = []
    @Published var showTITR: Bool
    @Published var averageDayMinutes: Double = 24 * 60
    @Published var graphMode: TIRGraphMode = .hours
    @Published var tirWeekdayData: [TIRDataPoint] = []

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
        showTITR = Storage.shared.showTITR.value
        calculateTIR()
    }

    func calculateTIR() {
        let bgData = dataService.getBGData()
        tirData = TIRCalculator.calculate(bgData: bgData, useTightRange: showTITR)
        averageDayMinutes = Self.computeAverageDayMinutes(bgData: bgData)
        tirWeekdayData = Self.calculateWeekdayWeekendTIR(bgData: bgData, useTightRange: showTITR)
    }

    func toggleTIRMode() {
        showTITR.toggle()
        Storage.shared.showTITR.value = showTITR
        calculateTIR()
    }

    func toggleGraphMode() {
        graphMode = (graphMode == .hours) ? .weekdays : .hours
    }

    /// Computes how many minutes the "average" row should represent.
    /// - If all readings are from today and within the same calendar day, we use
    ///   elapsed minutes from today's midnight to the last reading (clamped to now).
    /// - Otherwise, we assume a full 24-hour day.
    private static func computeAverageDayMinutes(bgData: [ShareGlucoseData]) -> Double {
        guard !bgData.isEmpty else { return 24 * 60 }
        
        // Normalize timestamps similar to TIRCalculator.normalizeAndDedupe (ms vs s),
        // but we don't need to dedupe for span calculation.
        let timestamps: [Double] = bgData.map { r in
            if r.date > 10_000_000_000 {
                return r.date / 1000.0
            } else {
                return r.date
            }
        }
        
        guard let minTs = timestamps.min(), let maxTs = timestamps.max() else {
            return 24 * 60
        }
        
        let calendar = Calendar.current
        let minDate = Date(timeIntervalSince1970: minTs)
        let maxDate = Date(timeIntervalSince1970: maxTs)
        
        // Om alla värden ligger inom samma kalenderdag och den dagen är idag,
        // basera "per dag"-tiden på hur mycket av dagens dygn som förflutit.
        if calendar.isDate(minDate, inSameDayAs: maxDate), calendar.isDateInToday(maxDate) {
            let startOfDay = calendar.startOfDay(for: maxDate)
            let now = Date()
            let effectiveEnd = min(now, maxDate)
            let seconds = max(effectiveEnd.timeIntervalSince(startOfDay), 0)
            // Minst 1 minut så att extremt korta dataset inte ger 0h 0m överallt.
            return max(seconds / 60.0, 1.0)
        }
        
        // Övriga fall: anta ett helt dygn.
        return 24 * 60
    }

    /// Computes TIR for Weekdays (Mon–Fri) vs Weekends (Sat–Sun) from the current bgData window.
    private static func calculateWeekdayWeekendTIR(bgData: [ShareGlucoseData], useTightRange: Bool) -> [TIRDataPoint] {
        let cal = Calendar.current

        // Split into weekdays/weekends using the timestamp on ShareGlucoseData.
        var weekdays: [ShareGlucoseData] = []
        var weekends: [ShareGlucoseData] = []
        var schooldays: [ShareGlucoseData] = []
        weekdays.reserveCapacity(bgData.count)
        weekends.reserveCapacity(bgData.count)
        schooldays.reserveCapacity(bgData.count)

        for r in bgData {
            // Normalize timestamp (ms vs s) like elsewhere
            let ts: TimeInterval = (r.date > 10_000_000_000) ? (r.date / 1000.0) : r.date
            let date = Date(timeIntervalSince1970: ts)
            let hour = cal.component(.hour, from: date)

            if cal.isDateInWeekend(date) {
                weekends.append(r)
            } else {
                // Mon–Fre
                weekdays.append(r)
                // Skoldagar = vardagar kl 08–16
                if hour >= 8 && hour < 16 {
                    schooldays.append(r)
                }
            }
        }

        func zeroPoint(_ period: TIRPeriod) -> TIRDataPoint {
            TIRDataPoint(period: period, veryLow: 0, low: 0, inRange: 0, high: 0, veryHigh: 0)
        }

        func averagePoint(from data: [ShareGlucoseData], period: TIRPeriod) -> TIRDataPoint {
            let points = TIRCalculator.calculate(bgData: data, useTightRange: useTightRange)
            if let avg = points.first(where: { $0.period == .average }) {
                // Re-label the average point to the requested period (weekdays/weekends/schooldays)
                return TIRDataPoint(period: period,
                                    veryLow: avg.veryLow,
                                    low: avg.low,
                                    inRange: avg.inRange,
                                    high: avg.high,
                                    veryHigh: avg.veryHigh)
            }
            return zeroPoint(period)
        }

        // Overall average (same as the existing graph)
        let overallAvg = averagePoint(from: bgData, period: .average)
        let weekdaysAvg = averagePoint(from: weekdays, period: .weekdays)
        let schooldaysAvg = averagePoint(from: schooldays, period: .schooldays)
        let weekendsAvg = averagePoint(from: weekends, period: .weekends)

        return [overallAvg, weekdaysAvg, schooldaysAvg, weekendsAvg]
    }
}
