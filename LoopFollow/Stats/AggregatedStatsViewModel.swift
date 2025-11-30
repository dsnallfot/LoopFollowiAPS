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
    }

    func calculateStats() {
        simpleStats.calculateStats()
        agpStats.calculateAGP()
        griStats.calculateGRI()
        tirStats.calculateTIR()
    }

    func updatePeriod(_ days: Int, forceReload: Bool = false, completion: @escaping () -> Void = {}) {
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

        if forceReload {
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
