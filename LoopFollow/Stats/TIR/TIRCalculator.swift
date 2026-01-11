// LoopFollow
// TIRCalculator.swift

import Foundation

class TIRCalculator {
    static func calculate(bgData: [ShareGlucoseData], useTightRange: Bool = false) -> [TIRDataPoint] {
        guard !bgData.isEmpty else { return [] }
        
        // Normalize timestamps (seconds vs milliseconds) and de-duplicate readings.
        // Some call-sites may accidentally pass arrays that contain duplicates (e.g. mixed sources or repeated merges).
        // We bucket by 5-minute slots (300s) and keep the most recent reading per bucket.
        let rawCount = bgData.count
        let normalizedBG = normalizeAndDedupe(bgData)
        let dedupedCount = normalizedBG.count
        let dropped = rawCount - dedupedCount


        let veryLowThreshold = 54.0
        let lowThreshold = Double(UserDefaultsRepository.lowLine.value)
        let configuredHigh = Double(UserDefaultsRepository.highLine.value)
        let highThreshold = useTightRange ? configuredHigh : 180.0
        let veryHighThreshold = 250.0
        var periodData: [TIRPeriod: [Double]] = [:]
        let calendar = Calendar.current

        for reading in normalizedBG {
            let date = Date(timeIntervalSince1970: reading.date)
            let components = calendar.dateComponents([.hour], from: date)
            let hour = components.hour ?? 0

            let glucose = Double(reading.sgv)

            var period: TIRPeriod?
            if let hourRange = TIRPeriod.night.hourRange, hour >= hourRange.start, hour < hourRange.end {
                period = .night
            } else if let hourRange = TIRPeriod.morning.hourRange, hour >= hourRange.start, hour < hourRange.end {
                period = .morning
            } else if let hourRange = TIRPeriod.day.hourRange, hour >= hourRange.start, hour < hourRange.end {
                period = .day
            } else if let hourRange = TIRPeriod.evening.hourRange, hour >= hourRange.start, hour < hourRange.end {
                period = .evening
            }

            if let period = period {
                if periodData[period] == nil {
                    periodData[period] = []
                }
                periodData[period]?.append(glucose)
            }
        }

        var tirPoints: [TIRDataPoint] = []

        for period in [TIRPeriod.night, .morning, .day, .evening] {
            guard let readings = periodData[period], !readings.isEmpty else {
                tirPoints.append(TIRDataPoint(
                    period: period,
                    veryLow: 0.0,
                    low: 0.0,
                    inRange: 0.0,
                    high: 0.0,
                    veryHigh: 0.0
                ))
                continue
            }

            let percentages = calculatePercentages(readings: readings,
                                                   veryLowThreshold: veryLowThreshold,
                                                   lowThreshold: lowThreshold,
                                                   highThreshold: highThreshold,
                                                   veryHighThreshold: veryHighThreshold)

            tirPoints.append(TIRDataPoint(
                period: period,
                veryLow: percentages.veryLow,
                low: percentages.low,
                inRange: percentages.inRange,
                high: percentages.high,
                veryHigh: percentages.veryHigh
            ))
        }

        let allReadings = normalizedBG.map { Double($0.sgv) }
        let averagePercentages = calculatePercentages(readings: allReadings,
                                                      veryLowThreshold: veryLowThreshold,
                                                      lowThreshold: lowThreshold,
                                                      highThreshold: highThreshold,
                                                      veryHighThreshold: veryHighThreshold)

        /*
        // --- Sanity log (debug) ---
        let minTs = normalizedBG.min(by: { $0.date < $1.date })?.date ?? 0
        let maxTs = normalizedBG.max(by: { $0.date < $1.date })?.date ?? 0

        let total = allReadings.count
        let veryLowCount = allReadings.reduce(0) { $0 + ($1 < veryLowThreshold ? 1 : 0) }
        let lowCount = allReadings.reduce(0) { $0 + (($1 >= veryLowThreshold && $1 < lowThreshold) ? 1 : 0) }
        let inRangeCount = allReadings.reduce(0) { $0 + (($1 >= lowThreshold && $1 <= highThreshold) ? 1 : 0) }
        let highCount = allReadings.reduce(0) { $0 + (($1 > highThreshold && $1 <= veryHighThreshold) ? 1 : 0) }
        let veryHighCount = allReadings.reduce(0) { $0 + ($1 > veryHighThreshold ? 1 : 0) }

        let exactlyLowCount = allReadings.reduce(0) { $0 + ($1 == lowThreshold ? 1 : 0) }
        let exactlyHighCount = allReadings.reduce(0) { $0 + ($1 == highThreshold ? 1 : 0) }

        print(
            "[Sanity][TIRCalculator] raw=\(rawCount) deduped=\(dedupedCount) dropped=\(dropped) total=\(total) useTightRange=\(useTightRange) " +
            "thresholds(vl=<\(veryLowThreshold), l<\(lowThreshold), hi>\(highThreshold), vh>\(veryHighThreshold)) " +
            "counts(vl=\(veryLowCount), l=\(lowCount), in=\(inRangeCount), hi=\(highCount), vh=\(veryHighCount)) " +
            "exactlyLow=\(exactlyLowCount) exactlyHigh=\(exactlyHighCount) " +
            "min=\(Date(timeIntervalSince1970: minTs)) max=\(Date(timeIntervalSince1970: maxTs)) " +
            "pct(vl=\(averagePercentages.veryLow), l=\(averagePercentages.low), in=\(averagePercentages.inRange), hi=\(averagePercentages.high), vh=\(averagePercentages.veryHigh))"
        )
        // --- End sanity log ---
        */

        tirPoints.append(TIRDataPoint(
            period: .average,
            veryLow: averagePercentages.veryLow,
            low: averagePercentages.low,
            inRange: averagePercentages.inRange,
            high: averagePercentages.high,
            veryHigh: averagePercentages.veryHigh
        ))

        return tirPoints
    }

    private static func calculatePercentages(readings: [Double],
                                             veryLowThreshold: Double,
                                             lowThreshold: Double,
                                             highThreshold: Double,
                                             veryHighThreshold: Double) -> (veryLow: Double, low: Double, inRange: Double, high: Double, veryHigh: Double)
    {
        let total = Double(readings.count)
        guard total > 0 else {
            return (0.0, 0.0, 0.0, 0.0, 0.0)
        }

        var veryLowCount = 0
        var lowCount = 0
        var inRangeCount = 0
        var highCount = 0
        var veryHighCount = 0

        for glucose in readings {
            if glucose < veryLowThreshold {
                veryLowCount += 1
            } else if glucose < lowThreshold {
                lowCount += 1
            } else if glucose > veryHighThreshold {
                veryHighCount += 1
            } else if glucose > highThreshold {
                highCount += 1
            } else {
                inRangeCount += 1
            }
        }

        return (
            veryLow: (Double(veryLowCount) / total) * 100.0,
            low: (Double(lowCount) / total) * 100.0,
            inRange: (Double(inRangeCount) / total) * 100.0,
            high: (Double(highCount) / total) * 100.0,
            veryHigh: (Double(veryHighCount) / total) * 100.0
        )
    }
    
    /// Normalize timestamps to seconds and de-duplicate readings by 5-minute buckets.
    /// Keeps the most recent reading per bucket.
    private static func normalizeAndDedupe(_ input: [ShareGlucoseData]) -> [ShareGlucoseData] {
        // First normalize timestamps: if any entry looks like milliseconds since 1970, convert to seconds.
        let normalized: [ShareGlucoseData] = input.map { r in
            // Heuristic: seconds since 1970 ~ 1.7e9; milliseconds ~ 1.7e12
            if r.date > 10_000_000_000 { // > ~2286-11-20 in seconds, so likely ms
                return ShareGlucoseData(sgv: r.sgv, date: r.date / 1000.0, direction: r.direction)
            }
            return r
        }

        // Bucket by 5-minute slots.
        var byBucket: [Int: ShareGlucoseData] = [:]
        byBucket.reserveCapacity(normalized.count)

        for r in normalized {
            // Use nearest 5-minute slot to be robust to small timestamp jitter.
            let bucket = Int((r.date / 300.0).rounded())
            if let existing = byBucket[bucket] {
                if r.date > existing.date {
                    byBucket[bucket] = r
                }
            } else {
                byBucket[bucket] = r
            }
        }

        // Return sorted (oldest -> newest)
        return byBucket.values.sorted(by: { $0.date < $1.date })
    }

}
