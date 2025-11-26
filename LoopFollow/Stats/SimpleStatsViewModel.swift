// LoopFollow
// SimpleStatsViewModel.swift

import Combine
import Foundation

class SimpleStatsViewModel: ObservableObject {
    @Published var gmi: Double?
    @Published var avgGlucose: Double?
    @Published var stdDeviation: Double?
    @Published var coefficientOfVariation: Double?
    @Published var totalDailyDose: Double?
    @Published var programmedBasal: Double?
    @Published var actualBasal: Double?
    @Published var avgBolus: Double?
    @Published var avgCarbs: Double?
    @Published var avgBGCheck: Double?
    @Published var avgLowTreatments: Double?
    @Published var avgLowTreatmentAmount: Double?
    @Published var avgFPUCarbs: Double?
    @Published var avgManualBolus: Double?
    @Published var avgSMB: Double?
    @Published var netMealBolus: Double?
    @Published var realCarbRatio: Double?

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
    }

    func calculateStats() {
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
