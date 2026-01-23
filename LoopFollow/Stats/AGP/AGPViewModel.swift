// LoopFollow
// AGPViewModel.swift

import Combine
import Foundation

class AGPViewModel: ObservableObject {
    @Published var agpData: [AGPDataPoint] = []

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
        calculateAGP()
    }

    func calculateAGP() {
        // Använd samma analysfönster som övrig Aggregated Stats-logik
        let interval = dataService.currentStatsInterval()
        let bgData = dataService.getBGData(in: interval)
        agpData = AGPCalculator.calculate(bgData: bgData)
    }
}
