// LoopFollow
// AggregatedStatsViewModel.swift

import Combine
import Foundation

class AggregatedStatsViewModel: ObservableObject {
    var simpleStats: SimpleStatsViewModel
    var agpStats: AGPViewModel
    var griStats: GRIViewModel
    var tirStats: TIRViewModel
    var sickDayStats: (count: Int, percent: Double) {
        let calendar = Calendar.current
        let entries = Storage.shared.sickDayHistory

        let includedDays: Set<Date>

        if dataService.isTodayOnly {
            includedDays = [calendar.startOfDay(for: Date())]
        } else if let custom = dataService.customInterval {
            let startDay = calendar.startOfDay(for: custom.start)
            let endExclusiveDay = calendar.startOfDay(for: custom.end)
            let endInclusiveDay = calendar.date(byAdding: .day, value: -1, to: endExclusiveDay) ?? startDay

            let dayCount = max((calendar.dateComponents([.day], from: startDay, to: endInclusiveDay).day ?? 0) + 1, 1)
            includedDays = Set((0..<dayCount).compactMap {
                calendar.date(byAdding: .day, value: $0, to: startDay)
            })
        } else {
            let days = max(dataService.daysToAnalyze, 1)
            let today = calendar.startOfDay(for: Date())

            if days == 1 {
                // "1 d" i din statistik slutar på igår
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                includedDays = [yesterday]
            } else {
                let endDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
                includedDays = Set((0..<days).compactMap {
                    calendar.date(byAdding: .day, value: $0, to: startDay)
                })
            }
        }

        guard !includedDays.isEmpty else { return (0, 0) }

        let sickCount = entries.filter { entry in
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: entry.date))
            return includedDays.contains(day)
        }.count

        let totalDays = includedDays.count
        let percent = totalDays > 0 ? (Double(sickCount) / Double(totalDays)) * 100.0 : 0.0

        return (sickCount, percent)
    }

    let dataService: StatsDataService

    init(mainViewController: MainViewController?) {
        dataService = StatsDataService(mainViewController: mainViewController)
        simpleStats = SimpleStatsViewModel(dataService: dataService)
        agpStats = AGPViewModel(dataService: dataService)
        griStats = GRIViewModel(dataService: dataService)
        tirStats = TIRViewModel(dataService: dataService)
        let savedPeriod = UserDefaults.standard.object(forKey: "AggregatedStatsSelectedPeriod") as? Int ?? 14
        applyPeriodSettings(savedPeriod)
        //calculateStats()
    }

    private func applyPeriodSettings(_ days: Int) {
        if days == 0 {
            // "Idag" – use only data from midnight to now, but fetch 1 dag bakåt om det behövs
            dataService.isTodayOnly = true
            dataService.isOneDayOnly = false
            dataService.daysToAnalyze = 1
        } else {
            // Alla andra perioder (1 d, 7 d, 14 d, 30 d, 90 d) behandlas som rullande N×24h
            dataService.isTodayOnly = false
            dataService.isOneDayOnly = false
            dataService.daysToAnalyze = max(days, 1)
        }
    }

    func calculateStats() {
        dataService.clearBGCache()

        simpleStats.calculateStats()
        agpStats.calculateAGP()
        griStats.calculateGRI()
        tirStats.calculateTIR()
    }

    func updatePeriod(
        _ days: Int,
        startDate: Date? = nil,
        endDate: Date? = nil,
        forceReload: Bool = false,
        backfillDays: Int? = nil,
        completion: @escaping () -> Void = {}
    ) {
        applyPeriodSettings(days)

        // Konfigurera ev. anpassat intervall
        if days == 0 {
            dataService.customInterval = nil
        } else if let s = startDate, let e = endDate {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: s)
            let endDayStart = calendar.startOfDay(for: e)
            if let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDayStart) {
                dataService.customInterval = DateInterval(start: start, end: endExclusive)
            } else {
                dataService.customInterval = nil
            }
        } else {
            dataService.customInterval = nil
        }

        let shouldForceReload = forceReload

        if shouldForceReload {
            dataService.reloadAllData(
                backfillDays: backfillDays,
                onProgress: {},
                completion: {
                    self.calculateStats()
                    completion()
                }
            )
        } else {
            dataService.ensureDataAvailable(
                onProgress: {},
                completion: {
                    self.calculateStats()
                    completion()
                }
            )
        }
    }

    var gmi: Double? { simpleStats.gmi }
    var avgGlucose: Double? { simpleStats.avgGlucose }
    var stdDeviation: Double? { simpleStats.stdDeviation }
    var coefficientOfVariation: Double? { simpleStats.coefficientOfVariation }
    var totalDailyDose: Double? { simpleStats.totalDailyDose }
    var programmedBasal: Double? { simpleStats.programmedBasal }
    var actualBasal: Double? { simpleStats.actualBasal }
    var avgBolus: Double? { simpleStats.avgBolus }
    var avgCarbs: Double? { simpleStats.avgCarbs }
    var agpData: [AGPDataPoint] { agpStats.agpData }
    var gri: Double? { griStats.gri }
    var griHypoComponent: Double? { griStats.griHypoComponent }
    var griHyperComponent: Double? { griStats.griHyperComponent }
    var griDataPoints: [(date: Date, value: Double)] { griStats.griDataPoints }
}
