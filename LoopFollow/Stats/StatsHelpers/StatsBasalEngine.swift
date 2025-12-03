// LoopFollow
// StatsBasalEngine.swift
//
// En liten motor som simulerar faktiskt levererad basal
// genom 0.05 E-pulser, baserat på piecewise-constant basalrate (U/h).

import Foundation

struct StatsBasalEngine {

    /// En basaländring: från `date` gäller `rateUph` (U/h)
    /// fram till nästa event eller intervallets slut.
    struct BasalChangeEvent {
        let date: Date
        let rateUph: Double   // units per hour
    }

    /// En simulerad basalpuls – t.ex. 0.05 E vid en viss tidpunkt.
    struct BasalPulse {
        let date: Date
        let units: Double
    }

    struct Result {
        /// Summa levererad basal inom intervallet (summerad över alla pulser).
        let totalUnits: Double
        /// Alla enskilda pulser (kan användas för grafer eller debug).
        let pulses: [BasalPulse]
        /// Eventuellt kvarvarande "odeliverad" basal < pulseSize efter sista segmentet.
        let residualUnits: Double
    }

    /// Simulera levererad basal i 0.05 E-pulser över ett givet tidsintervall.
    ///
    /// - Parameters:
    ///   - events: Basaländringar (måste minst innehålla alla ändringspunkter som berör intervallet).
    ///   - interval: Tidsfönster vi vill integrera över.
    ///   - pulseSize: Storleken per puls, standard 0.05 E.
    ///   - carryOverUndeliveredBasals:
    ///       Om true -> "undeliverad" mängd (< pulseSize) förs vidare till nästa segment.
    ///       Om false -> nollställs vid segmentgränser (t.ex. vid basal=0 eller avbrott).
    static func simulateDeliveredBasal(
        events: [BasalChangeEvent],
        in interval: DateInterval,
        pulseSize: Double = 0.05,
        carryOverUndeliveredBasals: Bool = false
    ) -> Result {
        // Tomt eller inget tidsfönster → inget levererat
        guard !events.isEmpty, interval.duration > 0 else {
            return Result(totalUnits: 0, pulses: [], residualUnits: 0)
        }

        // Sortera säkerhetsmässigt (skulle gärna vara sorterat redan)
        let sorted = events.sorted { $0.date < $1.date }

        var total: Double = 0
        var pulses: [BasalPulse] = []
        var residual: Double = 0  // odeliverad basalmängd (< pulseSize) från föregående segment

        // Vi loopar över varje event och använder nästa events tid som segmentEnd
        for (idx, evt) in sorted.enumerated() {
            // Segmentet gäller från denna tidpunkt...
            let rawSegmentStart = evt.date
            // ...till nästa event eller intervallets slut
            let rawSegmentEnd: Date = {
                if idx + 1 < sorted.count {
                    return sorted[idx + 1].date
                } else {
                    return interval.end
                }
            }()

            // Klipp segmentet till vårt intresseintervall
            let segmentStart = max(rawSegmentStart, interval.start)
            let segmentEnd = min(rawSegmentEnd, interval.end)

            // Om segmentet inte överlappar intervallet hoppar vi
            guard segmentStart < segmentEnd else { continue }

            let rate = evt.rateUph
            // 0 U/h = avstängd basal => inget mer än ev. residual-hantering
            guard rate > 0 else {
                if !carryOverUndeliveredBasals {
                    residual = 0
                }
                continue
            }

            let ratePerSec = rate / 3600.0
            var t = segmentStart
            var accum = carryOverUndeliveredBasals ? residual : 0.0

            while true {
                let remaining = pulseSize - accum
                let dt = remaining / ratePerSec                 // sekunder till nästa puls
                let candidateTime = t.addingTimeInterval(dt)

                if candidateTime > segmentEnd {
                    // Vi hinner inte nå en full puls innan segmentet tar slut
                    let deltaT = segmentEnd.timeIntervalSince(t)
                    if deltaT > 0 {
                        accum += ratePerSec * deltaT
                        t = segmentEnd
                    }
                    break
                }

                // Vi når en ny puls inom segmentet
                t = candidateTime
                if t >= interval.start {
                    total += pulseSize
                    pulses.append(BasalPulse(date: t, units: pulseSize))
                }
                // Efter en levererad puls börjar vi om ackumulatorn
                accum = 0.0
            }

            // Spara ev. odelad andel till nästa segment (om vi vill)
            residual = carryOverUndeliveredBasals ? accum : 0.0

            // Om vi redan nått intervallets slut kan vi avbryta
            if t >= interval.end {
                break
            }
        }

        return Result(totalUnits: total,
                      pulses: pulses,
                      residualUnits: residual)
    }
}
