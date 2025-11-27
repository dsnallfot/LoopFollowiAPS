// LoopFollow
// SimpleStatsViewModel.swift

import Combine
import Foundation

class SimpleStatsViewModel: ObservableObject {
    @Published var gmi: Double?
    @Published var avgGlucose: Double?
    @Published var avgGlucoseTrend: StatsTrendArrow = .none

    @Published var stdDeviation: Double?
    @Published var coefficientOfVariation: Double?
    @Published var stdDeviationTrend: StatsTrendArrow = .none
    @Published var cvTrend: StatsTrendArrow = .none

    @Published var totalDailyDose: Double?
    @Published var totalDailyDoseTrend: StatsTrendArrow = .none

    @Published var programmedBasal: Double?
    @Published var programmedBasalTrend: StatsTrendArrow = .none

    @Published var actualBasal: Double?
    @Published var actualBasalTrend: StatsTrendArrow = .none

    @Published var avgBolus: Double?
    @Published var avgBolusTrend: StatsTrendArrow = .none

    @Published var avgCarbs: Double?
    @Published var avgCarbsTrend: StatsTrendArrow = .none

    @Published var avgBGCheck: Double?
    @Published var avgBGCheckTrend: StatsTrendArrow = .none

    @Published var avgLowTreatments: Double?
    @Published var avgLowTreatmentsTrend: StatsTrendArrow = .none

    @Published var avgLowTreatmentAmount: Double?
    @Published var avgLowTreatmentAmountTrend: StatsTrendArrow = .none

    @Published var avgFPUCarbs: Double?
    @Published var avgFPUCarbsTrend: StatsTrendArrow = .none

    @Published var avgManualBolus: Double?
    @Published var avgManualBolusTrend: StatsTrendArrow = .none

    @Published var avgSMB: Double?
    @Published var avgSMBTrend: StatsTrendArrow = .none

    @Published var netMealBolus: Double?
    @Published var netMealBolusTrend: StatsTrendArrow = .none

    @Published var realCarbRatio: Double?
    @Published var realCarbRatioTrend: StatsTrendArrow = .none

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
    }

    func calculateStats() {
        // Reset trends – sätts upp senare när previous-period-logik är på plats
            avgGlucoseTrend = .none
            stdDeviationTrend = .none
            cvTrend = .none
            totalDailyDoseTrend = .none
            programmedBasalTrend = .none
            actualBasalTrend = .none
            avgBolusTrend = .none
            avgCarbsTrend = .none
            avgBGCheckTrend = .none
            avgLowTreatmentsTrend = .none
            avgLowTreatmentAmountTrend = .none
            avgFPUCarbsTrend = .none
            avgManualBolusTrend = .none
            avgSMBTrend = .none
            netMealBolusTrend = .none
            realCarbRatioTrend = .none
        
        // Definiera nuvarande och föregående analysfönster (för trend-pilar)
                let currentInterval = dataService.currentStatsInterval()
                let previousInterval = dataService.previousStatsInterval()
        
        let bgData = dataService.getBGData()
        guard !bgData.isEmpty else { return }

        let totalGlucose = bgData.reduce(0) { $0 + $1.sgv }
        let avgBGmgdL = Double(totalGlucose) / Double(bgData.count)
        avgGlucose = UserDefaultsRepository.units.value == "mg/dL" ? avgBGmgdL : avgBGmgdL * GlucoseConversion.mgDlToMmolL

        let variance = bgData.reduce(0.0) { sum, reading in
            let diff = Double(reading.sgv) - avgBGmgdL
            return sum + (diff * diff)
        }
        let stdDevMgdL = sqrt(variance / Double(bgData.count))
        stdDeviation = UserDefaultsRepository.units.value == "mg/dL" ? stdDevMgdL : stdDevMgdL * GlucoseConversion.mgDlToMmolL

        gmi = 3.31 + (0.02392 * avgBGmgdL)

        if avgBGmgdL > 0 {
            coefficientOfVariation = (stdDevMgdL / avgBGmgdL) * 100.0
        } else {
            coefficientOfVariation = nil
        }

        let cutoffTime = Date().timeIntervalSince1970 - (Double(dataService.daysToAnalyze) * 24 * 60 * 60)
        let now = Date().timeIntervalSince1970

        // Bolus-data (manuell + SMB)
        let bolusData = dataService.getBolusData()
        let smbData = dataService.getSMBData()

        let manualBolusTotal = bolusData.reduce(0.0) { $0 + $1.value }
        let smbTotal = smbData.reduce(0.0) { $0 + $1.value }
        let totalBolusInPeriod = manualBolusTotal + smbTotal

        let bolusDates = (bolusData.map { $0.date } + smbData.map { $0.date })
            .filter { $0 >= cutoffTime && $0 <= now }

        let actualDaysWithBolus = calculateActualDaysCovered(
            dates: bolusDates,
            requestedDays: dataService.daysToAnalyze
        )

        if actualDaysWithBolus > 0 {
            avgBolus = totalBolusInPeriod / Double(actualDaysWithBolus)
            avgManualBolus = manualBolusTotal / Double(actualDaysWithBolus)
            avgSMB = smbTotal / Double(actualDaysWithBolus)
        } else {
            avgBolus = nil
            avgManualBolus = nil
            avgSMB = nil
        }

        // Kolhydrater + FPU (foodType tom)
        let carbData = dataService.getCarbData()

        let totalCarbsInPeriod = carbData.reduce(0.0) { $0 + $1.value }
        let totalFPUCarbsInPeriod = carbData
            .filter { ($0.foodType ?? "").isEmpty }
            .reduce(0.0) { $0 + $1.value }

        let carbDates = carbData
            .map { $0.date }
            .filter { $0 >= cutoffTime && $0 <= now }

        let actualDaysWithCarbs = calculateActualDaysCovered(
            dates: carbDates,
            requestedDays: dataService.daysToAnalyze
        )

        if actualDaysWithCarbs > 0 {
            avgCarbs = totalCarbsInPeriod / Double(actualDaysWithCarbs)
            avgFPUCarbs = totalFPUCarbsInPeriod / Double(actualDaysWithCarbs)
        } else {
            avgCarbs = nil
            avgFPUCarbs = nil
        }

        // Fingerstick (BG Check) – count of BG Check treatments per dag
        let bgCheckDates = dataService.getBGCheckDates()
        if !bgCheckDates.isEmpty {
            let actualDaysWithBGChecks = calculateActualDaysCovered(
                dates: bgCheckDates,
                requestedDays: dataService.daysToAnalyze
            )
            if actualDaysWithBGChecks > 0 {
                avgBGCheck = Double(bgCheckDates.count) / Double(actualDaysWithBGChecks)
            } else {
                avgBGCheck = nil
            }
        } else {
            avgBGCheck = nil
        }

        // Hypo-behandlingar (Dextro): foodType innehåller minst en "🍬"
        let lowTreatmentCarbEntries = carbData
            .filter { ($0.foodType ?? "").contains("🍬") }

        let lowTreatmentDates = lowTreatmentCarbEntries
            .map { $0.date }
            .filter { $0 >= cutoffTime && $0 <= now }

        if !lowTreatmentDates.isEmpty {
            let actualDaysWithLowTreatments = calculateActualDaysCovered(
                dates: lowTreatmentDates,
                requestedDays: dataService.daysToAnalyze
            )

            if actualDaysWithLowTreatments > 0 {
                // Antal Dextro-tillfällen per dag
                avgLowTreatments = Double(lowTreatmentDates.count) / Double(actualDaysWithLowTreatments)

                // Total mängd Dextro (g) i perioden, baserat på carb-värdet
                let totalLowTreatmentCarbsInPeriod = lowTreatmentCarbEntries
                    .filter { $0.date >= cutoffTime && $0.date <= now }
                    .reduce(0.0) { $0 + $1.value }

                // g Dextro per dag
                avgLowTreatmentAmount = totalLowTreatmentCarbsInPeriod / Double(actualDaysWithLowTreatments)
            } else {
                avgLowTreatments = nil
                avgLowTreatmentAmount = nil
            }
        } else {
            avgLowTreatments = nil
            avgLowTreatmentAmount = nil
        }

        let dailyBasalStats = dataService.getDailyDeliveredBasal()

        var avgDailyBolus = 0.0
        var avgDailyBasal = 0.0

        if actualDaysWithBolus > 0 {
            avgDailyBolus = totalBolusInPeriod / Double(actualDaysWithBolus)
        }

        if !dailyBasalStats.isEmpty {
            let basalSum = dailyBasalStats.reduce(0.0) { $0 + $1.totalUnits }
            avgDailyBasal = basalSum / Double(dailyBasalStats.count)
            actualBasal = avgDailyBasal
        } else {
            actualBasal = nil
        }

        if actualDaysWithBolus > 0 || !dailyBasalStats.isEmpty {
            totalDailyDose = avgDailyBolus + avgDailyBasal
        } else {
            totalDailyDose = nil
        }

        let basalProfile = dataService.getBasalProfile()
        if dataService.isTodayOnly {
            // "Idag": använd teoretisk profilbasal från midnatt till nu
            programmedBasal = calculateProgrammedBasalForToday(basalProfile: basalProfile)
        } else {
            // Övriga perioder: använd 24h-profilbasal (E/dygn)
            programmedBasal = calculateProgrammedBasalFromProfile(basalProfile: basalProfile)
        }

        // Netto måltidsbolus = Total Daglig Dos − Profilbasal
        if let tdd = totalDailyDose, let profile = programmedBasal {
            let net = tdd - profile
            netMealBolus = net > 0 ? net : 0
        } else {
            netMealBolus = nil
        }

        // Verklig insulinkvot (g/E) = Kolhydrater / Netto måltidsbolus
        if let carbsPerDay = avgCarbs, let net = netMealBolus, net > 0 {
            realCarbRatio = carbsPerDay / net
        } else {
            realCarbRatio = nil
        }

        // MARK: - Trender (jämför med föregående period med samma längd)
        if let prevInterval = previousInterval {
            let periodDays = max(currentInterval.duration / (24 * 60 * 60), 1)

            // BG-data föregående period
            let prevBG = dataService.getBGData(in: prevInterval)
            var prevAvgBGmgdL: Double?
            var prevStdDevMgdL: Double?

            if !prevBG.isEmpty {
                let prevTotalGlucose = prevBG.reduce(0) { $0 + $1.sgv }
                let avg = Double(prevTotalGlucose) / Double(prevBG.count)
                prevAvgBGmgdL = avg

                let prevVariance = prevBG.reduce(0.0) { sum, reading in
                    let diff = Double(reading.sgv) - avg
                    return sum + (diff * diff)
                }
                prevStdDevMgdL = sqrt(prevVariance / Double(prevBG.count))
            }

            // Medelglukos-trend (i aktuella enheter)
            let prevAvgGlucoseConverted: Double? = {
                guard let base = prevAvgBGmgdL else { return nil }
                if UserDefaultsRepository.units.value == "mg/dL" {
                    return base
                } else {
                    return base * GlucoseConversion.mgDlToMmolL
                }
            }()
            avgGlucoseTrend = StatsTrendCalculator.arrow(current: avgGlucose, previous: prevAvgGlucoseConverted)

            // StdAvvikelse/CV-trend
            if let prevStd = prevStdDevMgdL, let prevAvg = prevAvgBGmgdL, prevAvg > 0 {
                let prevStdConverted: Double = {
                    if UserDefaultsRepository.units.value == "mg/dL" {
                        return prevStd
                    } else {
                        return prevStd * GlucoseConversion.mgDlToMmolL
                    }
                }()
                let prevCV = (prevStd / prevAvg) * 100.0

                stdDeviationTrend = StatsTrendCalculator.arrow(current: stdDeviation, previous: prevStdConverted)
                cvTrend = StatsTrendCalculator.arrow(current: coefficientOfVariation, previous: prevCV)
            } else {
                stdDeviationTrend = .none
                cvTrend = .none
            }

            // Bolus + basal → TDD-trend
            let prevBolus = dataService.getBolusData(in: prevInterval)
            let prevSMB = dataService.getSMBData(in: prevInterval)
            let prevManualBolusTotal = prevBolus.reduce(0.0) { $0 + $1.value }
            let prevSMBTotal = prevSMB.reduce(0.0) { $0 + $1.value }
            let prevTotalBolus = prevManualBolusTotal + prevSMBTotal

            let prevBasalTotal = dataService.getDailyDeliveredBasal(in: prevInterval)
                .reduce(0.0) { $0 + $1.totalUnits }

            let prevAvgDailyBolus = prevTotalBolus / periodDays
            let prevAvgDailyBasal = prevBasalTotal / periodDays
            let prevTDD = prevAvgDailyBolus + prevAvgDailyBasal

            totalDailyDoseTrend = StatsTrendCalculator.arrow(current: totalDailyDose, previous: prevTDD)
            actualBasalTrend = StatsTrendCalculator.arrow(current: actualBasal, previous: prevAvgDailyBasal)

            // Kolhydrater + FPU
            let prevCarbsData = dataService.getCarbData(in: prevInterval)
            let prevTotalCarbs = prevCarbsData.reduce(0.0) { $0 + $1.value }
            let prevAvgCarbsPerDay = prevTotalCarbs / periodDays
            avgCarbsTrend = StatsTrendCalculator.arrow(current: avgCarbs, previous: prevAvgCarbsPerDay)

            let prevFPUCarbs = prevCarbsData
                .filter { ($0.foodType ?? "").isEmpty }
                .reduce(0.0) { $0 + $1.value }
            let prevAvgFPUPerDay = prevFPUCarbs / periodDays
            avgFPUCarbsTrend = StatsTrendCalculator.arrow(current: avgFPUCarbs, previous: prevAvgFPUPerDay)

            // Fingerstick / BG Check
            let prevBGChecks = dataService.getBGCheckDates(in: prevInterval)
            let prevAvgBGChecksPerDay = Double(prevBGChecks.count) / periodDays
            avgBGCheckTrend = StatsTrendCalculator.arrow(current: avgBGCheck, previous: prevAvgBGChecksPerDay)

            // Hypo-behandlingar (Dextro)
            let prevLowTreatmentEntries = prevCarbsData.filter { ($0.foodType ?? "").contains("🍬") }
            let prevLowTreatmentCount = prevLowTreatmentEntries.count
            let prevLowTreatmentCarbs = prevLowTreatmentEntries.reduce(0.0) { $0 + $1.value }

            let prevAvgLowTreatmentsPerDay = Double(prevLowTreatmentCount) / periodDays
            let prevAvgLowTreatmentAmountPerDay = prevLowTreatmentCarbs / periodDays

            avgLowTreatmentsTrend = StatsTrendCalculator.arrow(current: avgLowTreatments, previous: prevAvgLowTreatmentsPerDay)
            avgLowTreatmentAmountTrend = StatsTrendCalculator.arrow(current: avgLowTreatmentAmount, previous: prevAvgLowTreatmentAmountPerDay)

            // Medel bolus (manuell + SMB) + uppdelning
            let prevAvgBolusPerDay = prevTotalBolus / periodDays
            avgBolusTrend = StatsTrendCalculator.arrow(current: avgBolus, previous: prevAvgBolusPerDay)

            let prevAvgManualBolusPerDay = prevManualBolusTotal / periodDays
            avgManualBolusTrend = StatsTrendCalculator.arrow(current: avgManualBolus, previous: prevAvgManualBolusPerDay)

            let prevAvgSMBPerDay = prevSMBTotal / periodDays
            avgSMBTrend = StatsTrendCalculator.arrow(current: avgSMB, previous: prevAvgSMBPerDay)

            // Netto måltidsbolus och verklig insulinkvot
            let prevNetMealBolus: Double? = {
                guard let profile = programmedBasal else { return nil }
                let net = prevTDD - profile
                return net > 0 ? net : 0
            }()
            netMealBolusTrend = StatsTrendCalculator.arrow(current: netMealBolus, previous: prevNetMealBolus)

            let prevRealCarbRatio: Double? = {
                guard let net = prevNetMealBolus, net > 0 else { return nil }
                return prevAvgCarbsPerDay / net
            }()
            realCarbRatioTrend = StatsTrendCalculator.arrow(current: realCarbRatio, previous: prevRealCarbRatio)
        }
    }

    private func calculateTotalBasal(basalData: [MainViewController.basalGraphStruct]) -> Double {
        guard !basalData.isEmpty else { return 0.0 }

        var totalBasal = 0.0
        let cutoffTime = Date().timeIntervalSince1970 - (Double(dataService.daysToAnalyze) * 24 * 60 * 60)
        let now = Date().timeIntervalSince1970

        let basalProfile = dataService.getBasalProfile()

        let sortedBasal = basalData.sorted { $0.date < $1.date }

        for i in 0 ..< sortedBasal.count {
            let current = sortedBasal[i]
            let startTime = max(current.date, cutoffTime)

            let endTime: TimeInterval
            if i < sortedBasal.count - 1 {
                endTime = min(sortedBasal[i + 1].date, now)
            } else {
                endTime = now
            }

            if endTime > startTime {
                let durationHours = (endTime - startTime) / 3600.0

                let scheduledBasalRate = getScheduledBasalRate(for: startTime, profile: basalProfile)

                let adjustment = current.basalRate - scheduledBasalRate

                totalBasal += scheduledBasalRate * durationHours
                totalBasal += adjustment * durationHours
            }
        }

        return totalBasal
    }

    private func getScheduledBasalRate(for time: TimeInterval, profile: [MainViewController.basalProfileStruct]) -> Double {
        guard !profile.isEmpty else { return 0.0 }

        let calendar = Calendar.current
        let date = Date(timeIntervalSince1970: time)
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)

        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let secondsSinceMidnight = Double(hours * 3600 + minutes * 60 + seconds)

        let sortedProfile = profile.sorted { $0.timeAsSeconds < $1.timeAsSeconds }

        for i in 0 ..< sortedProfile.count {
            let current = sortedProfile[i]
            let nextTime: Double
            if i < sortedProfile.count - 1 {
                nextTime = sortedProfile[i + 1].timeAsSeconds
            } else {
                nextTime = 24 * 60 * 60
            }

            if secondsSinceMidnight >= current.timeAsSeconds && secondsSinceMidnight < nextTime {
                return current.value
            }
        }

        return sortedProfile.first?.value ?? 0.0
    }

    private func calculateActualDaysCovered(dates: [TimeInterval], requestedDays: Int) -> Int {
        guard !dates.isEmpty else { return requestedDays }

        let calendar = Calendar.current
        let cutoffTime = Date().timeIntervalSince1970 - (Double(requestedDays) * 24 * 60 * 60)
        let filteredDates = dates.filter { $0 >= cutoffTime }

        var uniqueDays = Set<Date>()
        for date in filteredDates {
            let dateObj = Date(timeIntervalSince1970: date)
            let dayStart = calendar.startOfDay(for: dateObj)
            uniqueDays.insert(dayStart)
        }

        return min(uniqueDays.count, requestedDays)
    }

    private func calculateProgrammedBasalFromProfile(basalProfile: [MainViewController.basalProfileStruct]) -> Double {
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
    
    // Profilbasal för "Idag": teoretisk basal från midnatt fram till nu
    private func calculateProgrammedBasalForToday(
        basalProfile: [MainViewController.basalProfileStruct]
    ) -> Double {
        guard !basalProfile.isEmpty else { return 0.0 }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        return scheduledBasal(from: startOfDay, to: now, basalProfile: basalProfile)
    }

    /// Integrera schemalagd profilbasal (enligt basalprofil) mellan två datum.
    /// Baserad på MealAnalysisView.scheduledBasal(from:to:) men använder basalprofilen som skickas in.
    private func scheduledBasal(
        from start: Date,
        to end: Date,
        basalProfile: [MainViewController.basalProfileStruct]
    ) -> Double {
        let schedule = basalProfile  // array av (timeAsSeconds, value)
        guard !schedule.isEmpty else { return 0 }
        let calendar = Calendar.current
        var total = 0.0
        var current = start

        func basalRate(at date: Date) -> Double {
            let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
            let secondsOfDay = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
            // hitta sista entry vars timeAsSeconds ≤ secondsOfDay
            var rate = schedule.last!.value
            for entry in schedule {
                if Int(entry.timeAsSeconds) <= secondsOfDay {
                    rate = entry.value
                } else {
                    break
                }
            }
            return rate
        }

        func nextChange(after date: Date) -> Date {
            // Bygg DateComponents (hour, minute, second) för alla schema-brytningar
            let breakpoints: [DateComponents] = schedule.map { entry in
                let totalSeconds = Int(entry.timeAsSeconds)
                let h = totalSeconds / 3600
                let m = (totalSeconds % 3600) / 60
                let s = totalSeconds % 60
                var dc = DateComponents()
                dc.hour = h
                dc.minute = m
                dc.second = s
                return dc
            }
            var candidate: Date? = nil
            for dc in breakpoints {
                if let d = calendar.nextDate(
                    after: date,
                    matching: dc,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .last,
                    direction: .forward
                ) {
                    if d > date {
                        if candidate == nil || d < candidate! {
                            candidate = d
                        }
                    }
                }
            }
            // Om inget hittades (bör inte hända), flytta en sekund framåt för att undvika loop
            return candidate ?? calendar.date(byAdding: .second, value: 1, to: date)!
        }

        while current < end {
            let rate = basalRate(at: current)
            let next = min(end, nextChange(after: current))

            if next <= current {
                let bumped = calendar.date(byAdding: .second, value: 1, to: current)!
                if bumped >= end { break }
                current = bumped
                continue
            }

            let hours = next.timeIntervalSince(current) / 3600.0
            total += rate * hours
            current = next
        }
        return max(total, 0)
    }
}
