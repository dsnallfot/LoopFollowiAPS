// LoopFollow
// AGPViewModel.swift

import Combine
import Foundation

class AGPViewModel: ObservableObject {
    @Published var agpData: [AGPDataPoint] = []

    enum DisplayMode {
        case agp
        case dayByDay
    }

    @Published var displayMode: DisplayMode = .agp
    @Published var dayByDaySeries: [AGPDaySeries] = []
    @Published var guardrailCrossings: AGPGuardrailCrossings = .empty
    @Published private(set) var currentInterval: DateInterval =
        DateInterval(start: Date().addingTimeInterval(-14 * 24 * 60 * 60), end: Date())

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
        calculateAGP()
    }

    var canToggleDayByDay: Bool {
        let maxSeconds: TimeInterval = 14 * 24 * 60 * 60
        return currentInterval.duration <= (maxSeconds + 60) // liten slack
    }

    func calculateAGP() {
        let interval = dataService.currentStatsInterval()
        currentInterval = interval

        let bgData = dataService.getBGData(in: interval)
        agpData = AGPCalculator.calculate(bgData: bgData)

        if canToggleDayByDay {
            dayByDaySeries = AGPDayByDayCalculator.calculate(bgData: bgData, in: interval)
            guardrailCrossings = AGPDayByDayCalculator.calculateGuardrailCrossings(series: dayByDaySeries)
        } else {
            dayByDaySeries = []
            guardrailCrossings = .empty
            if displayMode == .dayByDay {
                displayMode = .agp
            }
        }
    }

    func toggleDisplayMode() {
        guard canToggleDayByDay else {
            displayMode = .agp
            return
        }
        displayMode = (displayMode == .agp) ? .dayByDay : .agp
    }

    func enforceModeConstraints() {
        // Endast enforce:a mode. Själva beräkningen triggas av AggregatedStatsViewModel.calculateStats().
        if !canToggleDayByDay {
            displayMode = .agp
        }
    }
}
