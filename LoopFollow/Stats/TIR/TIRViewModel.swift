// LoopFollow
// TIRViewModel.swift

import Combine
import Foundation

class TIRViewModel: ObservableObject {
    @Published var tirData: [TIRDataPoint] = []
    @Published var showTITR: Bool
    @Published var averageDayMinutes: Double = 24 * 60

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
    }

    func toggleTIRMode() {
        showTITR.toggle()
        Storage.shared.showTITR.value = showTITR
        calculateTIR()
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
}
