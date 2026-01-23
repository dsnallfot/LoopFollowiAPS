// LoopFollow
// DailyStatsViewModel.swift

import Foundation
import Combine

extension StatsDataService {
    /// Dummy placeholder, används endast för att SwiftUI ska kunna skapa views
    static var placeholder: StatsDataService {
        return StatsDataService(mainViewController: nil)
    }
}

struct DailyStatRow: Identifiable {
    let id = UUID()
    let date: Date

    let totalCarbs: Double?          // g
    let insulinTDD: Double?          // E (basal + bolus)
    let meanGlucoseMmol: Double?     // mmol/L
    let lowPercent: Double?          // %
    let tightRangePercent: Double?   // %
    let timeInRangePercent: Double?  // %
    let stdDevMmol: Double?          // mmol/L
    let profileBasal: Double?        // E (teoretisk profilbasal per 24h)
    let emptyInfo: String?           // Trailing space

    /// Antal glukosvärden för dagen (används för att filtrera bort "halva" dagar ur statistiken)
    let glucoseCount: Int?
}

final class DailyStatsViewModel: ObservableObject {
    let dataService: StatsDataService
    private let todayTDDOverride: Double?

        var mainViewController: MainViewController? {
            dataService.mainViewController
        }
    
    @Published var rows: [DailyStatRow] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let lowGlucoseOKThreshold: Double = 0.05
    let lowGlucoseGreatThreshold: Double = 0.03
    let titrTargetThreshold: Double = 0.5
    let tirTargetThreshold: Double = 0.7
    let stdDevOkThreshold: Double = 3.0
    let stdDevGreatThreshold: Double = 2.5
    let bgAverageOKThreshold: Double = 8.0
    let bgAverageGreatThreshold: Double = 7.5
    let minGlucoseReadingsPerDay: Int = 150

    var numberOfDaysMeetingTitrTarget: Int {
        rowsWithSufficientGlucose.filter { row in
            if let tir = row.tightRangePercent {
                return (tir / 100.0) >= titrTargetThreshold
            } else {
                return false
            }
        }.count
    }
    
    var numberOfDaysMeetingTirTarget: Int {
        rowsWithSufficientGlucose.filter { row in
            if let tir = row.timeInRangePercent {
                return (tir / 100.0) >= tirTargetThreshold
            } else {
                return false
            }
        }.count
    }

    var numberOfDaysInScope: Int {
        rowsWithSufficientGlucose.count
    }

    /// Endast dagar med tillräckligt många glukosvärden (för att slippa med halva dagar).
    /// För dagens datum är vi mer tillåtande (så fort vi har något glukosvärde).
    /// Om inga dagar alls uppfyller kraven (t.ex. p.g.a. för få värden per dag),
    /// faller vi tillbaka till att visa alla dagar som har någon form av glukosdata.
    var rowsWithSufficientGlucose: [DailyStatRow] {
        let calendar = Calendar.current

        // Primär, strikt filtrering
        let strict = rows.filter { row in
            // Dagens datum: inkludera alltid om vi har något glukosvärde
            if calendar.isDateInToday(row.date) {
                return (row.glucoseCount ?? 0) > 0
            }

            // Äldre dagar: kräver minst minGlucoseReadingsPerDay värden
            if row.meanGlucoseMmol != nil, let count = row.glucoseCount {
                return count >= minGlucoseReadingsPerDay
            }
            return false
        }

        // Om vi fick minst en dag med tillräckligt många värden, använd den strikta listan.
        if !strict.isEmpty {
            return strict
        }

        // Annars: visa hellre dagar som har någon form av glukosdata
        let fallback = rows.filter { $0.meanGlucoseMmol != nil || rowHasAnyGlucoseCount($0) }
        if !fallback.isEmpty {
            return fallback
        }

        // Sista utväg
        return rows
    }

    private func rowHasAnyGlucoseCount(_ row: DailyStatRow) -> Bool {
        (row.glucoseCount ?? 0) > 0
    }

    var percentageOfDaysMeetingTarget: Double {
        let scope = numberOfDaysInScope
        guard scope > 0 else { return 0.0 }
        return Double(numberOfDaysMeetingTitrTarget) / Double(scope)
    }

    // MARK: - Aggregated averages for DailyStatsView

    /// Genomsnittliga värden baserat på de dagar som faktiskt är i scope (rowsWithSufficientGlucose).
    var averageCarbs: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.totalCarbs }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageTDD: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.insulinTDD }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageMeanGlucose: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.meanGlucoseMmol }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Genomsnittlig andel låga värden (%).
    var averageLowPercent: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.lowPercent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Genomsnittlig tid i tight målområde (TITR, %).
    var averageTitr: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.tightRangePercent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Genomsnittlig tid i målområde (TIR, %).
    var averageTir: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.timeInRangePercent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageStdDev: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.stdDevMmol }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Genomsnittlig teoretisk basal (E/dag) från profilen.
    var averageProfileBasal: Double? {
        let values = rowsWithSufficientGlucose.compactMap { $0.profileBasal }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private let daysBack: Int

    init(dataService: StatsDataService, daysBack: Int = 90, todayTDDOverride: Double? = nil) {
        self.dataService = dataService
        self.todayTDDOverride = todayTDDOverride
        self.daysBack = daysBack
    }

    // MARK: - Public API

    func loadDailyStats() {
        guard !isLoading else { return }
        // Skydda mot placeholder-StatsDataService (används bara som SwiftUI-dummy)
        guard self.mainViewController != nil else {
            LogManager.shared.log(
                category: .analysis,
                message: "DailyStatsViewModel.loadDailyStats – aborting because dataService.mainViewController is nil (placeholder in use)",
                isDebug: true
            )
            DispatchQueue.main.async {
                self.rows = []
                self.isLoading = false
                self.errorMessage = nil
            }
            return
        }
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let calendar = Calendar.current

            // Använd samma analysintervall som övrig AggregatedStats-logik
            let interval = self.dataService.currentStatsInterval()
            let intervalStart = interval.start
            let intervalEndExclusive = interval.end

            // Justera till kalenderdygn enligt intervallet:
            // firstDayStart = 00:00 för äldsta dygnet i fönstret
            // endDayStart = 00:00 för dagen efter sista dygnet i fönstret
            let firstDayStart = calendar.startOfDay(for: intervalStart)
            let endDayStart = calendar.startOfDay(for: intervalEndExclusive)

            // Antal dygn i analysfönstret (t.ex. 1, 3, 7, 14, 30, 90)
            let components = calendar.dateComponents([.day], from: firstDayStart, to: endDayStart)
            let daysToShow = max(1, components.day ?? 1)

            LogManager.shared.log(
                category: .temporaryDebug,
                message: """
                DailyStatsViewModel.loadDailyStats – daysToAnalyze=\(self.dataService.daysToAnalyze), daysToShow=\(daysToShow)
                interval=\(intervalStart) → \(intervalEndExclusive)
                """,
                isDebug: false
            )

            // Sista hela dygnet i fönstret är dygnet före endDayStart
            guard let lastDayStart = calendar.date(byAdding: .day, value: -1, to: endDayStart) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Kunde inte beräkna datumintervall."
                }
                return
            }

            let analysisInterval = DateInterval(start: firstDayStart, end: endDayStart)

            // 1. Hämta alla BG-värden inom detta intervall
            let bgAll = self.dataService.getBGData(in: analysisInterval)
            LogManager.shared.log(
                category: .analysis,
                message: """
                DailyStatsViewModel.loadDailyStats
                daysToShow=\(daysToShow)
                interval=\(analysisInterval.start) → \(analysisInterval.end)
                bgAllCount=\(bgAll.count)
                """,
                isDebug: false
            )
            if bgAll.isEmpty {
                let statsBGCount = self.dataService.mainViewController?.statsBGData.count ?? -1
                let statsLastUpdated = self.dataService.mainViewController?.statsCacheLastUpdated

                LogManager.shared.log(
                    category: .temporaryDebug,
                    message: """
                    DailyStatsViewModel.loadDailyStats – bgAllCount=0 ⚠️
                    daysToShow=\(daysToShow)
                    analysisInterval=\(analysisInterval.start) → \(analysisInterval.end)
                    statsBGData.count=\(statsBGCount)
                    statsCacheLastUpdated=\(String(describing: statsLastUpdated))
                    """,
                    isDebug: true
                )

                DispatchQueue.main.async {
                    self.rows = []
                    self.isLoading = false
                    self.errorMessage = "Inga glukosdata hittades."
                }
                return
            }

            // 2. Grupp BG per kalenderdag (startOfDay)
            let groupedBG = Dictionary(grouping: bgAll) { reading -> Date in
                let date = Date(timeIntervalSince1970: reading.date)
                return calendar.startOfDay(for: date)
            }

            // 3. Hämta övrig data en gång, inom samma kalenderbaserade intervall
            let bolusData = self.dataService.getBolusData(in: analysisInterval)
            let smbData = self.dataService.getSMBData(in: analysisInterval)
            let carbData = self.dataService.getCarbData(in: analysisInterval)
            let dailyBasalStats = self.dataService.getDailyDeliveredBasal(in: analysisInterval)

            // 4. Bygg upp dictionarier per dag
            let basalPerDay: [Date: Double] = Dictionary(
                grouping: dailyBasalStats,
                by: { stat in
                    let d = stat.dayStart
                    return calendar.startOfDay(for: d)
                }
            ).mapValues { stats in
                stats.reduce(0.0) { $0 + $1.totalUnits }
            }

            let bolusPerDay: [Date: Double] = self.sumPerDay(
                data: bolusData,
                dateKey: { Date(timeIntervalSince1970: $0.date) },
                valueKey: { $0.value },
                calendar: calendar
            )

            let smbPerDay: [Date: Double] = self.sumPerDay(
                data: smbData,
                dateKey: { Date(timeIntervalSince1970: $0.date) },
                valueKey: { $0.value },
                calendar: calendar
            )

            let carbsPerDay: [Date: Double] = self.sumPerDay(
                data: carbData,
                dateKey: { Date(timeIntervalSince1970: $0.date) },
                valueKey: { $0.value },
                calendar: calendar
            )

            // 5. Konstanter för beräkningar
            let mgToMmol = GlucoseConversion.mgDlToMmolL
            let lowThresholdMgdL = Double(UserDefaultsRepository.lowLine.value)
            let tightLowMgdL = Double(UserDefaultsRepository.lowLine.value)
            let tightHighMgdL = Double(UserDefaultsRepository.highLine.value)
            let tirHighMgdL = 180.0

            // 6. Bygg EN rad per kalenderdag, alltid exakt daysToShow st
            var allRows: [DailyStatRow] = []

            // Nyaste först: 0 = sista dagen i intervallet, 1 = dagen före, osv
            for offset in 0..<daysToShow {
                guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: lastDayStart),
                      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
                else { continue }

                let dayInterval = DateInterval(start: dayStart, end: dayEnd)

                // Historisk profilbasal för just denna dag (24h, teoretisk)
                let dayBasalProfile = self.dataService.getBasalProfile(for: dayInterval)
                let profileBasalValueForDay = self.calculateProgrammedBasalFromProfile(
                    basalProfile: dayBasalProfile
                )

                let emptyInfo = ""

                // BG för dagen
                let bgForDay = groupedBG[dayStart] ?? []

                var meanGlucoseMmol: Double?
                var stdDevMmol: Double?
                var lowPercent: Double?
                var tightRangePercent: Double?
                var timeInRangePercent: Double?
                var glucoseCountForDay: Int?

                if !bgForDay.isEmpty {
                    let sgvValues = bgForDay.map { Double($0.sgv) }
                    let count = Double(sgvValues.count)
                    glucoseCountForDay = sgvValues.count

                    let sum = sgvValues.reduce(0.0, +)
                    let meanMgdL = sum / count
                    meanGlucoseMmol = meanMgdL * mgToMmol

                    let variance = sgvValues.reduce(0.0) { partial, v in
                        let diff = v - meanMgdL
                        return partial + diff * diff
                    } / count
                    let stdDevMgdL = sqrt(variance)
                    stdDevMmol = stdDevMgdL * mgToMmol

                    let lowCount = sgvValues.filter { $0 < lowThresholdMgdL }.count
                    lowPercent = (Double(lowCount) / count) * 100.0

                    let tightCount = sgvValues.filter { $0 >= tightLowMgdL && $0 <= tightHighMgdL }.count
                    tightRangePercent = (Double(tightCount) / count) * 100.0

                    let tirCount = sgvValues.filter { $0 >= tightLowMgdL && $0 <= tirHighMgdL }.count
                    timeInRangePercent = (Double(tirCount) / count) * 100.0
                }

                /*
                // --- Sanity log (debug): glucose count per day ---
                #if DEBUG
                let dayString: String = {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    df.timeZone = TimeZone.current
                    return df.string(from: dayStart)
                }()

                let countText = glucoseCountForDay.map(String.init) ?? "0"
                let lowText = lowPercent.map { String(format: "%.1f", $0) } ?? "-"
                let titrText = tightRangePercent.map { String(format: "%.1f", $0) } ?? "-"
                let tirText = timeInRangePercent.map { String(format: "%.1f", $0) } ?? "-"

                let suffix = (glucoseCountForDay ?? 0) < self.minGlucoseReadingsPerDay && !calendar.isDateInToday(dayStart) ? " ⚠️<\(self.minGlucoseReadingsPerDay)" : ""

                LogManager.shared.log(
                    category: .analysis,
                    message: "[DailyStats][Sanity] day=\(dayString) glucoseCount=\(countText)\(suffix) low%=\(lowText) TITR%=\(titrText) TIR%=\(tirText)",
                    isDebug: true
                )
                #endif
                // --- End sanity log ---
                */

                // Kolhydrater
                let carbs = carbsPerDay[dayStart]

                // Bolus + SMB
                let manualBolus = bolusPerDay[dayStart] ?? 0.0
                let smb = smbPerDay[dayStart] ?? 0.0

                // Levererad basal
                let basalDelivered = basalPerDay[dayStart] ?? 0.0

                let insulinTDD = (manualBolus + smb + basalDelivered)
                var insulinTDDValue: Double? = insulinTDD > 0 ? insulinTDD : nil

                // För dagens datum kan vi använda samma TDD-beräkning som i AggregatedStatsView
                // (SimpleStatsViewModel.totalDailyDose), om ett override-värde har skickats in.
                if calendar.isDateInToday(dayStart), let override = self.todayTDDOverride {
                    insulinTDDValue = override
                }

                let row = DailyStatRow(
                    date: dayStart,
                    totalCarbs: carbs,
                    insulinTDD: insulinTDDValue,
                    meanGlucoseMmol: meanGlucoseMmol,
                    lowPercent: lowPercent,
                    tightRangePercent: tightRangePercent,
                    timeInRangePercent: timeInRangePercent,
                    stdDevMmol: stdDevMmol,
                    profileBasal: profileBasalValueForDay,
                    emptyInfo: emptyInfo,
                    glucoseCount: glucoseCountForDay
                )

                allRows.append(row)
            }

            // Vi genererar exakt daysToShow rader, nyaste först
            DispatchQueue.main.async {
                self.rows = allRows
                self.isLoading = false
            }
        }
    }

    /// Skapa CSV-sträng (separat från export så du kan testa i logg om du vill).
    func makeCSVString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        func fmt(_ value: Double?, decimals: Int = 2) -> String {
            guard let value = value else { return "" }
            let formatted = String(format: "%.\(decimals)f", value)
            // Byt punkt mot komma för svensk Excel
            return formatted.replacingOccurrences(of: ".", with: ",")
        }
        
        var lines: [String] = []
        lines.append("Datum;KH tot (g);Insulin tot (E);Medel BS;Låg %;TIT 3.9-7.8;Std. Dev;Basal (teoretisk)")
        
        for row in rowsWithSufficientGlucose.sorted(by: { $0.date < $1.date }) {
            let dateStr = dateFormatter.string(from: row.date)
            
            // Skala procent 0–100 → 0–1 så Excel kan använda cellformat Procent
            let lowFraction = row.lowPercent.map { $0 / 100.0 }
            let tightFraction = row.tightRangePercent.map { $0 / 100.0 }
            
            let line = [
                dateStr,
                fmt(row.totalCarbs, decimals: 0),
                fmt(row.insulinTDD),
                fmt(row.meanGlucoseMmol, decimals: 2),
                fmt(lowFraction),                 // nu 0–1
                fmt(tightFraction),               // nu 0–1
                fmt(row.stdDevMmol, decimals: 2),
                fmt(row.profileBasal)
            ].joined(separator: ";")              // semikolonseparerat
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Skriv CSV till Documents och returnera URL för delning.
    func writeCSVToDisk() -> URL? {
        let csvString = makeCSVString()
        guard let data = csvString.data(using: .utf8) else { return nil }

        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        let exportURL = documentsURL.appendingPathComponent("DailyStats_\(today).csv")

        do {
            try data.write(to: exportURL, options: .atomic)
            return exportURL
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Misslyckades skriva CSV: \(error.localizedDescription)"
            }
            return nil
        }
    }

    // MARK: - Helpers

    private func sumPerDay<T>(
        data: [T],
        dateKey: (T) -> Date,
        valueKey: (T) -> Double,
        calendar: Calendar
    ) -> [Date: Double] {
        var dict: [Date: Double] = [:]
        for item in data {
            let d = calendar.startOfDay(for: dateKey(item))
            dict[d, default: 0.0] += valueKey(item)
        }
        return dict
    }

    // 24h teoretisk profilbasal, samma logik som i SimpleStatsViewModel
    private func calculateProgrammedBasalFromProfile(
        basalProfile: [MainViewController.basalProfileStruct]
    ) -> Double {
        guard !basalProfile.isEmpty else { return 0.0 }

        let sortedProfile = basalProfile.sorted { $0.timeAsSeconds < $1.timeAsSeconds }

        var totalBasal = 0.0
        let secondsInDay = 24 * 60 * 60

        for i in 0 ..< sortedProfile.count {
            let current = sortedProfile[i]
            let currentTime = Double(current.timeAsSeconds)

            let nextTime: Double
            if i < sortedProfile.count - 1 {
                nextTime = Double(sortedProfile[i + 1].timeAsSeconds)
            } else {
                nextTime = Double(secondsInDay)
            }

            let durationHours = (nextTime - currentTime) / 3600.0
            totalBasal += current.value * durationHours
        }

        return totalBasal
    }
}
