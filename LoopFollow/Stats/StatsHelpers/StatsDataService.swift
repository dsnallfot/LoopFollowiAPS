// LoopFollow
// StatsDataService.swift


import Foundation

// Enkel persistent cache för statistikdata (bolus, SMB, kolhydrater, basal).
// Lagrar upp till 90 dagar och används för att minska Nightscout-förfrågningar.
final class StatsCacheManager {
    static let shared = StatsCacheManager()
    private let root: URL
    private let diskLock = NSRecursiveLock()
    private weak var loadedController: MainViewController?
    private var daysOnDisk: [Int: Cache]?

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
        root = directory
    }

    private struct CachedBolus: Codable, Equatable {
        let value: Double
        let date: Double
        let sgv: Int
    }

    private struct CachedCarb: Codable, Equatable {
        let value: Double
        let date: Double
        let sgv: Int
        let absorptionTime: Int
        let foodType: String?
        let fat: Double
        let protein: Double
    }

    private struct CachedBasal: Codable, Equatable {
        let basalRate: Double
        let date: Double
    }

    private struct CachedBG: Codable, Equatable {
        let sgv: Int
        let date: Double
        let direction: String?
    }

    private struct CachedBGCheck: Codable, Equatable {
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

    private var cacheURL: URL { root.appendingPathComponent("StatsCache.json") }
    private var daysURL: URL { root.appendingPathComponent("StatsCacheDays-v1", isDirectory: true) }
    private var markerURL: URL { daysURL.appendingPathComponent("_complete") }

    private func dayURL(_ day: Int, in directory: URL) -> URL {
        directory.appendingPathComponent("day-\(day).json")
    }

    // UTC buckets keep filenames stable when the phone changes timezone.
    private func splitDays(_ cache: Cache) -> [Int: Cache] {
        func key(_ date: Double) -> Int { Int(floor(date / 86400)) }
        let bg = Dictionary(grouping: cache.bg) { key($0.date) }
        let checks = Dictionary(grouping: cache.bgChecks) { key($0.date) }
        let bolus = Dictionary(grouping: cache.bolus) { key($0.date) }
        let smb = Dictionary(grouping: cache.smb) { key($0.date) }
        let carbs = Dictionary(grouping: cache.carbs) { key($0.date) }
        let basal = Dictionary(grouping: cache.basal) { key($0.date) }
        let keys = Set(bg.keys).union(checks.keys).union(bolus.keys)
            .union(smb.keys).union(carbs.keys).union(basal.keys)
        return Dictionary(uniqueKeysWithValues: keys.map { day in
            (day, Cache(lastUpdated: cache.lastUpdated, bg: bg[day] ?? [],
                        bgChecks: checks[day] ?? [], bolus: bolus[day] ?? [],
                        smb: smb[day] ?? [], carbs: carbs[day] ?? [], basal: basal[day] ?? []))
        })
    }

    private func readCache() throws -> Cache {
        if daysOnDisk == nil {
            if FileManager.default.fileExists(atPath: markerURL.path) {
                var days: [Int: Cache] = [:]
                for url in try FileManager.default.contentsOfDirectory(at: daysURL, includingPropertiesForKeys: nil)
                    where url.pathExtension == "json" {
                    let cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: url))
                    // A corrupt day is an error, never an invitation to resurrect the legacy cache.
                    guard let day = Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "day-", with: "")) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    days[day] = cache
                }
                daysOnDisk = days
            } else if FileManager.default.fileExists(atPath: cacheURL.path) {
                daysOnDisk = splitDays(try JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)))
            } else {
                daysOnDisk = [:]
            }
        }
        let days = (daysOnDisk ?? [:]).sorted { $0.key < $1.key }.map { $0.value }
        return Cache(lastUpdated: days.map { $0.lastUpdated }.max() ?? Date(),
                     bg: days.flatMap { $0.bg }, bgChecks: days.flatMap { $0.bgChecks },
                     bolus: days.flatMap { $0.bolus }, smb: days.flatMap { $0.smb },
                     carbs: days.flatMap { $0.carbs }, basal: days.flatMap { $0.basal })
    }

    private func sameContent(_ lhs: Cache, _ rhs: Cache) -> Bool {
        lhs.bg == rhs.bg && lhs.bgChecks == rhs.bgChecks && lhs.bolus == rhs.bolus &&
        lhs.smb == rhs.smb && lhs.carbs == rhs.carbs && lhs.basal == rhs.basal
    }

    /// Persist synchronously before the background execution opportunity ends.
    /// Atomic per-day writes; migration becomes visible only when the entire directory is ready.
    private func writeCache(_ cache: Cache) throws {
        let fm = FileManager.default
        let days = splitDays(cache)
        let encoder = JSONEncoder()
        var writtenBytes = 0
        var writtenDays = 0
        if !fm.fileExists(atPath: markerURL.path) {
            let staging = root.appendingPathComponent("StatsCacheMigration-" + UUID().uuidString)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            for (day, payload) in days {
                let data = try encoder.encode(payload)
                try data.write(to: dayURL(day, in: staging), options: .atomic)
                writtenBytes += data.count
                writtenDays += 1
            }
            try Data("1".utf8).write(to: staging.appendingPathComponent("_complete"), options: .atomic)
            try fm.moveItem(at: staging, to: daysURL)
            // Leave StatsCache.json untouched as a rollback copy. Never read it after migration.
            daysOnDisk = days
        } else {
            for (day, payload) in days {
                let url = dayURL(day, in: daysURL)
                if let old = daysOnDisk?[day], sameContent(old, payload), fm.fileExists(atPath: url.path) { continue }
                let data = try encoder.encode(payload)
                try data.write(to: url, options: .atomic)
                daysOnDisk?[day] = payload
                writtenBytes += data.count
                writtenDays += 1
            }
            for day in Set((daysOnDisk ?? [:]).keys).subtracting(days.keys) {
                let url = dayURL(day, in: daysURL)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                daysOnDisk?.removeValue(forKey: day)
            }
        }
        LogManager.shared.log(category: .analysis,
            message: "Stats cache: wrote \(writtenDays) days / \(writtenBytes) bytes; retained \(days.count) days",
            isDebug: true, limitIdentifier: "stats-cache-writes")
    }

    /// Läs in cache från disk och applicera på MainViewController (endast de senaste 90 dagarna).
    func loadInto(mainVC: MainViewController) {
        diskLock.lock()
        defer { diskLock.unlock() }
        guard loadedController !== mainVC else { return }
        do {
            let cache = try readCache()

            let now = Date()
            let cutoff = now.addingTimeInterval(-91 * 24 * 60 * 60).timeIntervalSince1970

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
            loadedController = mainVC
            
            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - cache loaded: bg=\(bg.count), bgChecks=\(bgChecks.count), bolus=\(bolus.count), smb=\(smb.count), carbs=\(carbs.count), basal=\(basal.count)",
                isDebug: true
            )
        } catch {
            LogManager.shared.log(category: .analysis,
                message: "Stats cache could not be loaded; preserving files: \(error.localizedDescription)",
                limitIdentifier: "stats-cache-load-failed")
        }
    }

    /// MainViewController owns the cumulative history, loaded once before any fetch.
    /// Never merge deleted records back from yesterday's disk snapshot.
    func saveFrom(mainVC: MainViewController) {
        diskLock.lock()
        defer { diskLock.unlock() }
        guard loadedController === mainVC else { return }
        let now = Date()
        let horizonCutoff = now.addingTimeInterval(-91 * 24 * 60 * 60).timeIntervalSince1970

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

        let cache = Cache(lastUpdated: now,
                          bg: newBG.sorted { $0.date < $1.date },
                          bgChecks: newBGChecks.sorted { $0.date < $1.date },
                          bolus: newBolus.sorted { $0.date < $1.date },
                          smb: newSMB.sorted { $0.date < $1.date },
                          carbs: newCarbs.sorted { $0.date < $1.date },
                          basal: newBasal.sorted { $0.date < $1.date })
        do {
            try writeCache(cache)
            mainVC.statsCacheLastUpdated = now
        } catch {
            LogManager.shared.log(category: .analysis,
                message: "Stats cache save failed: \(error.localizedDescription)",
                limitIdentifier: "stats-cache-write-failed")
        }
    }

    /// Export a month-scoped StatsCache.json to the given destination URL.
    /// Reads the daily cache (or legacy cache before migration) and filters to the interval.
    /// Best-effort only: if no cache exists or decoding fails, nothing is written.
    func exportMonthStatsCache(interval: DateInterval, destinationURL: URL) {
        diskLock.lock()
        defer { diskLock.unlock() }
        let existing: Cache
        do {
            existing = try readCache()
        } catch {
            LogManager.shared.log(category: .analysis, message: "Stats cache export failed: \(error.localizedDescription)")
            return
        }

        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970

        func inRange(_ t: Double) -> Bool { t >= start && t < end }

        let monthCache = Cache(
            lastUpdated: Date(),
            bg: existing.bg.filter { inRange($0.date) },
            bgChecks: existing.bgChecks.filter { inRange($0.date) },
            bolus: existing.bolus.filter { inRange($0.date) },
            smb: existing.smb.filter { inRange($0.date) },
            carbs: existing.carbs.filter { inRange($0.date) },
            basal: existing.basal.filter { inRange($0.date) }
        )

        do {
            let dir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let out = try encoder.encode(monthCache)
            try out.write(to: destinationURL, options: [.atomic])

            LogManager.shared.log(
                category: .analysis,
                message: "StatsCacheManager - exportMonthStatsCache: wrote month cache (bg=\(monthCache.bg.count), bolus=\(monthCache.bolus.count), smb=\(monthCache.smb.count), carbs=\(monthCache.carbs.count), basal=\(monthCache.basal.count))",
                isDebug: true
            )
        } catch {
            LogManager.shared.log(category: .analysis, message: "StatsCacheManager - exportMonthStatsCache: write failed (\(error.localizedDescription))", isDebug: true)
        }
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
        let horizonDays: Double = 91          // ska matcha StatsDataFetcher.maxCachedDays
        let horizonCutoff = now - horizonDays * 24 * 60 * 60

        // 1. Trimma bort riktigt gammal historik (äldre än 90 dagar)
        statsBGData.removeAll { $0.date < horizonCutoff }

        // Incoming live values win, including corrections at an existing timestamp.
        // Keep the existing five-minute de-duplication between NS and live sources.
        var byBucket: [Int: ShareGlucoseData] = [:]
        for reading in statsBGData { byBucket[Int((reading.date / 300).rounded())] = reading }
        for reading in bgData where reading.date >= horizonCutoff && reading.date <= now {
            byBucket[Int((reading.date / 300).rounded())] = reading
        }
        statsBGData = byBucket.values.sorted { $0.date < $1.date }
    }

    func stats_syncTreatmentsFromLive(replacingRecentSince: Date? = nil) {
        let now = Date().timeIntervalSince1970
        let horizonDays: Double = 91          // ska matcha StatsDataFetcher.maxCachedDays
        let horizonCutoff = now - horizonDays * 24 * 60 * 60
        let replacementStart = replacingRecentSince?.timeIntervalSince1970 ?? .infinity

        // MARK: Bolus
        statsBolusData.removeAll { $0.date < horizonCutoff || ($0.date >= replacementStart && $0.date <= now) }
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
        statsSMBData.removeAll { $0.date < horizonCutoff || ($0.date >= replacementStart && $0.date <= now) }
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
        statsCarbData.removeAll { $0.date < horizonCutoff || $0.date > now || $0.date >= replacementStart }
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
        statsBasalData.removeAll { $0.date < horizonCutoff || ($0.date >= replacementStart && $0.date <= now) }
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
        statsBGCheckData.removeAll { $0 < horizonCutoff || ($0 >= replacementStart && $0 <= now) }
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
    private let maxStatsDays: Int = 91
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
    
    /// Tvinga omladdning av BG + treatments från Nightscout.
    /// Normal reload hämtar bara de senaste 48 timmarna.
    /// Vid explicit backfill, t.ex. långtryck i AggregatedStatsView, hämtas valt antal dagar
    /// och BG-cachens replacement window utökas till hela det begärda fönstret.
    func reloadAllData(backfillDays: Int? = nil, onProgress: @escaping () -> Void, completion: @escaping () -> Void) {
        let daysToFetch = max(1, min(backfillDays ?? 2, maxStatsDays))
        let forceFullReloadWindow = backfillDays != nil

        clearBGCache()

        LogManager.shared.log(
            category: .analysis,
            message: "StatsDataService - reloadAllData daysToFetch=\(daysToFetch), forceFullReloadWindow=\(forceFullReloadWindow)",
            isDebug: true
        )

        dataFetcher.fetchBGData(days: daysToFetch, forceFullReloadWindow: forceFullReloadWindow) {
            DispatchQueue.main.async {
                onProgress()
                self.dataFetcher.fetchTreatmentsData(days: daysToFetch) {
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
            isTempDebug: false
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
            isTempDebug: false
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
            isTempDebug: false
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
            isTempDebug: false
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
            isTempDebug: false
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
                isTempDebug: false
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
            isTempDebug: false
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
            isTempDebug: false
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
