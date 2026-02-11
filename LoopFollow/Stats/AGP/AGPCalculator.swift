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

class AGPDayByDayCalculator {
    /// Builds up to 14 daily series for a “day-by-day” overlay.
    /// Values are returned in mg/dL so we can reuse the fixed 0–360 mg/dL axis.
    static func calculate(bgData: [ShareGlucoseData], in interval: DateInterval) -> [AGPDaySeries] {
        guard !bgData.isEmpty else { return [] }

        let calendar = Calendar.current

        // Group readings by calendar day inside interval
        var grouped: [Date: [ShareGlucoseData]] = [:]
        for r in bgData {
            let d = Date(timeIntervalSince1970: r.date)
            guard d >= interval.start && d <= interval.end else { continue }
            let dayStart = calendar.startOfDay(for: d)
            grouped[dayStart, default: []].append(r)
        }

        let dayStarts = grouped.keys.sorted()
        let cappedDays = Array(dayStarts.prefix(14))

        var out: [AGPDaySeries] = []
        out.reserveCapacity(cappedDays.count)

        for dayStart in cappedDays {
            guard let readings = grouped[dayStart], !readings.isEmpty else { continue }
            // Calendar weekday: 1=Sunday ... 7=Saturday. Convert to ISO/SV: 1=Monday ... 7=Sunday.
            let calendarWeekday = calendar.component(.weekday, from: dayStart)
            let weekday = ((calendarWeekday + 5) % 7) + 1

            var points: [AGPDayPoint] = []
            points.reserveCapacity(readings.count)

            for r in readings {
                let d = Date(timeIntervalSince1970: r.date)
                let comps = calendar.dateComponents([.hour, .minute], from: d)
                let h = Double(comps.hour ?? 0)
                let m = Double(comps.minute ?? 0)
                let x = h + (m / 60.0)

                // ShareGlucoseData.sgv is always mg/dL in our pipeline.
                let yMgdl = Double(r.sgv)
                points.append(AGPDayPoint(xHour: x, yMgdl: yMgdl))
            }

            // Sort by x, de-dupe by 5-min bucket
            let sorted = points.sorted { $0.xHour < $1.xHour }
            var deduped: [AGPDayPoint] = []
            deduped.reserveCapacity(sorted.count)

            var lastBucket: Int?
            for p in sorted {
                let bucket = Int((p.xHour * 60.0 / 5.0).rounded())
                if lastBucket == bucket {
                    deduped[deduped.count - 1] = p
                } else {
                    deduped.append(p)
                    lastBucket = bucket
                }
            }

            out.append(AGPDaySeries(dayStart: dayStart, weekday: weekday, points: deduped))
        }

        return out
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
