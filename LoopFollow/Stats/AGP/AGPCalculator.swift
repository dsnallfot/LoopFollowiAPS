// LoopFollow
// AGPCalculator.swift

import Foundation

class AGPCalculator {
    static func calculate(bgData: [ShareGlucoseData]) -> [AGPDataPoint] {
        guard !bgData.isEmpty else { return [] }

        var hourData: [Int: [Double]] = [:]
        let calendar = Calendar.current

        for reading in bgData {
            let date = Date(timeIntervalSince1970: reading.date)
            let components = calendar.dateComponents([.hour], from: date)
            let hour = components.hour ?? 0

            let glucose = Double(reading.sgv)
            let glucoseMgdL = UserDefaultsRepository.units.value == "mg/dL" ? glucose : glucose * GlucoseConversion.mmolToMgDl

            if hourData[hour] == nil {
                hourData[hour] = []
            }
            hourData[hour]?.append(glucoseMgdL)
        }

        var agpPoints: [AGPDataPoint] = []
        for hour in 0 ..< 24 {
            guard let values = hourData[hour], !values.isEmpty else { continue }

            let sorted = values.sorted()
            let p5 = PercentileCalculator.percentile(sorted, p: 0.05)
            let p25 = PercentileCalculator.percentile(sorted, p: 0.25)
            let p50 = PercentileCalculator.percentile(sorted, p: 0.50)
            let p75 = PercentileCalculator.percentile(sorted, p: 0.75)
            let p95 = PercentileCalculator.percentile(sorted, p: 0.95)

            let convert: (Double) -> Double = { value in
                UserDefaultsRepository.units.value == "mg/dL" ? value : value * GlucoseConversion.mgDlToMmolL
            }

            let minutesSinceMidnight = hour * 60

            agpPoints.append(AGPDataPoint(
                timeOfDay: minutesSinceMidnight,
                p5: convert(p5),
                p25: convert(p25),
                p50: convert(p50),
                p75: convert(p75),
                p95: convert(p95)
            ))
        }

        // Sortera i tidsordning
        var sortedPoints = agpPoints.sorted { $0.timeOfDay < $1.timeOfDay }

        // För att undvika en visuell "lucka" mellan 23:00 och 24:00 i AGP-grafen
        // lägger vi till en extra punkt vid 24:00 (1440 minuter) – men bara om
        // vi faktiskt har data som når sista timmen (>= 23:00).
        //
        // För att göra övergången mer cirkulär låter vi 24:00-punkten ha samma
        // percentiler som 00:00-punkten (timeOfDay == 0). Då representerar segmentet
        // 23–24 rörelsen mot nästa dygns början istället för att bara “förlänga”
        // sista timmen. Vid “Idag”-vyn, där vi ännu inte nått midnatt och saknar
        // data i sista timmen, lägger vi inte till 24:00-punkten.
        if let first = sortedPoints.first,
           first.timeOfDay == 0,
           let last = sortedPoints.last,
           last.timeOfDay >= 23 * 60 {
            let extended = AGPDataPoint(
                timeOfDay: 24 * 60,
                p5: first.p5,
                p25: first.p25,
                p50: first.p50,
                p75: first.p75,
                p95: first.p95
            )
            sortedPoints.append(extended)
        }

        return sortedPoints
    }
}

class PercentileCalculator {
    static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0.0 }
        if sorted.count == 1 { return sorted[0] }

        let index = p * Double(sorted.count - 1)
        let lower = Int(index.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = index - Double(lower)

        return sorted[lower] * (1.0 - weight) + sorted[upper] * weight
    }
}
