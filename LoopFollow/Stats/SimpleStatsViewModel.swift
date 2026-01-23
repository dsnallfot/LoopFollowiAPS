// LoopFollow
// SimpleStatsViewModel.swift

import Combine
import Foundation

class SimpleStatsViewModel: ObservableObject {
    @Published var gmi: Double?
    @Published var avgGlucose: Double?
    @Published var avgGlucoseTrend: StatsTrendArrow = .none
    
    @Published var highGlucose: Double?
    @Published var highGlucoseTrend: StatsTrendArrow = .none

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
    
    @Published var avgLowPercentage: Double?
    @Published var avgLowPercentageTrend: StatsTrendArrow = .none
    
    @Published var prevAvgGlucose: Double?
    @Published var prevHighGlucose: Double?
    
    @Published var prevStdDeviation: Double?
    @Published var prevCoefficientOfVariation: Double?

    @Published var prevTotalDailyDose: Double?
    @Published var prevProgrammedBasal: Double?
    @Published var prevActualBasal: Double?

    @Published var prevAvgBolus: Double?
    @Published var prevAvgCarbs: Double?

    @Published var prevAvgBGCheck: Double?
    @Published var prevAvgLowTreatments: Double?
    @Published var prevAvgLowTreatmentAmount: Double?

    @Published var prevAvgFPUCarbs: Double?
    @Published var prevAvgManualBolus: Double?
    @Published var prevAvgSMB: Double?

    @Published var prevNetMealBolus: Double?
    @Published var prevRealCarbRatio: Double?
    @Published var prevAvgLowPercentage: Double?

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
    }

    func calculateStats() {
        avgGlucoseTrend = .none
        highGlucoseTrend = .none
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
        avgLowPercentageTrend = .none
        netMealBolusTrend = .none
        realCarbRatioTrend = .none

        // Nolla previous-värden
        prevAvgGlucose = nil
        prevHighGlucose = nil
        prevStdDeviation = nil
        prevCoefficientOfVariation = nil

        prevTotalDailyDose = nil
        prevProgrammedBasal = nil
        prevActualBasal = nil

        prevAvgBolus = nil
        prevAvgCarbs = nil

        prevAvgBGCheck = nil
        prevAvgLowTreatments = nil
        prevAvgLowTreatmentAmount = nil

        prevAvgFPUCarbs = nil
        prevAvgManualBolus = nil
        prevAvgSMB = nil

        prevNetMealBolus = nil
        prevRealCarbRatio = nil
        prevAvgLowPercentage = nil
        
        // Definiera nuvarande och föregående analysfönster (för trend-pilar)
        let baseInterval = dataService.currentStatsInterval()
        let calendar = Calendar.current

        // Normalisera nuvarande intervall till hela kalenderdygn (förutom "Idag"-läget)
        let currentInterval: DateInterval = {
            if dataService.isTodayOnly {
                // StatsDataService.currentStatsInterval returnerar redan 00:00–nu för "Idag"
                return baseInterval
            }

            // Om AggregatedStatsView har satt ett customInterval (via datumväljaren)
            if let custom = dataService.customInterval {
                return custom
            }

            // Fallback: runda av till hela kalenderdagar baserat på baseInterval
            let startDay = calendar.startOfDay(for: baseInterval.start)
            let endDayStart = calendar.startOfDay(for: baseInterval.end)
            if let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDayStart) {
                return DateInterval(start: startDay, end: endExclusive)
            } else {
                return baseInterval
            }
        }()

        // Antal kalenderdagar som nuvarande analysintervall täcker
        let periodDaysForCurrent: Double = {
            if dataService.isTodayOnly {
                return 1.0
            } else {
                let raw = currentInterval.duration / (24 * 60 * 60)
                return max(raw, 1.0)
            }
        }()

        let previousInterval = dataService.previousStatsInterval()
        
        let bgData = dataService.getBGData(in: currentInterval)
        guard !bgData.isEmpty else { return }

        let totalGlucose = bgData.reduce(0) { $0 + $1.sgv }
        let avgBGmgdL = Double(totalGlucose) / Double(bgData.count)
        avgGlucose = UserDefaultsRepository.units.value == "mg/dL" ? avgBGmgdL : avgBGmgdL * GlucoseConversion.mgDlToMmolL

        // Highest glucose in current interval
        if let maxSGV = bgData.max(by: { $0.sgv < $1.sgv })?.sgv {
            let maxMgdL = Double(maxSGV)
            highGlucose = UserDefaultsRepository.units.value == "mg/dL" ? maxMgdL : maxMgdL * GlucoseConversion.mgDlToMmolL
        } else {
            highGlucose = nil
        }

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
        
        // LOW PERCENTAGE (< 3.9 mmol/L)
        // Vi räknar alltid i mg/dL eftersom sgv är mg/dL
        let lowThresholdMgdL = 70.0 //3.9 * 18.0182   // ≈ 70.27 mg/dL

        let lowCount = bgData.filter { Double($0.sgv) < lowThresholdMgdL }.count
        if bgData.count > 0 {
            avgLowPercentage = (Double(lowCount) / Double(bgData.count)) * 100.0
        } else {
            avgLowPercentage = nil
        }

        let cutoffTime = currentInterval.start.timeIntervalSince1970
        let now = currentInterval.end.timeIntervalSince1970

        // Bolus-data (manuell + SMB)
        let bolusData = dataService.getBolusData(in: currentInterval)
        let smbData = dataService.getSMBData(in: currentInterval)

        let manualBolusTotal = bolusData.reduce(0.0) { $0 + $1.value }
        let smbTotal = smbData.reduce(0.0) { $0 + $1.value }
        let totalBolusInPeriod = manualBolusTotal + smbTotal

        // Normalisera alltid per kalenderdag i aktuellt analysfönster
        if totalBolusInPeriod > 0 {
            avgBolus = totalBolusInPeriod / periodDaysForCurrent
            avgManualBolus = manualBolusTotal / periodDaysForCurrent
            avgSMB = smbTotal / periodDaysForCurrent
        } else {
            avgBolus = nil
            avgManualBolus = nil
            avgSMB = nil
        }

        // Kolhydrater + FPU (foodType tom)
        let carbData = dataService.getCarbData(in: currentInterval)

        let totalCarbsInPeriod = carbData.reduce(0.0) { $0 + $1.value }
        let totalFPUCarbsInPeriod = carbData
            .filter { ($0.foodType ?? "").isEmpty }
            .reduce(0.0) { $0 + $1.value }

        let carbDates = carbData
            .map { $0.date }
            .filter { $0 >= cutoffTime && $0 <= now }

        // Vi behåller carbDates om vi vill använda dem till något annat,
        // men för medelvärdena vill vi normalisera över hela kalenderfönstret
        // (samma som vi gör för TDD via periodDaysForCurrent).
        if totalCarbsInPeriod > 0 {
            avgCarbs = totalCarbsInPeriod / periodDaysForCurrent
            avgFPUCarbs = totalFPUCarbsInPeriod / periodDaysForCurrent
        } else {
            avgCarbs = nil
            avgFPUCarbs = nil
        }

        // Fingerstick (BG Check) – count of BG Check treatments per dag
        let bgCheckDates = dataService.getBGCheckDates(in: currentInterval)

        if !bgCheckDates.isEmpty {
            // Använd samma kalenderbaserade längd som för övriga medelvärden
            let daysInPeriod = periodDaysForCurrent
            avgBGCheck = daysInPeriod > 0 ? Double(bgCheckDates.count) / daysInPeriod : nil
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
            // Medel per dag i hela analysfönstret (inte bara dagar med Dextro)
            let daysInPeriod = periodDaysForCurrent

            // Antal Dextro-tillfällen per dag
            avgLowTreatments = Double(lowTreatmentDates.count) / daysInPeriod

            // Total mängd Dextro (g) i perioden, baserat på carb-värdet
            let totalLowTreatmentCarbsInPeriod = lowTreatmentCarbEntries
                .filter { $0.date >= cutoffTime && $0.date <= now }
                .reduce(0.0) { $0 + $1.value }

            // g Dextro per dag
            avgLowTreatmentAmount = totalLowTreatmentCarbsInPeriod / daysInPeriod
        } else {
            avgLowTreatments = nil
            avgLowTreatmentAmount = nil
        }

        let dailyBasalStats = dataService.getDailyDeliveredBasal(in: currentInterval)

        var avgDailyBolus = 0.0
        var avgDailyBasal = 0.0

        // Medel bolus per dag (manuell + SMB) över hela intervallets längd
        if totalBolusInPeriod > 0 {
            avgDailyBolus = totalBolusInPeriod / periodDaysForCurrent
        }

        // Medel levererad basal per dag över hela intervallets längd
        if !dailyBasalStats.isEmpty {
            let basalSum = dailyBasalStats.reduce(0.0) { $0 + $1.totalUnits }
            avgDailyBasal = basalSum / periodDaysForCurrent
            actualBasal = avgDailyBasal
        } else {
            actualBasal = nil
        }

        if (totalBolusInPeriod > 0) || !dailyBasalStats.isEmpty {
            totalDailyDose = avgDailyBolus + avgDailyBasal
        } else {
            totalDailyDose = nil
        }
        
        // Spara 14-dagars medel-TDD i UserDefaults så att andra vyer (t.ex. AddUserDataView) kan återanvända den.
        if let tdd = totalDailyDose,
           dataService.daysToAnalyze == 14,
           !dataService.isTodayOnly {
            UserDefaults.standard.set(tdd, forKey: "Stats14DayAverageTDD")
        }

        // Hämta basalprofil baserat på aktuellt analysintervall (historisk om möjligt)
        let basalProfileForInterval = dataService.getBasalProfile(for: currentInterval)
        if dataService.isTodayOnly {
            // "Idag": använd teoretisk profilbasal från midnatt till nu
            programmedBasal = calculateProgrammedBasalForToday(basalProfile: basalProfileForInterval)
        } else {
            // Övriga perioder: använd genomsnittlig profilbasal per dag i analysfönstret
            let days = max(dataService.daysToAnalyze, 1)
            programmedBasal = averageProgrammedBasalOverPeriod(interval: currentInterval, days: days)
        }

        // Netto måltidsbolus = Total Daglig Dos − Profilbasal
        if let tdd = totalDailyDose, let profile = programmedBasal {
            let net = tdd - profile
            netMealBolus = net > 0 ? net : 0
        } else {
            netMealBolus = nil
        }

        // Verklig insulinkvot (g/E) = Kolhydrater / Netto måltidsbolus
        if let carbsPerDay = avgCarbs, let net = netMealBolus, net > 0.04 {
            realCarbRatio = carbsPerDay / net
        } else {
            realCarbRatio = nil
        }

        // MARK: - Trender (jämför med föregående period med samma längd)
        // För "Idag" vill vi jämföra 00:00–nu idag med samma tidsfönster igår (00:00–nu-00:00 igår).
        let prevIntervalForTrends: DateInterval?

        if dataService.isTodayOnly {
            let now = Date()
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)
            let elapsedSinceMidnight = now.timeIntervalSince(startOfToday)

            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            let endOfYesterdayWindow = startOfYesterday.addingTimeInterval(elapsedSinceMidnight)

            prevIntervalForTrends = DateInterval(start: startOfYesterday, end: endOfYesterdayWindow)
        } else {
            prevIntervalForTrends = previousInterval
        }

        if let prevInterval = prevIntervalForTrends {
            let periodDays: Double = {
                if dataService.isTodayOnly {
                    return 1.0
                } else {
                    let raw = currentInterval.duration / (24 * 60 * 60)
                    return max(raw, 1.0)
                }
            }()

            // BG-data föregående period
            let prevBG = dataService.getBGData(in: prevInterval)
            var prevAvgBGmgdL: Double?
            var prevStdDevMgdL: Double?
            var prevHighBGmgdL: Double?

            if !prevBG.isEmpty {
                let prevTotalGlucose = prevBG.reduce(0) { $0 + $1.sgv }
                let avg = Double(prevTotalGlucose) / Double(prevBG.count)
                prevAvgBGmgdL = avg

                // Highest glucose in previous interval
                if let prevMaxSGV = prevBG.max(by: { $0.sgv < $1.sgv })?.sgv {
                    prevHighBGmgdL = Double(prevMaxSGV)
                }

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
            
            prevAvgGlucose = prevAvgGlucoseConverted

            // Highest glucose trend (i aktuella enheter)
            let prevHighGlucoseConverted: Double? = {
                guard let base = prevHighBGmgdL else { return nil }
                if UserDefaultsRepository.units.value == "mg/dL" {
                    return base
                } else {
                    return base * GlucoseConversion.mgDlToMmolL
                }
            }()

            prevHighGlucose = prevHighGlucoseConverted
            highGlucoseTrend = StatsTrendCalculator.arrow(current: highGlucose, previous: prevHighGlucoseConverted)

            // Low % previous period
            let prevLowCount: Int = prevBG.filter {
                Double($0.sgv) < lowThresholdMgdL
            }.count

            let prevLowPercentage: Double? = {
                guard !prevBG.isEmpty else { return nil }
                return (Double(prevLowCount) / Double(prevBG.count)) * 100.0
            }()

            prevAvgLowPercentage = prevLowPercentage
            avgLowPercentageTrend = StatsTrendCalculator.arrow(
                current: avgLowPercentage,
                previous: prevLowPercentage
            )
            
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
                
                prevStdDeviation = prevStdConverted
                prevCoefficientOfVariation = prevCV
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
            
            prevTotalDailyDose = prevTDD
            prevActualBasal = prevAvgDailyBasal
            
            // Historisk profilbasal för föregående period (samma längd)
            let prevProgrammedBasalValue: Double? = {
                if dataService.isTodayOnly {
                    // För "Idag" jämför vi mot samma tidsfönster igår
                    let prevBasalProfile = dataService.getBasalProfile(for: prevInterval)
                    return scheduledBasal(from: prevInterval.start, to: prevInterval.end, basalProfile: prevBasalProfile)
                } else {
                    let days = max(dataService.daysToAnalyze, 1)
                    return averageProgrammedBasalOverPeriod(interval: prevInterval, days: days)
                }
            }()
            prevProgrammedBasal = prevProgrammedBasalValue
            programmedBasalTrend = StatsTrendCalculator.arrow(current: programmedBasal, previous: prevProgrammedBasalValue)

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
            
            prevAvgCarbs = prevAvgCarbsPerDay
            prevAvgFPUCarbs = prevAvgFPUPerDay

            // Fingerstick / BG Check – trendberäkning
            let prevBGChecks = dataService.getBGCheckDates(in: prevInterval)

            let prevDaysInPeriod: Double
            if dataService.isTodayOnly {
                prevDaysInPeriod = 1.0
            } else {
                prevDaysInPeriod = Double(max(dataService.daysToAnalyze, 1))
            }

            let prevAvgBGChecksPerDay = prevDaysInPeriod > 0
                ? Double(prevBGChecks.count) / prevDaysInPeriod
                : nil

            avgBGCheckTrend = StatsTrendCalculator.arrow(
                current: avgBGCheck,
                previous: prevAvgBGChecksPerDay
            )

            prevAvgBGCheck = prevAvgBGChecksPerDay
            
            // Hypo-behandlingar (Dextro) – föregående period
            let prevLowTreatmentEntries = prevCarbsData.filter { ($0.foodType ?? "").contains("🍬") }
            let prevLowTreatmentCount = prevLowTreatmentEntries.count
            let prevLowTreatmentCarbs = prevLowTreatmentEntries.reduce(0.0) { $0 + $1.value }

            // Samma dagar-logik som för nuvarande period
            let prevDexDaysInPeriod: Double
            if dataService.isTodayOnly {
                prevDexDaysInPeriod = 1.0
            } else {
                prevDexDaysInPeriod = Double(max(dataService.daysToAnalyze, 1))
            }

            let prevAvgLowTreatmentsPerDay = prevDexDaysInPeriod > 0
                ? Double(prevLowTreatmentCount) / prevDexDaysInPeriod
                : 0

            let prevAvgLowTreatmentAmountPerDay = prevDexDaysInPeriod > 0
                ? prevLowTreatmentCarbs / prevDexDaysInPeriod
                : 0

            avgLowTreatmentsTrend = StatsTrendCalculator.arrow(
                current: avgLowTreatments,
                previous: prevAvgLowTreatmentsPerDay
            )

            avgLowTreatmentAmountTrend = StatsTrendCalculator.arrow(
                current: avgLowTreatmentAmount,
                previous: prevAvgLowTreatmentAmountPerDay
            )

            prevAvgLowTreatments = prevAvgLowTreatmentsPerDay
            prevAvgLowTreatmentAmount = prevAvgLowTreatmentAmountPerDay
            
            // Medel bolus (manuell + SMB) + uppdelning
            let prevAvgBolusPerDay = prevTotalBolus / periodDays
            avgBolusTrend = StatsTrendCalculator.arrow(current: avgBolus, previous: prevAvgBolusPerDay)

            let prevAvgManualBolusPerDay = prevManualBolusTotal / periodDays
            avgManualBolusTrend = StatsTrendCalculator.arrow(current: avgManualBolus, previous: prevAvgManualBolusPerDay)

            let prevAvgSMBPerDay = prevSMBTotal / periodDays
            avgSMBTrend = StatsTrendCalculator.arrow(current: avgSMB, previous: prevAvgSMBPerDay)
            
            prevAvgBolus = prevAvgBolusPerDay
            prevAvgManualBolus = prevAvgManualBolusPerDay
            prevAvgSMB = prevAvgSMBPerDay

            // Netto måltidsbolus och verklig insulinkvot
            let prevNetMealBolus: Double? = {
                guard let profile = prevProgrammedBasalValue else { return nil }
                let net = prevTDD - profile
                return net > 0 ? net : 0
            }()
            netMealBolusTrend = StatsTrendCalculator.arrow(current: netMealBolus, previous: prevNetMealBolus)

            let prevRealCarbRatio: Double? = {
                guard let net = prevNetMealBolus, net > 0 else { return nil }
                return prevAvgCarbsPerDay / net
            }()
            realCarbRatioTrend = StatsTrendCalculator.arrow(current: realCarbRatio, previous: prevRealCarbRatio)
            
            self.prevNetMealBolus = prevNetMealBolus
            self.prevRealCarbRatio = prevRealCarbRatio
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

    /// Genomsnittlig teoretisk profilbasal per dag över en given period.
    /// Vi delar upp perioden i kalenderdagar och räknar ut 24h-profilbasal för varje dag
    /// (baserat på den profil som gäller för den dagen via StatsProfileBasalEngine),
    /// och tar sedan snittet.
    private func averageProgrammedBasalOverPeriod(
        interval: DateInterval,
        days: Int
    ) -> Double {
        guard days > 0 else { return 0.0 }
        
        let calendar = Calendar.current
        var total = 0.0
        
        // Starta på kalenderdagens början för intervallets start
        var currentDayStart = calendar.startOfDay(for: interval.start)
        
        for _ in 0 ..< days {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else { break }
            
            let dayInterval = DateInterval(start: currentDayStart, end: nextDayStart)
            let dayBasalProfile = dataService.getBasalProfile(for: dayInterval)
            let dayBasal = calculateProgrammedBasalFromProfile(basalProfile: dayBasalProfile)
            total += dayBasal
            
            currentDayStart = nextDayStart
        }
        
        return total / Double(days)
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
