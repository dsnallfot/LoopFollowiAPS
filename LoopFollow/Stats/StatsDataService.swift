// LoopFollow
// StatsDataService.swift


import Foundation

// Enkel persistent cache för statistikdata (bolus, SMB, kolhydrater, basal).
// Lagrar upp till 90 dagar och används för att minska Nightscout-förfrågningar.
private class StatsCacheManager {
    static let shared = StatsCacheManager()
    private init() {}

    private struct CachedBolus: Codable {
        let value: Double
        let date: Double
        let sgv: Int
    }

    private struct CachedCarb: Codable {
        let value: Double
        let date: Double
        let sgv: Int
        let absorptionTime: Int
        let foodType: String?
        let fat: Double
        let protein: Double
    }

    private struct CachedBasal: Codable {
        let basalRate: Double
        let date: Double
    }

    private struct CachedBG: Codable {
        let sgv: Int
        let date: Double
        let direction: String?
    }

    private struct CachedBGCheck: Codable {
        let date: Double
    }

    private struct Cache: Codable {
        let lastUpdated: Date
        let bg: [CachedBG]
        let bgChecks: [CachedBGCheck]
        let bolus: [CachedBolus]
        let smb: [CachedBolus]
        let carbs: [CachedCarb]
        let basal: [CachedBasal]
    }

    private var cacheURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("StatsCache.json")
    }

    /// Läs in cache från disk och applicera på MainViewController (endast de senaste 90 dagarna).
    func loadInto(mainVC: MainViewController) {
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let cache = try decoder.decode(Cache.self, from: data)

            let now = Date()
            let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970

            let bg = cache.bg
                .filter { $0.date >= cutoff }
                .map { ShareGlucoseData(sgv: $0.sgv, date: $0.date, direction: $0.direction) }

            let bolus = cache.bolus
                .filter { $0.date >= cutoff }
                .map { MainViewController.bolusGraphStruct(value: $0.value, date: $0.date, sgv: $0.sgv) }

            let smb = cache.smb
                .filter { $0.date >= cutoff }
                .map { MainViewController.bolusGraphStruct(value: $0.value, date: $0.date, sgv: $0.sgv) }

            let carbs = cache.carbs
                .filter { $0.date >= cutoff }
                .map {
                    MainViewController.carbGraphStruct(
                        value: $0.value,
                        date: $0.date,
                        sgv: $0.sgv,
                        absorptionTime: $0.absorptionTime,
                        foodType: $0.foodType ?? "",
                        fat: $0.fat,
                        protein: $0.protein
                    )
                }

            let basal = cache.basal
                .filter { $0.date >= cutoff }
                .map { MainViewController.basalGraphStruct(basalRate: $0.basalRate, date: $0.date) }

            let bgChecks = cache.bgChecks
                .filter { $0.date >= cutoff }
                .map { $0.date }

            // Skriv över befintlig statsdata med cachen (vi utgår från att MainViewController precis initierats)
            mainVC.statsBGData = bg
            mainVC.statsBGCheckData = bgChecks
            mainVC.statsBolusData = bolus
            mainVC.statsSMBData = smb
            mainVC.statsCarbData = carbs
            mainVC.statsBasalData = basal

            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - cache loaded: bg=\(bg.count), bgChecks=\(bgChecks.count), bolus=\(bolus.count), smb=\(smb.count), carbs=\(carbs.count), basal=\(basal.count)",
                isDebug: true
            )
        } catch {
            // Ingen cache ännu eller så gick det fel att läsa – ignoreras tyst.
            LogManager.shared.log(category: .analysis, message: "StatsCacheManager - no cache loaded (\(error.localizedDescription))", isDebug: true)
        }
    }

    /// Spara aktuella stats-arrayer från MainViewController till disk (endast de senaste 90 dagarna).
    func saveFrom(mainVC: MainViewController) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970

        let bg = mainVC.statsBGData
            .filter { $0.date >= cutoff }
            .map { CachedBG(sgv: $0.sgv, date: $0.date, direction: $0.direction) }

        let bgChecks = mainVC.statsBGCheckData
            .filter { $0 >= cutoff }
            .map { CachedBGCheck(date: $0) }

        let bolus = mainVC.statsBolusData
            .filter { $0.date >= cutoff }
            .map { CachedBolus(value: $0.value, date: $0.date, sgv: $0.sgv) }

        let smb = mainVC.statsSMBData
            .filter { $0.date >= cutoff }
            .map { CachedBolus(value: $0.value, date: $0.date, sgv: $0.sgv) }

        let carbs = mainVC.statsCarbData
            .filter { $0.date >= cutoff }
            .map {
                CachedCarb(
                    value: $0.value,
                    date: $0.date,
                    sgv: $0.sgv,
                    absorptionTime: $0.absorptionTime,
                    foodType: $0.foodType,
                    fat: $0.fat,
                    protein: $0.protein
                )
            }

        let basal = mainVC.statsBasalData
            .filter { $0.date >= cutoff }
            .map { CachedBasal(basalRate: $0.basalRate, date: $0.date) }

        let cache = Cache(
            lastUpdated: now,
            bg: bg,
            bgChecks: bgChecks,
            bolus: bolus,
            smb: smb,
            carbs: carbs,
            basal: basal
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - cache saved: bg=\(bg.count), bgChecks=\(bgChecks.count), bolus=\(bolus.count), smb=\(smb.count), carbs=\(carbs.count), basal=\(basal.count)",
                isDebug: true
            )
        } catch {
            LogManager.shared.log(category: .analysis, message: "StatsCacheManager - failed to save cache: \(error.localizedDescription)", isDebug: true)
        }
    }
}

class StatsDataService {
    weak var mainViewController: MainViewController?

    var daysToAnalyze: Int = 14
    var isTodayOnly: Bool = false
    var isOneDayOnly: Bool = false
    private let dataFetcher: StatsDataFetcher
    private let maxStatsDays: Int = 90
    
    struct DailyBasalStat {
        let dayStart: Date
        let totalUnits: Double
    }

    init(mainViewController: MainViewController?) {
        self.mainViewController = mainViewController
        dataFetcher = StatsDataFetcher(mainViewController: mainViewController)

        // Ladda ev. cache direkt in i MainViewController när tjänsten skapas
        if let mainVC = mainViewController {
            StatsCacheManager.shared.loadInto(mainVC: mainVC)
        }
    }

    func ensureDataAvailable(onProgress: @escaping () -> Void, completion: @escaping () -> Void) {
        guard let mainVC = mainViewController else {
            completion()
            return
        }

        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }

        let oldestBG = mainVC.statsBGData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestBolus = mainVC.statsBolusData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestCarb = mainVC.statsCarbData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestBasal = mainVC.statsBasalData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date

        let bgDataCount = mainVC.statsBGData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let bolusDataCount = mainVC.statsBolusData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let carbDataCount = mainVC.statsCarbData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let basalDataCount = mainVC.statsBasalData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count

        // Freshness: senaste datapunkt får inte vara äldre än 48 timmar,
        // annars betraktar vi datat som "stale" och triggar en ny 90-dagarsfetch.
        let newestBG = mainVC.statsBGData.max(by: { $0.date < $1.date })?.date
        let newestBolus = mainVC.statsBolusData.max(by: { $0.date < $1.date })?.date
        let newestCarb = mainVC.statsCarbData.max(by: { $0.date < $1.date })?.date
        let newestBasal = mainVC.statsBasalData.max(by: { $0.date < $1.date })?.date

        let newestTreatment = max(newestBolus ?? 0, newestCarb ?? 0, newestBasal ?? 0)

        let freshnessThreshold: TimeInterval = 48 * 60 * 60
        let isBGStale = (newestBG == nil) || (now - (newestBG ?? 0)) > freshnessThreshold
        let isTreatmentStale = (newestTreatment == 0) || (now - newestTreatment) > freshnessThreshold

        LogManager.shared.log(
            category: .analysis,
            message: "StatsDataService - freshness BG: isStale=\(isBGStale), newestBG=\(String(describing: newestBG)); treatments: isStale=\(isTreatmentStale), newestTreatment=\(newestTreatment))",
            isDebug: true
        )

        let minExpectedBGEntries = max(daysToAnalyze * 6, 12)
        let hasEnoughBGData = !isBGStale &&
            bgDataCount >= minExpectedBGEntries &&
            (oldestBG ?? now) <= cutoffTime + (24 * 60 * 60)

        let minExpectedTreatmentEntries = max(daysToAnalyze, 1)
        let hasEnoughTreatmentData = !isTreatmentStale &&
            (bolusDataCount + carbDataCount + basalDataCount) >= minExpectedTreatmentEntries &&
            (oldestBolus ?? now) <= cutoffTime + (24 * 60 * 60) &&
            (oldestCarb ?? now) <= cutoffTime + (24 * 60 * 60) &&
            (oldestBasal ?? now) <= cutoffTime + (24 * 60 * 60)

        if !hasEnoughBGData {
            // Bootstrap med upp till 90 dagars data i cachen.
            dataFetcher.fetchBGData(days: maxStatsDays) {
                DispatchQueue.main.async {
                    onProgress()
                }

                if !hasEnoughTreatmentData {
                    self.dataFetcher.fetchTreatmentsData(days: self.maxStatsDays) {
                        DispatchQueue.main.async {
                            onProgress()
                            StatsCacheManager.shared.saveFrom(mainVC: mainVC)
                            completion()
                        }
                    }
                } else {
                    StatsCacheManager.shared.saveFrom(mainVC: mainVC)
                    completion()
                }
            }
        } else if !hasEnoughTreatmentData {
            // Vi har tillräckligt med BG, men för lite treatments – fyll upp hela 90-dagarsfönstret.
            dataFetcher.fetchTreatmentsData(days: maxStatsDays) {
                DispatchQueue.main.async {
                    onProgress()
                    StatsCacheManager.shared.saveFrom(mainVC: mainVC)
                    completion()
                }
            }
        } else {
            completion()
        }
    }
    
    /// Tvinga omladdning av BG + treatments från Nightscout för nuvarande period (daysToAnalyze).
    /// Används av "Ladda om"-knappen för att garantera att senaste data hämtas.
    func reloadAllData(onProgress: @escaping () -> Void, completion: @escaping () -> Void) {
        // För omladdning vill vi endast hämta de senaste 48 timmarna från Nightscout.
        let recentDays = 2

        dataFetcher.fetchBGData(days: recentDays) {
            DispatchQueue.main.async {
                onProgress()
                self.dataFetcher.fetchTreatmentsData(days: recentDays) {
                    DispatchQueue.main.async {
                        onProgress()
                        if let mainVC = self.mainViewController {
                            StatsCacheManager.shared.saveFrom(mainVC: mainVC)
                        }
                        completion()
                    }
                }
            }
        }
    }

    // Nuvarande analysfönster baserat på isTodayOnly/daysToAnalyze
    func currentStatsInterval() -> DateInterval {
        let nowDate = Date()
        if isTodayOnly {
            let start = Calendar.current.startOfDay(for: nowDate)
            return DateInterval(start: start, end: nowDate)
        } else {
            let end = nowDate
            let start = end.addingTimeInterval(-Double(daysToAnalyze) * 24 * 60 * 60)
            return DateInterval(start: start, end: end)
        }
    }

    // Föregående analysfönster med samma längd som nuvarande
    func previousStatsInterval() -> DateInterval? {
        if isTodayOnly { return nil }
        let current = currentStatsInterval()
        let duration = current.duration
        guard duration > 0 else { return nil }
        let previousEnd = current.start
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return DateInterval(start: previousStart, end: previousEnd)
    }
    
    // MARK: - Interval-baserade getters för trendberäkningar

    func getBGData(in interval: DateInterval) -> [ShareGlucoseData] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return mainVC.statsBGData.filter { $0.date >= start && $0.date <= end }
    }

    func getBGCheckDates(in interval: DateInterval) -> [TimeInterval] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return mainVC.statsBGCheckData.filter { $0 >= start && $0 <= end }
    }

    func getBolusData(in interval: DateInterval) -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return mainVC.statsBolusData.filter { $0.date >= start && $0.date <= end }
    }

    func getSMBData(in interval: DateInterval) -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return mainVC.statsSMBData.filter { $0.date >= start && $0.date <= end }
    }

    func getCarbData(in interval: DateInterval) -> [MainViewController.carbGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        return mainVC.statsCarbData.filter { $0.date >= start && $0.date <= end }
    }

    func getDailyDeliveredBasal(in interval: DateInterval) -> [DailyBasalStat] {
        guard let mainVC = mainViewController else { return [] }

        let startDate = interval.start
        let endDate = interval.end
        let cutoffTime = startDate.timeIntervalSince1970
        let endTime = endDate.timeIntervalSince1970

        // Ta ut basalstege upp till endTime och inkludera sista punkt före start
        let allBasal = mainVC.statsBasalData
            .filter { $0.date <= endTime }
            .sorted { $0.date < $1.date }

        guard !allBasal.isEmpty else { return [] }

        var basalPoints = allBasal.filter { $0.date >= cutoffTime }
        if let lastBeforeStart = allBasal.last(where: { $0.date < cutoffTime }) {
            basalPoints.insert(lastBeforeStart, at: 0)
        }

        guard !basalPoints.isEmpty else { return [] }

        let events: [StatsBasalEngine.BasalChangeEvent] = basalPoints.map {
            StatsBasalEngine.BasalChangeEvent(
                date: Date(timeIntervalSince1970: $0.date),
                rateUph: $0.basalRate
            )
        }

        let sim = StatsBasalEngine.simulateDeliveredBasal(
            events: events,
            in: interval,
            pulseSize: 0.05,
            carryOverUndeliveredBasals: false
        )

        return [DailyBasalStat(dayStart: startDate, totalUnits: sim.totalUnits)]
    }
    
    func getBGData() -> [ShareGlucoseData] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBGData.filter { $0.date >= cutoffTime }
    }
    
    func getBGCheckDates() -> [TimeInterval] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBGCheckData.filter { $0 >= cutoffTime && $0 <= now }
    }

    func getBolusData() -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBolusData.filter { $0.date >= cutoffTime }
    }

    func getSMBData() -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsSMBData.filter { $0.date >= cutoffTime }
    }

    func getCarbData() -> [MainViewController.carbGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsCarbData.filter { $0.date >= cutoffTime && $0.date <= now }
    }

    func getBasalProfile() -> [MainViewController.basalProfileStruct] {
        guard let mainVC = mainViewController else { return [] }
        return mainVC.basalProfile
    }
    
    /*
    func getDailyDeliveredBasal() -> [DailyBasalStat] {
        guard let mainVC = mainViewController else { return [] }
        LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - getDailyDeliveredBasal called. isTodayOnly=\(isTodayOnly), daysToAnalyze=\(daysToAnalyze)", isDebug: true)

        let calendar = Calendar.current
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970

        // Bestäm analysfönster – håll detta i sync med övriga getters
        let endDate: Date = nowDate
        let startDate: Date

        if isTodayOnly {
            // Idag: midnatt → nu
            startDate = calendar.startOfDay(for: nowDate)
        } else {
            // Övriga perioder (1, 7, 14, 30 dagar): rullande fönster bakåt i tid
            startDate = endDate.addingTimeInterval(-Double(daysToAnalyze) * 24 * 60 * 60)
        }
        LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - window start=\(startDate), end=\(endDate)", isDebug: true)

        let cutoffTime = startDate.timeIntervalSince1970
        let endTime = endDate.timeIntervalSince1970

        // 1) Ta ut basalstege inom fönstret
        let basalPoints = mainVC.statsBasalData
            .filter { $0.date >= cutoffTime && $0.date <= endTime }
            .sorted { $0.date < $1.date }

        guard !basalPoints.isEmpty else { return [] }

        // 2) Gör om till BasalChangeEvent (piecewise-constant rate U/h)
        let events: [StatsBasalEngine.BasalChangeEvent] = basalPoints.map {
            StatsBasalEngine.BasalChangeEvent(
                date: Date(timeIntervalSince1970: $0.date),
                rateUph: $0.basalRate
            )
        }

        // 3) Simulera levererad basal med StatsBasalEngine
        var results: [DailyBasalStat] = []

        // Specialfall: 24 h‑valet (daysToAnalyze == 1 och inte "Idag") ska vara ett rullande 24 h‑fönster
        if !isTodayOnly && daysToAnalyze == 1 {
            let interval = DateInterval(start: startDate, end: endDate)
            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            let stat = DailyBasalStat(dayStart: startDate, totalUnits: sim.totalUnits)
            results.append(stat)
            LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - 24h window start=\(startDate), end=\(endDate), basalUnits=\(sim.totalUnits)", isDebug: true)

            let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
            LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)", isDebug: true)
            return results
        }

        // Standardfall: dela upp i kalenderdagar (Idag, 7, 14, 30 dagar)
        var currentDayStart = calendar.startOfDay(for: startDate)
        let finalDayStart = calendar.startOfDay(for: endDate)

        while currentDayStart <= finalDayStart {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else { break }

            let intervalEnd = min(nextDayStart, endDate)
            let interval = DateInterval(start: currentDayStart, end: intervalEnd)

            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            results.append(DailyBasalStat(dayStart: currentDayStart,
                                          totalUnits: sim.totalUnits))
            LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - dayStart=\(currentDayStart), basalUnits=\(sim.totalUnits)", isDebug: true)

            currentDayStart = nextDayStart
        }

        let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
        LogManager.shared.log(category: .analysis, message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)", isDebug: true)
        return results
    }
    */
    func getDailyDeliveredBasal() -> [DailyBasalStat] {
        guard let mainVC = mainViewController else { return [] }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - getDailyDeliveredBasal called. isTodayOnly=\(isTodayOnly), daysToAnalyze=\(daysToAnalyze)",
            isDebug: true
        )

        let calendar = Calendar.current
        let nowDate = Date()

        // Bestäm analysfönster – håll detta i sync med övriga getters
        let endDate: Date = nowDate
        let startDate: Date

        if isTodayOnly {
            // Idag: midnatt → nu
            startDate = calendar.startOfDay(for: nowDate)
        } else {
            // Övriga perioder (1, 7, 14, 30, 90 dagar): rullande fönster bakåt i tid
            startDate = endDate.addingTimeInterval(-Double(daysToAnalyze) * 24 * 60 * 60)
        }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - window start=\(startDate), end=\(endDate)",
            isDebug: true
        )

        let cutoffTime = startDate.timeIntervalSince1970
        let endTime = endDate.timeIntervalSince1970

        // 1) Ta ut basalstege upp till endTime
        //    och inkludera även sista punkt *före* startDate
        let allBasal = mainVC.statsBasalData
            .filter { $0.date <= endTime }
            .sorted { $0.date < $1.date }

        guard !allBasal.isEmpty else { return [] }

        // Alla punkter inom fönstret
        var basalPoints = allBasal.filter { $0.date >= cutoffTime }

        // Lägg till sista punkten innan cutoff som första element (om den finns),
        // så att motorn vet vilken basal som gällde vid fönstrets start.
        if let lastBeforeStart = allBasal.last(where: { $0.date < cutoffTime }) {
            basalPoints.insert(lastBeforeStart, at: 0)
        }

        guard !basalPoints.isEmpty else { return [] }

        // 2) Gör om till BasalChangeEvent (piecewise-constant rate U/h)
        let events: [StatsBasalEngine.BasalChangeEvent] = basalPoints.map {
            StatsBasalEngine.BasalChangeEvent(
                date: Date(timeIntervalSince1970: $0.date),
                rateUph: $0.basalRate
            )
        }

        // 3) Simulera levererad basal med StatsBasalEngine
        var results: [DailyBasalStat] = []

        // Specialfall: 24 h-valet (daysToAnalyze == 1 och inte "Idag") ska vara ett rullande 24 h-fönster
        if !isTodayOnly && daysToAnalyze == 1 {
            let interval = DateInterval(start: startDate, end: endDate)
            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            let stat = DailyBasalStat(dayStart: startDate, totalUnits: sim.totalUnits)
            results.append(stat)
            LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - 24h window start=\(startDate), end=\(endDate), basalUnits=\(sim.totalUnits)",
                isDebug: true
            )

            let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
            LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)",
                isDebug: true
            )
            return results
        }

        // Standardfall: dela upp i kalenderdagar (Idag, 7, 14, 30, 90 dagar)
        var currentDayStart = calendar.startOfDay(for: startDate)
        let finalDayStart = calendar.startOfDay(for: endDate)

        while currentDayStart <= finalDayStart {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else { break }

            let intervalEnd = min(nextDayStart, endDate)
            let interval = DateInterval(start: currentDayStart, end: intervalEnd)

            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            results.append(DailyBasalStat(dayStart: currentDayStart,
                                          totalUnits: sim.totalUnits))
            LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - dayStart=\(currentDayStart), basalUnits=\(sim.totalUnits)",
                isDebug: true
            )

            currentDayStart = nextDayStart
        }

        let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)",
            isDebug: true
        )
        return results
    }
}
