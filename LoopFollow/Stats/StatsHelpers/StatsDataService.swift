// LoopFollow
// StatsDataService.swift


import Foundation

// Enkel persistent cache för statistikdata (bolus, SMB, kolhydrater, basal).
// Lagrar upp till 90 dagar och används för att minska Nightscout-förfrågningar.
private class StatsCacheManager {
    static let shared = StatsCacheManager()
    private init() {}

    private struct CachedBolus: Codable {
        let value: Double
        let date: Double
        let sgv: Int
    }

    private struct CachedCarb: Codable {
        let value: Double
        let date: Double
        let sgv: Int
        let absorptionTime: Int
        let foodType: String?
        let fat: Double
        let protein: Double
    }

    private struct CachedBasal: Codable {
        let basalRate: Double
        let date: Double
    }

    private struct CachedBG: Codable {
        let sgv: Int
        let date: Double
        let direction: String?
    }

    private struct CachedBGCheck: Codable {
        let date: Double
    }

    private struct Cache: Codable {
        let lastUpdated: Date
        let bg: [CachedBG]
        let bgChecks: [CachedBGCheck]
        let bolus: [CachedBolus]
        let smb: [CachedBolus]
        let carbs: [CachedCarb]
        let basal: [CachedBasal]
    }

    private var cacheURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("StatsCache.json")
    }

    /// Läs in cache från disk och applicera på MainViewController (endast de senaste 90 dagarna).
    func loadInto(mainVC: MainViewController) {
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let cache = try decoder.decode(Cache.self, from: data)

            let now = Date()
            let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970

            let bg = cache.bg
                .filter { $0.date >= cutoff }
                .map { ShareGlucoseData(sgv: $0.sgv, date: $0.date, direction: $0.direction) }

            let bolus = cache.bolus
                .filter { $0.date >= cutoff }
                .map { MainViewController.bolusGraphStruct(value: $0.value, date: $0.date, sgv: $0.sgv) }

            let smb = cache.smb
                .filter { $0.date >= cutoff }
                .map { MainViewController.bolusGraphStruct(value: $0.value, date: $0.date, sgv: $0.sgv) }

            let carbs = cache.carbs
                .filter { $0.date >= cutoff }
                .map {
                    MainViewController.carbGraphStruct(
                        value: $0.value,
                        date: $0.date,
                        sgv: $0.sgv,
                        absorptionTime: $0.absorptionTime,
                        foodType: $0.foodType ?? "",
                        fat: $0.fat,
                        protein: $0.protein
                    )
                }

            let basal = cache.basal
                .filter { $0.date >= cutoff }
                .map { MainViewController.basalGraphStruct(basalRate: $0.basalRate, date: $0.date) }

            let bgChecks = cache.bgChecks
                .filter { $0.date >= cutoff }
                .map { $0.date }

            // Skriv över befintlig statsdata med cachen (vi utgår från att MainViewController precis initierats)
            mainVC.statsBGData = bg
            mainVC.statsBGCheckData = bgChecks
            mainVC.statsBolusData = bolus
            mainVC.statsSMBData = smb
            mainVC.statsCarbData = carbs
            mainVC.statsBasalData = basal
            
            // Spara senaste uppdateringstid från cachen
            mainVC.statsCacheLastUpdated = cache.lastUpdated
            
            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - cache loaded: bg=\(bg.count), bgChecks=\(bgChecks.count), bolus=\(bolus.count), smb=\(smb.count), carbs=\(carbs.count), basal=\(basal.count)",
                isDebug: true
            )
        } catch {
            // Ingen cache ännu eller så gick det fel att läsa – ignoreras tyst.
            LogManager.shared.log(category: .analysis, message: "StatsCacheManager - no cache loaded (\(error.localizedDescription))", isDebug: true)
        }
    }

    /// Spara aktuella stats-arrayer från MainViewController till disk (endast de senaste 90 dagarna).
    ///
    /// Viktigt:
    ///  • Vi MERGAR alltid mot befintlig cache om den finns, så att en tillfällig 24h-fetch
    ///    inte kan skriva över ett tidigare 30–90-dagarsfönster.
    ///  • För treatments (bolus/SMB/kolhydrater/basal/BG-checks) behandlas de senaste 24 timmarna
    ///    som en "sanningskälla" från Nightscout – vi slänger cache-data i det fönstret och ersätter
    ///    med ny snapshot varje gång, för att fånga raderade/ändrade events.
    func saveFrom(mainVC: MainViewController) {
        let now = Date()
        let horizonCutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        let recentCutoff = now.addingTimeInterval(-24 * 60 * 60).timeIntervalSince1970

        // 1) Bygg upp "nya" arrayer från MainViewController (begränsade till 90 dagar bakåt)
        let newBG = mainVC.statsBGData
            .filter { $0.date >= horizonCutoff }
            .map { CachedBG(sgv: $0.sgv, date: $0.date, direction: $0.direction) }

        let newBGChecks = mainVC.statsBGCheckData
            .filter { $0 >= horizonCutoff }
            .map { CachedBGCheck(date: $0) }

        let newBolus = mainVC.statsBolusData
            .filter { $0.date >= horizonCutoff }
            .map { CachedBolus(value: $0.value, date: $0.date, sgv: $0.sgv) }

        let newSMB = mainVC.statsSMBData
            .filter { $0.date >= horizonCutoff }
            .map { CachedBolus(value: $0.value, date: $0.date, sgv: $0.sgv) }

        let newCarbs = mainVC.statsCarbData
            .filter { $0.date >= horizonCutoff }
            .map {
                CachedCarb(
                    value: $0.value,
                    date: $0.date,
                    sgv: $0.sgv,
                    absorptionTime: $0.absorptionTime,
                    foodType: $0.foodType,
                    fat: $0.fat,
                    protein: $0.protein
                )
            }

        let newBasal = mainVC.statsBasalData
            .filter { $0.date >= horizonCutoff }
            .map { CachedBasal(basalRate: $0.basalRate, date: $0.date) }

        // Om ALL ny data är tom, spara inte – skriv inte över en ev. befintlig cache
        // med en helt tom snapshot.
        if newBG.isEmpty && newBGChecks.isEmpty && newBolus.isEmpty && newSMB.isEmpty && newCarbs.isEmpty && newBasal.isEmpty {
            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - skipping save (all stats arrays are empty)",
                isDebug: true
            )
            return
        }

        // 2) Läs in befintlig cache om den finns, så vi kan MERGA 24h-fönster in i ett
        // redan uppbyggt 30–90-dagarsfönster.
        var existingCache: Cache?
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            existingCache = try decoder.decode(Cache.self, from: data)
        } catch {
            existingCache = nil
        }

        // 3) Slå ihop gammal och ny data per timestamp.
        //    • BG: klassisk merge, ny data vinner, behåll upp till 90 dagar.
        //    • Treatments/BG-checks: behåll gammal historik äldre än 24h, men ersätt
        //      allt inom de senaste 24h med ny snapshot.
        let mergedBG = mergeBG(old: existingCache?.bg ?? [], new: newBG, horizonCutoff: horizonCutoff)
        let mergedBGChecks = mergeBGChecks(old: existingCache?.bgChecks ?? [], new: newBGChecks, horizonCutoff: horizonCutoff, recentCutoff: recentCutoff)
        let mergedBolus = mergeBolus(old: existingCache?.bolus ?? [], new: newBolus, horizonCutoff: horizonCutoff, recentCutoff: recentCutoff)
        let mergedSMB = mergeBolus(old: existingCache?.smb ?? [], new: newSMB, horizonCutoff: horizonCutoff, recentCutoff: recentCutoff)
        let mergedCarbs = mergeCarbs(old: existingCache?.carbs ?? [], new: newCarbs, horizonCutoff: horizonCutoff, recentCutoff: recentCutoff)
        let mergedBasal = mergeBasal(old: existingCache?.basal ?? [], new: newBasal, horizonCutoff: horizonCutoff, recentCutoff: recentCutoff)

        let cache = Cache(
            lastUpdated: now,
            bg: mergedBG,
            bgChecks: mergedBGChecks,
            bolus: mergedBolus,
            smb: mergedSMB,
            carbs: mergedCarbs,
            basal: mergedBasal
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
            
            // Uppdatera senast-uppdaterad-tid i MainViewController
                mainVC.statsCacheLastUpdated = now
            
            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - cache saved: bg=\(mergedBG.count), bgChecks=\(mergedBGChecks.count), bolus=\(mergedBolus.count), smb=\(mergedSMB.count), carbs=\(mergedCarbs.count), basal=\(mergedBasal.count)",
                isDebug: true
            )
        } catch {
            LogManager.shared.log(category: .analysis, message: "StatsCacheManager - failed to save cache: \(error.localizedDescription)", isDebug: true)
        }
    }

    // MARK: - Merge helpers

    /// Slår ihop BG från befintlig cache och ny snapshot. Ny data vinner på samma timestamp.
    private func mergeBG(old: [CachedBG], new: [CachedBG], horizonCutoff: Double) -> [CachedBG] {
        var dict: [Int: CachedBG] = [:]

        // Behåll upp till 90 dagar från befintlig cache
        for item in old where item.date >= horizonCutoff {
            dict[Int(item.date)] = item
        }
        // Mergas in med ny data (vinner vid krock)
        for item in new where item.date >= horizonCutoff {
            dict[Int(item.date)] = item
        }

        return dict.values.sorted { $0.date < $1.date }
    }

    /// Slår ihop BG-kontroller från befintlig cache och ny snapshot.
    /// Äldre än 24h: behåll cache + lägg till ev. nya.
    /// Senaste 24h: byggs helt från ny snapshot.
    private func mergeBGChecks(old: [CachedBGCheck], new: [CachedBGCheck], horizonCutoff: Double, recentCutoff: Double) -> [CachedBGCheck] {
        var set: Set<Int> = []
        var merged: [CachedBGCheck] = []

        // Behåll bara äldre än 24h men inom 90-dagarsfönstret från cache
        for item in old where item.date >= horizonCutoff && item.date < recentCutoff {
            let key = Int(item.date)
            if !set.contains(key) {
                set.insert(key)
                merged.append(item)
            }
        }

        // Lägg till all ny data inom 90 dagar (inklusive senaste 24h)
        for item in new where item.date >= horizonCutoff {
            let key = Int(item.date)
            if !set.contains(key) {
                set.insert(key)
                merged.append(item)
            }
        }

        return merged.sorted { $0.date < $1.date }
    }

    /// Slår ihop bolus/SMB-data (samma struktur) från befintlig cache och ny snapshot.
    /// Äldre än 24h: behåll cache + lägg till ev. nya.
    /// Senaste 24h: byggs helt från ny snapshot.
    private func mergeBolus(old: [CachedBolus], new: [CachedBolus], horizonCutoff: Double, recentCutoff: Double) -> [CachedBolus] {
        var dict: [Int: CachedBolus] = [:]

        // Behåll bara äldre än 24h men inom 90-dagarsfönstret från cache
        for item in old where item.date >= horizonCutoff && item.date < recentCutoff {
            dict[Int(item.date)] = item
        }

        // Lägg till all ny data inom 90 dagar (inklusive senaste 24h)
        for item in new where item.date >= horizonCutoff {
            dict[Int(item.date)] = item // ny data vinner vid krock
        }

        return dict.values.sorted { $0.date < $1.date }
    }

    /// Slår ihop kolhydratdata från befintlig cache och ny snapshot.
    /// Äldre än 24h: behåll cache + lägg till ev. nya.
    /// Senaste 24h: byggs helt från ny snapshot.
    private func mergeCarbs(old: [CachedCarb], new: [CachedCarb], horizonCutoff: Double, recentCutoff: Double) -> [CachedCarb] {
        var dict: [Int: CachedCarb] = [:]

        // Behåll bara äldre än 24h men inom 90-dagarsfönstret från cache
        for item in old where item.date >= horizonCutoff && item.date < recentCutoff {
            dict[Int(item.date)] = item
        }

        // Lägg till all ny data inom 90 dagar (inklusive senaste 24h)
        for item in new where item.date >= horizonCutoff {
            dict[Int(item.date)] = item
        }

        return dict.values.sorted { $0.date < $1.date }
    }

    /// Slår ihop basaldata från befintlig cache och ny snapshot.
    /// Äldre än 24h: behåll cache + lägg till ev. nya.
    /// Senaste 24h: byggs helt från ny snapshot.
    private func mergeBasal(old: [CachedBasal], new: [CachedBasal], horizonCutoff: Double, recentCutoff: Double) -> [CachedBasal] {
        var dict: [Int: CachedBasal] = [:]

        // Behåll bara äldre än 24h men inom 90-dagarsfönstret från cache
        for item in old where item.date >= horizonCutoff && item.date < recentCutoff {
            dict[Int(item.date)] = item
        }

        // Lägg till all ny data inom 90 dagar (inklusive senaste 24h)
        for item in new where item.date >= horizonCutoff {
            dict[Int(item.date)] = item
        }

        return dict.values.sorted { $0.date < $1.date }
    }
}

extension MainViewController {
    /// Ladda statistikcache (om den finns) in i denna MainViewController.
    func stats_loadFromCacheIfAvailable() {
        StatsCacheManager.shared.loadInto(mainVC: self)
    }

    /// Spara aktuella stats-arrayer från denna MainViewController till cache.
    func stats_saveToCache() {
        StatsCacheManager.shared.saveFrom(mainVC: self)
    }

    func stats_syncBGFromLive() {
        let now = Date().timeIntervalSince1970
        let horizonDays: Double = 90          // ska matcha StatsDataFetcher.maxCachedDays
        let horizonCutoff = now - horizonDays * 24 * 60 * 60

        // 1. Trimma bort riktigt gammal historik (äldre än 90 dagar)
        statsBGData.removeAll { $0.date < horizonCutoff }

        // 2. Börja med befintlig historik inom fönstret
        var merged: [ShareGlucoseData] = statsBGData

        // De-dupe keys by 5-minute buckets to avoid double-counting between NS + live sources.
        // Use rounded bucket to be robust to small timestamp jitter.
        var existingBuckets = Set(merged.map { Int(($0.date / 300.0).rounded()) })

        // 3. Lägg till live-BG från huvudgrafen inom [horizonCutoff, now]
        for reading in bgData {
            let t = reading.date
            if t < horizonCutoff || t > now { continue }

            let bucket = Int(((t) / 300.0).rounded())
            if !existingBuckets.contains(bucket) {
                merged.append(reading)
                existingBuckets.insert(bucket)
            }
        }

        merged.sort { $0.date < $1.date }
        statsBGData = merged
    }

    func stats_syncTreatmentsFromLive() {
        let now = Date().timeIntervalSince1970
        let horizonDays: Double = 90          // ska matcha StatsDataFetcher.maxCachedDays
        let horizonCutoff = now - horizonDays * 24 * 60 * 60

        // MARK: Bolus
        statsBolusData.removeAll { $0.date < horizonCutoff }
        var mergedBolus = statsBolusData
        var existingBolus = Set(mergedBolus.map { Int($0.date) })

        for b in bolusData {
            let t = b.date
            if t < horizonCutoff || t > now { continue }

            let key = Int(t)
            if !existingBolus.contains(key) {
                mergedBolus.append(b)
                existingBolus.insert(key)
            }
        }
        mergedBolus.sort { $0.date < $1.date }
        statsBolusData = mergedBolus

        // MARK: SMB
        statsSMBData.removeAll { $0.date < horizonCutoff }
        var mergedSMB = statsSMBData
        var existingSMB = Set(mergedSMB.map { Int($0.date) })

        for s in smbData {
            let t = s.date
            if t < horizonCutoff || t > now { continue }

            let key = Int(t)
            if !existingSMB.contains(key) {
                mergedSMB.append(s)
                existingSMB.insert(key)
            }
        }
        mergedSMB.sort { $0.date < $1.date }
        statsSMBData = mergedSMB

        // MARK: Carbs
        statsCarbData.removeAll { $0.date < horizonCutoff || $0.date > now }
        var mergedCarbs = statsCarbData
        var existingCarbs = Set(mergedCarbs.map { Int($0.date) })

        for c in carbData {
            let t = c.date
            if t < horizonCutoff || t > now { continue }

            let key = Int(t)
            if !existingCarbs.contains(key) {
                mergedCarbs.append(c)
                existingCarbs.insert(key)
            }
        }
        mergedCarbs.sort { $0.date < $1.date }
        statsCarbData = mergedCarbs

        // MARK: Basal
        statsBasalData.removeAll { $0.date < horizonCutoff }
        var mergedBasal = statsBasalData
        var existingBasal = Set(mergedBasal.map { Int($0.date) })

        for b in basalData {
            let t = b.date
            if t < horizonCutoff || t > now { continue }

            let key = Int(t)
            if !existingBasal.contains(key) {
                mergedBasal.append(b)
                existingBasal.insert(key)
            }
        }
        mergedBasal.sort { $0.date < $1.date }
        statsBasalData = mergedBasal

        // MARK: BG Checks
        statsBGCheckData.removeAll { $0 < horizonCutoff }
        var mergedBGChecks = statsBGCheckData
        var existingBGChecks = Set(mergedBGChecks.map { Int($0) })

        for check in bgCheckData {
            let t = check.date
            if t < horizonCutoff || t > now { continue }

            let key = Int(t)
            if !existingBGChecks.contains(key) {
                mergedBGChecks.append(t)
                existingBGChecks.insert(key)
            }
        }
        mergedBGChecks.sort { $0 < $1 }
        statsBGCheckData = mergedBGChecks
    }
}

class StatsDataService {
    weak var mainViewController: MainViewController?

    var daysToAnalyze: Int = 14
    var isTodayOnly: Bool = false
    var isOneDayOnly: Bool = false
    private let dataFetcher: StatsDataFetcher
    private let maxStatsDays: Int = 90
    // Om satt används detta intervall som analysfönster istället för rullande daysToAnalyze-baserat fönster.
    var customInterval: DateInterval?

    // Motor för historisk profilbasal (statistik)
    private let statsBasalEngine = StatsProfileBasalEngine()
    
    struct DailyBasalStat {
        let dayStart: Date
        let totalUnits: Double
    }
    
    private struct BGIntervalKey: Hashable {
        let start: Int   // seconds since 1970
        let end: Int     // seconds since 1970
    }

    // Enkel cache per intervall
    private var bgCache: [BGIntervalKey: [ShareGlucoseData]] = [:]
    private var basalCache: [BGIntervalKey: [DailyBasalStat]] = [:]

    func clearBGCache() {
        bgCache.removeAll()
        basalCache.removeAll()
    }

    init(mainViewController: MainViewController?) {
        self.mainViewController = mainViewController
        dataFetcher = StatsDataFetcher(mainViewController: mainViewController)

        // Ladda ev. cache direkt in i MainViewController när tjänsten skapas
        if let mainVC = mainViewController {
            mainVC.stats_loadFromCacheIfAvailable()
        }

        // Ladda historisk profilbasal för statistik (upp till maxStatsDays)
        statsBasalEngine.refresh(daysBack: maxStatsDays) { error in
            if let error = error {
                LogManager.shared.log(
                    category: .analysis,
                    message: "StatsProfileBasalEngine refresh error: \(error.localizedDescription)",
                    isDebug: true
                )
            } else {
                LogManager.shared.log(
                    category: .analysis,
                    message: "StatsProfileBasalEngine refresh completed",
                    isDebug: true
                )
            }
        }
    }

    func ensureDataAvailable(onProgress: @escaping () -> Void, completion: @escaping () -> Void) {
        guard let mainVC = mainViewController else {
            completion()
            return
        }

        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }

        let oldestBG = mainVC.statsBGData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestBolus = mainVC.statsBolusData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestCarb = mainVC.statsCarbData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date
        let oldestBasal = mainVC.statsBasalData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .min(by: { $0.date < $1.date })?.date

        // Äldsta treatment-datum inom analysfönstret (bolus/kolhydrat/basal).
        let oldestTreatmentInScope = min(
            oldestBolus ?? .greatestFiniteMagnitude,
            oldestCarb ?? .greatestFiniteMagnitude,
            oldestBasal ?? .greatestFiniteMagnitude
        )

        let bgDataCount = mainVC.statsBGData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let bolusDataCount = mainVC.statsBolusData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let carbDataCount = mainVC.statsCarbData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count
        let basalDataCount = mainVC.statsBasalData
            .filter { $0.date >= cutoffTime && $0.date <= now }
            .count

        // Freshness: senaste datapunkt får inte vara äldre än 48 timmar,
        // annars betraktar vi datat som "stale" och triggar en ny 90-dagarsfetch.
        let newestBG = mainVC.statsBGData.max(by: { $0.date < $1.date })?.date
        let newestBolus = mainVC.statsBolusData.max(by: { $0.date < $1.date })?.date
        let newestCarb = mainVC.statsCarbData.max(by: { $0.date < $1.date })?.date
        let newestBasal = mainVC.statsBasalData.max(by: { $0.date < $1.date })?.date

        let newestTreatment = max(newestBolus ?? 0, newestCarb ?? 0, newestBasal ?? 0)

        let freshnessThreshold: TimeInterval = 48 * 60 * 60
        let isBGStale = (newestBG == nil) || (now - (newestBG ?? 0)) > freshnessThreshold
        let isTreatmentStale = (newestTreatment == 0) || (now - newestTreatment) > freshnessThreshold

        LogManager.shared.log(
            category: .analysis,
            message: "StatsDataService - freshness BG: isStale=\(isBGStale), newestBG=\(String(describing: newestBG)); treatments: isStale=\(isTreatmentStale), newestTreatment=\(newestTreatment), oldestTreatmentInScope=\(oldestTreatmentInScope), cutoffTime=\(cutoffTime))",
            isDebug: true
        )

        let minExpectedBGEntries = max(daysToAnalyze * 6, 12)
        let hasEnoughBGData = !isBGStale &&
            bgDataCount >= minExpectedBGEntries

        let minExpectedTreatmentEntries = max(daysToAnalyze, 1)

        // Kräv att vi både har "färska" treatments OCH att den äldsta
        // inom stats-fönstret faktiskt ligger ungefär vid cutoff eller tidigare.
        // Annars har vi bara de sista dagarna, och saknar äldre historik.
        let windowSlack: TimeInterval = 6 * 60 * 60 // tillåt t.ex. upp till 6h lucka från exakt cutoff
        let coversFullWindow = oldestTreatmentInScope <= (cutoffTime + windowSlack)

        let hasEnoughTreatmentData = !isTreatmentStale &&
            coversFullWindow &&
            (bolusDataCount + carbDataCount + basalDataCount) >= minExpectedTreatmentEntries

        if !hasEnoughBGData {
            // Bootstrap med upp till 90 dagars data i cachen.
            dataFetcher.fetchBGData(days: maxStatsDays) {
                DispatchQueue.main.async {
                    onProgress()
                }

                if !hasEnoughTreatmentData {
                    self.dataFetcher.fetchTreatmentsData(days: self.maxStatsDays) {
                        DispatchQueue.main.async {
                            onProgress()
                            mainVC.stats_saveToCache()
                            completion()
                        }
                    }
                } else {
                    mainVC.stats_saveToCache()
                    completion()
                }
            }
        } else if !hasEnoughTreatmentData {
            // Vi har tillräckligt med BG, men för lite treatments – fyll upp hela 90-dagarsfönstret.
            dataFetcher.fetchTreatmentsData(days: maxStatsDays) {
                DispatchQueue.main.async {
                    onProgress()
                    mainVC.stats_saveToCache()
                    completion()
                }
            }
        } else {
            completion()
        }
    }
    
    /// Tvinga omladdning av BG + treatments från Nightscout för nuvarande period (daysToAnalyze).
    /// Används av "Ladda om"-knappen för att garantera att senaste data hämtas.
    func reloadAllData(onProgress: @escaping () -> Void, completion: @escaping () -> Void) {
        // För omladdning vill vi endast hämta de senaste 48 timmarna från Nightscout.
        let recentDays = 2

        dataFetcher.fetchBGData(days: recentDays) {
            DispatchQueue.main.async {
                onProgress()
                self.dataFetcher.fetchTreatmentsData(days: recentDays) {
                    DispatchQueue.main.async {
                        onProgress()
                        if let mainVC = self.mainViewController {
                            mainVC.stats_saveToCache()
                        }
                        completion()
                    }
                }
            }
        }
    }

    func currentStatsInterval() -> DateInterval {
        if let interval = customInterval {
            return interval
        }

        let nowDate = Date()
        if isTodayOnly {
            let start = Calendar.current.startOfDay(for: nowDate)
            return DateInterval(start: start, end: nowDate)
        } else {
            let end = nowDate
            let start = end.addingTimeInterval(-Double(daysToAnalyze) * 24 * 60 * 60)
            return DateInterval(start: start, end: end)
        }
    }

    func previousStatsInterval() -> DateInterval? {
        if let interval = customInterval {
            let duration = interval.duration
            guard duration > 0 else { return nil }
            let previousEnd = interval.start
            let previousStart = previousEnd.addingTimeInterval(-duration)
            return DateInterval(start: previousStart, end: previousEnd)
        }

        if isTodayOnly { return nil }
        let current = currentStatsInterval()
        let duration = current.duration
        guard duration > 0 else { return nil }
        let previousEnd = current.start
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return DateInterval(start: previousStart, end: previousEnd)
    }
    
    // MARK: - Interval-baserade getters för trendberäkningar

    func getBGData(in interval: DateInterval) -> [ShareGlucoseData] {
        guard let mainVC = mainViewController else {
            LogManager.shared.log(
                category: .analysis,
                message: "getBGData(in:) – mainVC was nil",
                isDebug: false
            )
            return []
        }

        let startTime = interval.start.timeIntervalSince1970
        let endTime = interval.end.timeIntervalSince1970

        // Använd heltalssekunder för cache-nyckeln för att undvika precisionstapp i Double
        let key = BGIntervalKey(
            start: Int(startTime),
            end: Int(endTime)
        )

        // 1) Kolla cache först
        if let cached = bgCache[key] {
            return cached
        }

        // 2) Filtrera + dedupe som tidigare
        let filtered = mainVC.statsBGData.filter { $0.date >= startTime && $0.date < endTime }

        let deduped = Self.dedupeBGByFiveMinuteBucket(filtered)

        LogManager.shared.log(
            category: .analysis,
            message: "getBGData(in:) – interval start=\(interval.start), end=\(interval.end), raw=\(filtered.count), deduped=\(deduped.count)",
            isDebug: true,
            isTempDebug: true
        )

        // 3) Lägg i cache
        bgCache[key] = deduped
        return deduped
    }
    
    /// De-duplicate BG readings by 5-minute buckets (300s). Keeps the newest reading per bucket.
    private static func dedupeBGByFiveMinuteBucket(_ input: [ShareGlucoseData]) -> [ShareGlucoseData] {
        guard !input.isEmpty else { return [] }

        var byBucket: [Int: ShareGlucoseData] = [:]
        byBucket.reserveCapacity(input.count)

        for r in input {
            let bucket = Int((r.date / 300.0).rounded()) // robust to jitter
            if let existing = byBucket[bucket] {
                if r.date > existing.date {
                    byBucket[bucket] = r
                }
            } else {
                byBucket[bucket] = r
            }
        }

        return byBucket.values.sorted(by: { $0.date < $1.date })
    }

    func getBGCheckDates(in interval: DateInterval) -> [TimeInterval] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        LogManager.shared.log(
            category: .analysis,
            message: "getBGCheckDates(in:) – interval start=\(interval.start), end=\(interval.end)",
            isDebug: true,
            isTempDebug: true
        )
        return mainVC.statsBGCheckData.filter { $0 >= start && $0 <= end }
    }

    func getBolusData(in interval: DateInterval) -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        LogManager.shared.log(
            category: .analysis,
            message: "getBolusData(in:) – interval start=\(interval.start), end=\(interval.end)",
            isDebug: true,
            isTempDebug: true
        )
        return mainVC.statsBolusData.filter { $0.date >= start && $0.date <= end }
    }

    func getSMBData(in interval: DateInterval) -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        LogManager.shared.log(
            category: .analysis,
            message: "getSMBData(in:) – interval start=\(interval.start), end=\(interval.end)",
            isDebug: true,
            isTempDebug: true
        )
        return mainVC.statsSMBData.filter { $0.date >= start && $0.date <= end }
    }

    func getCarbData(in interval: DateInterval) -> [MainViewController.carbGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        LogManager.shared.log(
            category: .analysis,
            message: "getCarbData(in:) – interval start=\(interval.start), end=\(interval.end)",
            isDebug: true,
            isTempDebug: true
        )
        return mainVC.statsCarbData.filter { $0.date >= start && $0.date <= end }
    }

    func getDailyDeliveredBasal(in interval: DateInterval) -> [DailyBasalStat] {
        guard let mainVC = mainViewController else { return [] }

        let startTime = interval.start.timeIntervalSince1970
        let endTime = interval.end.timeIntervalSince1970
        let key = BGIntervalKey(
            start: Int(startTime),
            end: Int(endTime)
        )

        if let cached = basalCache[key] {
            LogManager.shared.log(
                category: .analysis,
                message: "getDailyDeliveredBasal(in:) – cache hit for interval start=\(interval.start), end=\(interval.end)",
                isDebug: true,
                isTempDebug: true
            )
            return cached
        }

        let calendar = Calendar.current
        let startDate = interval.start
        let endDate = interval.end

        let cutoffTime = startDate.timeIntervalSince1970
        let endTimeVal = endDate.timeIntervalSince1970

        // Ta ut basalstege upp till endTime och inkludera även sista punkt före startDate
        let allBasal = mainVC.statsBasalData
            .filter { $0.date <= endTimeVal }
            .sorted { $0.date < $1.date }

        guard !allBasal.isEmpty else { return [] }

        var basalPoints = allBasal.filter { $0.date >= cutoffTime }
        if let lastBeforeStart = allBasal.last(where: { $0.date < cutoffTime }) {
            basalPoints.insert(lastBeforeStart, at: 0)
        }

        guard !basalPoints.isEmpty else { return [] }

        let events: [StatsBasalEngine.BasalChangeEvent] = basalPoints.map {
            StatsBasalEngine.BasalChangeEvent(
                date: Date(timeIntervalSince1970: $0.date),
                rateUph: $0.basalRate
            )
        }

        // Dela upp i kalenderdagar inom intervallet och simulera per dag.
        var results: [DailyBasalStat] = []

        var currentDayStart = calendar.startOfDay(for: startDate)

        // Iterera över kalenderdagar så länge dayStart ligger före intervallets slut.
        while currentDayStart < endDate {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else { break }

            let intervalEnd = min(nextDayStart, endDate)
            // Om intervallet av någon anledning blir tomt, avbryt
            guard intervalEnd > currentDayStart else { break }

            let dayInterval = DateInterval(start: currentDayStart, end: intervalEnd)

            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: dayInterval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            results.append(
                DailyBasalStat(
                    dayStart: currentDayStart,
                    totalUnits: sim.totalUnits
                )
            )

            currentDayStart = nextDayStart
        }

        // Cacha resultatet för detta intervall så vi slipper simulera om vid upprepade anrop
        let cacheKey = BGIntervalKey(
            start: Int(startDate.timeIntervalSince1970),
            end: Int(endDate.timeIntervalSince1970)
        )
        basalCache[cacheKey] = results

        let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)",
            isDebug: true,
            isTempDebug: true
        )
        return results
    }
    
    func getBGData() -> [ShareGlucoseData] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBGData.filter { $0.date >= cutoffTime }
    }
    
    func getBGCheckDates() -> [TimeInterval] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBGCheckData.filter { $0 >= cutoffTime && $0 <= now }
    }

    func getBolusData() -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsBolusData.filter { $0.date >= cutoffTime }
    }

    func getSMBData() -> [MainViewController.bolusGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = nowDate.timeIntervalSince1970 - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsSMBData.filter { $0.date >= cutoffTime }
    }

    func getCarbData() -> [MainViewController.carbGraphStruct] {
        guard let mainVC = mainViewController else { return [] }
        let nowDate = Date()
        let now = nowDate.timeIntervalSince1970
        let cutoffTime: TimeInterval
        if isTodayOnly {
            cutoffTime = Calendar.current.startOfDay(for: nowDate).timeIntervalSince1970
        } else {
            cutoffTime = now - (Double(daysToAnalyze) * 24 * 60 * 60)
        }
        return mainVC.statsCarbData.filter { $0.date >= cutoffTime && $0.date <= now }
    }

    func getBasalProfile() -> [MainViewController.basalProfileStruct] {
        guard let mainVC = mainViewController else { return [] }
        return mainVC.basalProfile
    }

    /// Hämta basalprofil för ett visst analysintervall.
    /// Försöker använda historisk profil från StatsProfileBasalEngine, annars fall-back till nuvarande profil.
    func getBasalProfile(for interval: DateInterval) -> [MainViewController.basalProfileStruct] {
        if let historical = statsBasalEngine.basalProfile(for: interval) {
            return historical
        } else {
            return getBasalProfile()
        }
    }
    
    func getDailyDeliveredBasal() -> [DailyBasalStat] {
        guard let mainVC = mainViewController else { return [] }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - getDailyDeliveredBasal called. isTodayOnly=\(isTodayOnly), daysToAnalyze=\(daysToAnalyze)",
            isDebug: true,
            isTempDebug: true
        )

        let calendar = Calendar.current
        let nowDate = Date()

        // Bestäm analysfönster – håll detta i sync med övriga getters
        let endDate: Date = nowDate
        let startDate: Date

        if isTodayOnly {
            // Idag: midnatt → nu
            startDate = calendar.startOfDay(for: nowDate)
        } else {
            // Övriga perioder (1, 7, 14, 30, 90 dagar): rullande fönster bakåt i tid
            startDate = endDate.addingTimeInterval(-Double(daysToAnalyze) * 24 * 60 * 60)
        }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - window start=\(startDate), end=\(endDate)",
            isDebug: true
        )

        let cutoffTime = startDate.timeIntervalSince1970
        let endTime = endDate.timeIntervalSince1970

        // 1) Ta ut basalstege upp till endTime
        //    och inkludera även sista punkt *före* startDate
        let allBasal = mainVC.statsBasalData
            .filter { $0.date <= endTime }
            .sorted { $0.date < $1.date }

        guard !allBasal.isEmpty else { return [] }

        // Alla punkter inom fönstret
        var basalPoints = allBasal.filter { $0.date >= cutoffTime }

        // Lägg till sista punkten innan cutoff som första element (om den finns),
        // så att motorn vet vilken basal som gällde vid fönstrets start.
        if let lastBeforeStart = allBasal.last(where: { $0.date < cutoffTime }) {
            basalPoints.insert(lastBeforeStart, at: 0)
        }

        guard !basalPoints.isEmpty else { return [] }

        // 2) Gör om till BasalChangeEvent (piecewise-constant rate U/h)
        let events: [StatsBasalEngine.BasalChangeEvent] = basalPoints.map {
            StatsBasalEngine.BasalChangeEvent(
                date: Date(timeIntervalSince1970: $0.date),
                rateUph: $0.basalRate
            )
        }

        // 3) Simulera levererad basal med StatsBasalEngine
        var results: [DailyBasalStat] = []

        // Specialfall: 24 h-valet (daysToAnalyze == 1 och inte "Idag") ska vara ett rullande 24 h-fönster
        if !isTodayOnly && daysToAnalyze == 1 {
            let interval = DateInterval(start: startDate, end: endDate)
            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            let stat = DailyBasalStat(dayStart: startDate, totalUnits: sim.totalUnits)
            results.append(stat)
            LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - 24h window start=\(startDate), end=\(endDate), basalUnits=\(sim.totalUnits)",
                isDebug: true
            )

            let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
            LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)",
                isDebug: true
            )
            return results
        }

        // Standardfall: dela upp i kalenderdagar (Idag, 7, 14, 30, 90 dagar)
        var currentDayStart = calendar.startOfDay(for: startDate)
        let finalDayStart = calendar.startOfDay(for: endDate)

        while currentDayStart <= finalDayStart {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else { break }

            let intervalEnd = min(nextDayStart, endDate)
            let interval = DateInterval(start: currentDayStart, end: intervalEnd)

            let sim = StatsBasalEngine.simulateDeliveredBasal(
                events: events,
                in: interval,
                pulseSize: 0.05,
                carryOverUndeliveredBasals: false
            )

            results.append(DailyBasalStat(dayStart: currentDayStart,
                                          totalUnits: sim.totalUnits))
            /*LogManager.shared.log(
                category: .analysis,
                message: "StatsBasalEngine - dayStart=\(currentDayStart), basalUnits=\(sim.totalUnits)",
                isDebug: true
            )*/

            currentDayStart = nextDayStart
        }

        let totalBasal = results.reduce(0.0) { $0 + $1.totalUnits }
        LogManager.shared.log(
            category: .analysis,
            message: "StatsBasalEngine - total days=\(results.count), summedBasal=\(totalBasal)",
            isDebug: true
        )
        return results
    }
}
