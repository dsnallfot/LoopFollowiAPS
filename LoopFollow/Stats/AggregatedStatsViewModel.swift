// LoopFollow
// AggregatedStatsViewModel.swift

import Combine
import Foundation

class AggregatedStatsViewModel: ObservableObject {
    var simpleStats: SimpleStatsViewModel
    var agpStats: AGPViewModel
    var griStats: GRIViewModel
    var tirStats: TIRViewModel

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
