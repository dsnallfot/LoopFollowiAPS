//
//  StatsProfileBasalEngine.swift
//  LoopFollow
//
//  Bygger upp en tidslinje av basalprofiler för statistik (senaste 90 dagarna).
//

import Foundation

final class StatsProfileBasalEngine {

    struct Snapshot {
        let createdAt: Date
        let basalProfile: [MainViewController.basalProfileStruct]
    }

    /// Sorterade snapshots i tidsordning (äldst först).
    private(set) var snapshots: [Snapshot] = []

    /// Ladda om profilhistoriken från Nightscout.
    /// Används bara för statistik (t.ex. 90 dagar).
    func refresh(daysBack: Int = 90, completion: @escaping (Error?) -> Void) {
        NightscoutUtils.fetchBasalProfilesSince(daysBack: daysBack) { result in
            switch result {
            case .failure(let error):
                LogManager.shared.log(
                    category: .nightscout,
                    message: "⚠️ StatsProfileBasalEngine refresh failed: \(error.localizedDescription)",
                    isDebug: true
                )
                completion(error)

            case .success(let docs):
                var temp: [Snapshot] = []

                for doc in docs {
                    guard
                        let createdAtString = doc.created_at,
                        let createdAt = NightscoutUtils.parseDate(createdAtString),
                        let storeDict = doc.store
                    else {
                        continue
                    }

                    // Försök först med defaultProfile, annars "default"/"Default"
                    let profileKey = doc.defaultProfile ?? "default"
                    let store = storeDict[profileKey]
                        ?? storeDict["default"]
                        ?? storeDict["Default"]

                    guard let statsStore = store else {
                        continue
                    }

                    let basal = statsStore.basal
                    guard !basal.isEmpty else { continue }

                    temp.append(
                        Snapshot(createdAt: createdAt, basalProfile: basal)
                    )
                }

                // Sortera i kronologisk ordning
                temp.sort { $0.createdAt < $1.createdAt }
                self.snapshots = temp

                LogManager.shared.log(
                    category: .analysis,
                    message: "✅ StatsProfileBasalEngine loaded \(temp.count) basal profile snapshots for stats",
                    isDebug: true
                )
                completion(nil)
            }
        }
    }

    /// Returnera basalprofilen som gällde vid ett visst datum.
    /// Vi väljer senaste snapshot vars createdAt <= date.
    func basalProfile(for date: Date) -> [MainViewController.basalProfileStruct]? {
        guard !snapshots.isEmpty else { return nil }

        var chosen: Snapshot?

        for snap in snapshots {
            if snap.createdAt <= date {
                chosen = snap
            } else {
                break
            }
        }

        // Om inget snapshot har createdAt <= date (mycket tidig dag),
        // använd det äldsta vi har som fallback.
        return (chosen ?? snapshots.first)?.basalProfile
    }

    /// Praktisk helper: hämta profil för ett helt intervall.
    /// Just nu använder vi start-tidpunkt (t.ex. midnatt).
    func basalProfile(for interval: DateInterval) -> [MainViewController.basalProfileStruct]? {
        return basalProfile(for: interval.start)
    }

    /// (Valfritt) Hitta alla datum då basalen ändrades inom ett intervall.
    func changeDates(in interval: DateInterval) -> [Date] {
        snapshots
            .map { $0.createdAt }
            .filter { interval.contains($0) }
    }
}
