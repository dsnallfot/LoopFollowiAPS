import Foundation
import HealthKit

struct BasalIOBCalculator {

    /// Fiasp-decay som fraktion av ursprunglig dos (0–7h).
    /// Index = timmar sedan insulin gavs.
    /// 1.0 = 100%, 0.70 = 70% etc.
    private static let decayFractions: [Double] = [
        1.0,   // 0h
        0.70,  // 1h
        0.35,  // 2h
        0.15,  // 3h
        0.06,  // 4h
        0.025, // 5h
        0.01,  // 6h
        0.0    // 7h+
    ]

    /// Plockar ut ett komplett 24h-array med basalhastighet (E/h) per heltimme
    /// från profilens "punkter" (timeAsSeconds, value).
    static func basalRatesPerHour(
        from basalSchedule: [ProfileManager.TimeValue<Double>]
    ) -> [Double] {
        var basalRates = Array(repeating: 0.0, count: 24)
        var lastBasal: Double?
        var basalDict: [Int: Double] = [:]

        for entry in basalSchedule {
            let hour = entry.timeAsSeconds / 3600
            basalDict[hour] = entry.value
        }

        for hour in 0..<24 {
            if let newBasal = basalDict[hour] {
                lastBasal = newBasal
            }
            basalRates[hour] = lastBasal ?? 0.0
        }

        return basalRates
    }
    
    /// Beräknar basal-IOB för en specifik tidpunkt baserat på basalprofilen.
    /// Antagande: profilen har varit aktiv tillräckligt länge för steady state.
    static func basalIOBNow(
        from basalSchedule: [ProfileManager.TimeValue<Double>],
        at date: Date = Date()
    ) -> Double {
        let basalRates = basalRatesPerHour(from: basalSchedule)
        let hour = Calendar.current.component(.hour, from: date) // 0–23

        var iobUnits = 0.0

        // Gå bakåt i tiden 0–7h och summera bidrag
        for k in 0..<decayFractions.count {
            let fraction = decayFractions[k]
            if fraction == 0 { continue }

            let sourceHour = (hour - k + 24) % 24
            let basalRate = basalRates[sourceHour]   // E/h
            let unitsDeliveredThisHour = basalRate   // * 1h

            iobUnits += unitsDeliveredThisHour * fraction
        }

        return iobUnits
    }

    /// Beräknar basal-IOB per heltimme i dygnet.
    ///
    /// Returnerar ScheduleEntry så du kan mata det rakt in i din view.
    /// value = antal E aktiv basal (IOB) vid den timmen (steady state).
    static func computeBasalIOBSchedule(
        from basalSchedule: [ProfileManager.TimeValue<Double>]
    ) -> [ScheduleEntry] {

        let basalRates = basalRatesPerHour(from: basalSchedule)   // E/h per timme
        var result: [ScheduleEntry] = []

        for hour in 0..<24 {
            var iobUnits = 0.0

            // Gå bakåt i tiden 0–7h och summera bidrag
            for k in 0..<decayFractions.count {
                let fraction = decayFractions[k]
                if fraction == 0 { continue }

                // timme då den "gamla" basalen gavs
                // wrappar runt dygnet så profilen antas upprepa sig
                let sourceHour = (hour - k + 24) % 24

                let basalRate = basalRates[sourceHour]   // E/h
                let unitsDeliveredThisHour = basalRate   // * 1h

                iobUnits += unitsDeliveredThisHour * fraction
            }

            let timeString = String(format: "%02d:00", hour)
            let valueString = String(format: "%.2f", iobUnits)

            result.append(ScheduleEntry(time: timeString, value: valueString))
        }

        return result
    }

    /// Om du vill ha samma format som profilens "TimeValue" (med timeAsSeconds)
    /// istället för ScheduleEntry:
    static func computeBasalIOBTimeValues(
        from basalSchedule: [ProfileManager.TimeValue<Double>]
    ) -> [ProfileManager.TimeValue<Double>] {

        let basalRates = basalRatesPerHour(from: basalSchedule)
        var result: [ProfileManager.TimeValue<Double>] = []

        for hour in 0..<24 {
            var iobUnits = 0.0

            for k in 0..<decayFractions.count {
                let fraction = decayFractions[k]
                if fraction == 0 { continue }

                let sourceHour = (hour - k + 24) % 24
                let basalRate = basalRates[sourceHour]
                iobUnits += basalRate * fraction
            }

            let seconds = hour * 3600
            result.append(ProfileManager.TimeValue(timeAsSeconds: seconds,
                                                   value: iobUnits))
        }

        return result
    }
}
