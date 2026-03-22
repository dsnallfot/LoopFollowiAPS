import UIKit
import Charts

struct BGCheckEntry {
    let date: Date
    let mmol: Double
    let hasDextroNearby: Bool
    let cgm10mMmol: Double?
    let delta10m: Double?
}

/// Enkel loggvy för fingerstick / BG Check, inspirerad av GlucoseView.
final class BGCheckView: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    private struct BGPoint {
        let date: Date
        let mmol: Double
    }
    
    private struct CGMPoint {
        let date: Date
        let mmol: Double
    }
    
    private struct LowTreatmentEntry {
        let date: Date
        let grams: Double
        let hasBGCheckNearby: Bool
        let cgmMmol: Double?
        let bgCheckMmol: Double?
    }

    private enum Mode {
        case fingerstick
        case dextro
    }

    private var mode: Mode = .fingerstick

    private var fingerstickEntries: [BGCheckEntry] = []
    private var dextroEntries: [LowTreatmentEntry] = []
    
    // För Dextro-stats (samma som bgCheckDatesForStats/bgCheckMmolForStats i LowTreatmentsView)
    private var dextroBGCheckDates: [Date] = []
    private var dextroBGCheckMmol: [Double] = []

    // Backwards-compat så resten av filen kan fortsätta använda `entries` tills vi fasar om
    private var entries: [BGCheckEntry] {
        get { fingerstickEntries }
        set { fingerstickEntries = newValue }
    }

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private let valueFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        return nf
    }()

    private let deltaFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        nf.positivePrefix = "+"
        nf.negativePrefix = "-"
        return nf
    }()
    
    private let gramsFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 0
        return nf
    }()

    private let mmolFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        return nf
    }()

    private var activityIndicator: UIActivityIndicatorView?
    private var reloadButton: UIBarButtonItem?

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        if #available(iOS 13.4, *) {
            dp.preferredDatePickerStyle = .compact
        }
        dp.locale = Locale(identifier: "sv_SE")
        dp.date = Date()
        return dp
    }()
    
    private let modeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Fingerstick", "Dextro"])
        sc.selectedSegmentIndex = 0
        return sc
    }()

    private let topStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.spacing = 8
        return sv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Fingerstick"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupDatePicker()
        setupTableView()
        setupConstraints()

        loadBGChecks()
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        // Samma logik som Behandlingslogg / Dextrologg
        let isModalRoot = navigationController?.viewControllers.first === self

        // Reload-knapp (samma look & feel som GlucoseView)
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        self.reloadButton = reload

        // Klar-knapp när vi är modala
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let statsBtn = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showBGCheckStats)
        )

        if isModalRoot {
            // MODAL: stats + Klar, reload till vänster
            navigationItem.rightBarButtonItems = [statsBtn, done]
            navigationItem.leftBarButtonItem = reload
        } else {
            // PUSH: bara stats till höger, back-pil + reload till vänster
            navigationItem.rightBarButtonItems = [statsBtn]
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItems = [reload]
        }
    }
    
    private func setupDatePicker() {
        topStack.translatesAutoresizingMaskIntoConstraints = false
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false

        // Arranged subviews: exakt som i TreatMentsTableView (datePicker + segmentedControl)
        topStack.axis = .horizontal
        topStack.spacing = 6
        topStack.alignment = .center
        topStack.addArrangedSubview(datePicker)
        topStack.addArrangedSubview(modeControl)

        view.addSubview(topStack)

        // Samma hugging/compression-trick som i TreatMentsTableView
        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        modeControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        modeControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Uniform compact heights
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        modeControl.heightAnchor.constraint(equalToConstant: 30).isActive = true
        // Ge datumtexten plats (samma som kommentaren i TreatMentsTableView)
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true

        datePicker.addTarget(self, action: #selector(datePickerChanged(_:)), for: .valueChanged)
        modeControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)

        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            topStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            topStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -8)
        ])
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func refreshTapped() {
        switch mode {
        case .fingerstick:
            loadBGChecks()
        case .dextro:
            loadLowTreatments()
        }
    }

    @objc private func showBGCheckStats() {
        switch mode {
        case .fingerstick:
            let calendar = Calendar.current
            let now = Date()
            let daysBack = min(NightscoutCache.retentionDays, 91)

            // Startdatum = början av dagen (daysBack-1) dagar bakåt
            guard let startDay = calendar.date(byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: now)) else {
                return
            }

            // Bygg en array av alla dagar i intervallet, med default 0 stick per dag
            var days: [Date] = []
            var counts: [Int] = []
            var dextroCounts: [Int] = []
            days.reserveCapacity(daysBack)
            counts.reserveCapacity(daysBack)
            dextroCounts.reserveCapacity(daysBack)

            for offset in 0..<daysBack {
                if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                    days.append(day)
                    counts.append(0)
                    dextroCounts.append(0)
                }
            }

            // Snabb lookup för dag -> index i counts
            var indexByDay: [Date: Int] = [:]
            for (idx, day) in days.enumerated() {
                indexByDay[calendar.startOfDay(for: day)] = idx
            }

            // Räkna fingerstick per dag inom perioden och dextro per dag
            for entry in fingerstickEntries {
                if entry.date < startDay || entry.date > now { continue }
                let dayStart = calendar.startOfDay(for: entry.date)
                if let idx = indexByDay[dayStart] {
                    counts[idx] += 1
                    if entry.hasDextroNearby {
                        dextroCounts[idx] += 1
                    }
                }
            }

            let bgCheckDates = fingerstickEntries.map { $0.date }
            let bgCheckDextroDates = fingerstickEntries.filter { $0.hasDextroNearby }.map { $0.date }

            let statsVC = BGCheckStatsViewController(
                days: days,
                counts: counts,
                dextroCounts: dextroCounts,
                bgCheckEntries: fingerstickEntries,
                bgCheckDates: bgCheckDates,
                bgCheckDextroDates: bgCheckDextroDates
            )
            let nav = UINavigationController(rootViewController: statsVC)

            nav.modalPresentationStyle = .formSheet
            nav.view.backgroundColor = .clear
            nav.view.isOpaque = false
            nav.view.layer.backgroundColor = UIColor.clear.cgColor

            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.compactAppearance = appearance

            nav.overrideUserInterfaceStyle = self.traitCollection.userInterfaceStyle
            present(nav, animated: true)

        case .dextro:
            let calendar = Calendar.current
            let now = Date()
            let daysBack = min(NightscoutCache.retentionDays, 91)

            // Startdatum = början av dagen (daysBack-1) dagar bakåt
            guard let startDay = calendar.date(
                byAdding: .day,
                value: -(daysBack - 1),
                to: calendar.startOfDay(for: now)
            ) else {
                return
            }

            // Begränsa till perioden vi ska visa i statistiken
            let filteredEntries = dextroEntries.filter { $0.date >= startDay && $0.date <= now }

            // Bygg en array av alla dagar i intervallet, med default 0 lågbehandlingar per dag
            var days: [Date] = []
            var counts: [Int] = []
            var gramsPerDay: [Double] = []
            days.reserveCapacity(daysBack)
            counts.reserveCapacity(daysBack)
            gramsPerDay.reserveCapacity(daysBack)

            for offset in 0..<daysBack {
                if let day = calendar.date(byAdding: .day, value: offset, to: startDay) {
                    days.append(day)
                    counts.append(0)
                    gramsPerDay.append(0)
                }
            }

            // Snabb lookup för dag -> index i arrays
            var indexByDay: [Date: Int] = [:]
            for (idx, day) in days.enumerated() {
                indexByDay[calendar.startOfDay(for: day)] = idx
            }

            // Räkna lågbehandlingar och gram per dag
            for entry in filteredEntries {
                let dayStart = calendar.startOfDay(for: entry.date)
                if let idx = indexByDay[dayStart] {
                    counts[idx] += 1
                    gramsPerDay[idx] += entry.grams
                }
            }

            // Underliggande lista med enskilda behandlingar (för medel/max/streak-beräkningar)
            let treatmentDates = filteredEntries.map { $0.date }
            let treatmentGrams = filteredEntries.map { $0.grams }
            let treatmentHasBGCheck = filteredEntries.map { $0.hasBGCheckNearby }

            let statsVC = LowTreatmentsStatsViewController(
                days: days,
                counts: counts,
                gramsPerDay: gramsPerDay,
                treatmentDates: treatmentDates,
                treatmentGrams: treatmentGrams,
                treatmentHasBGCheck: treatmentHasBGCheck,
                bgCheckDates: dextroBGCheckDates,
                bgCheckMmol: dextroBGCheckMmol
            )
            let nav = UINavigationController(rootViewController: statsVC)

            nav.modalPresentationStyle = .formSheet
            nav.view.backgroundColor = .clear
            nav.view.isOpaque = false
            nav.view.layer.backgroundColor = UIColor.clear.cgColor

            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.compactAppearance = appearance

            nav.overrideUserInterfaceStyle = self.traitCollection.userInterfaceStyle
            present(nav, animated: true)
        }
    }

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // Don't register: we want to create with .subtitle style below
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    private func updateDatePickerBounds() {
        let dates: [Date]
        switch mode {
        case .fingerstick:
            dates = fingerstickEntries.map { $0.date }
        case .dextro:
            dates = dextroEntries.map { $0.date }
        }
        
        guard !dates.isEmpty else { return }


        let cal = Calendar.current

        // Vi antar att listorna är sorterade nyast först → äldsta = last
        let sorted = dates.sorted()
        if let oldest = sorted.first {
            let minDate = cal.startOfDay(for: oldest)
            datePicker.minimumDate = minDate
        } else {
            datePicker.minimumDate = nil
        }

        // Maxdatum = idag
        datePicker.maximumDate = Date()

        // Klampa vald datum inom intervallet om den hamnat utanför
        if let min = datePicker.minimumDate, datePicker.date < min {
            datePicker.date = min
        }
        if let max = datePicker.maximumDate, datePicker.date > max {
            datePicker.date = max
        }
    }

    @objc private func datePickerChanged(_ picker: UIDatePicker) {
        let cal = Calendar.current
        let selected = picker.date
        let startOfDay = cal.startOfDay(for: selected)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        switch mode {
        case .fingerstick:
            guard !fingerstickEntries.isEmpty else { return }
            var targetIndex: Int?

            for (idx, entry) in fingerstickEntries.enumerated() {
                if entry.date >= startOfDay && entry.date < endOfDay {
                    targetIndex = idx
                    break
                }
            }

            if targetIndex == nil {
                var candidateIndex: Int?
                for (idx, entry) in fingerstickEntries.enumerated() {
                    if entry.date >= selected {
                        candidateIndex = idx
                    }
                }

                if let candidateIndex {
                    targetIndex = candidateIndex
                } else {
                    targetIndex = 0
                }
            }

            guard let index = targetIndex,
                  index >= 0,
                  index < tableView.numberOfRows(inSection: 0) else { return }

            let indexPath = IndexPath(row: index, section: 0)
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)

        case .dextro:
            guard !dextroEntries.isEmpty else { return }
            var targetIndex: Int?

            for (idx, entry) in dextroEntries.enumerated() {
                if entry.date >= startOfDay && entry.date < endOfDay {
                    targetIndex = idx
                    break
                }
            }

            if targetIndex == nil {
                var candidateIndex: Int?
                for (idx, entry) in dextroEntries.enumerated() {
                    if entry.date >= selected {
                        candidateIndex = idx
                    }
                }

                if let candidateIndex {
                    targetIndex = candidateIndex
                } else {
                    targetIndex = 0
                }
            }

            guard let index = targetIndex,
                  index >= 0,
                  index < tableView.numberOfRows(inSection: 0) else { return }

            let indexPath = IndexPath(row: index, section: 0)
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }
    }
    
    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let newMode: Mode = (sender.selectedSegmentIndex == 0) ? .fingerstick : .dextro
        mode = newMode

        switch mode {
        case .fingerstick:
            title = "Fingerstick"
            updateDatePickerBounds()
            tableView.reloadData()
            // Autoscrolla till rätt rad för det aktuella datumet
            datePickerChanged(datePicker)

        case .dextro:
            title = "Dextro"
            if dextroEntries.isEmpty {
                // När dextro laddas första gången, låt loadLowTreatments sköta bounds + autoscroll
                loadLowTreatments()
            } else {
                updateDatePickerBounds()
                tableView.reloadData()
                // Autoscrolla även här till rätt rad
                datePickerChanged(datePicker)
            }
        }
    }

    // MARK: - Loading from cache

    private func showActivity() {
        guard let reloadButton = reloadButton else { return }

        if activityIndicator == nil {
            let ind = UIActivityIndicatorView(style: .medium)
            ind.hidesWhenStopped = true
            activityIndicator = ind
        }

        reloadButton.image = nil
        reloadButton.customView = activityIndicator
        activityIndicator?.startAnimating()
    }

    private func hideActivity() {
        activityIndicator?.stopAnimating()
        reloadButton?.customView = nil
        reloadButton?.image = UIImage(systemName: "arrow.clockwise")
        activityIndicator = nil
    }

    /// Hämtar alla BG Check-treatments från cachen och mappar till BGCheckEntry.
    private func loadBGChecks() {
        showActivity()

        Task {
            let now = Date()
            let cal = Calendar.current

            // Hämta t.ex. hela cachefönstret (samma retention som övrig cache)
            let start = cal.date(
                byAdding: .day,
                value: -NightscoutCache.retentionDays,
                to: now
            ) ?? now.addingTimeInterval(-91 * 24 * 60 * 60)

            // Antag att NightscoutCache.loadWindow(from:to:) returnerar (sgv, treatments)
            let (sgvs, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            // Bygg CGM‑punkter (i mmol/L) från SGV‑datan
            let bgPoints: [BGPoint] = sgvs
                .map { sgv in
                    BGPoint(
                        date: Date(timeIntervalSince1970: sgv.date),
                        mmol: Double(sgv.sgv) / 18.0182
                    )
                }
                .sorted { $0.date < $1.date }

            // 1) Plocka ut alla "dextro-treatments":
            //    • eventType == "Carb Correction"
            //    • carbs > 0
            //    • notes innehåller minst en "🍬"
            let dextroTreatments: [TreatmentJSON] = treatments.filter { t in
                guard t.eventType == "Carb Correction" else { return false }
                guard let carbs = t.carbs, carbs > 0 else { return false }
                guard let notes = t.notes, notes.contains("🍬") else { return false }
                return true
            }

            let windowSeconds: TimeInterval = 10 * 60 // ±10 min

            // 2) Bygg BGCheckEntry och sätt hasDextroNearby om vi hittar en dextro inom ±10 min
            let bgChecks: [BGCheckEntry] = treatments.compactMap { (t) -> BGCheckEntry? in
                guard t.eventType == "BG Check" else { return nil }

                // Datum – använd createdAt (från created_at) om möjligt, annars date
                let date = t.created_at

                guard let raw = t.glucose else {
                    return nil
                }

                let mmol: Double
                if let units = t.units, units.lowercased().contains("mmol") {
                    mmol = raw
                } else {
                    // mg/dL -> mmol/L
                    mmol = raw / 18.0182
                }

                // Finns det en dextro-treatment inom ±10 minuter?
                let hasDextroNearby = dextroTreatments.contains { dextro in
                    abs(dextro.created_at.timeIntervalSince(date)) <= windowSeconds
                }

                // Hitta CGM‑värdet som ligger närmast 10 minuter efter fingersticket
                let target = date.addingTimeInterval(10 * 60)
                let cgmPoint = nearestBGPoint(around: target, in: bgPoints)
                let cgm10 = cgmPoint?.mmol
                let delta10 = cgm10.map { $0 - mmol }

                return BGCheckEntry(
                    date: date,
                    mmol: mmol,
                    hasDextroNearby: hasDextroNearby,
                    cgm10mMmol: cgm10,
                    delta10m: delta10
                )
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.entries = bgChecks
                self.tableView.reloadData()
                self.updateDatePickerBounds()
                self.hideActivity()
            }
        }
    }

    // Hittar närmaste CGM‑punkt tidsmässigt runt ett givet mål.
    private func nearestBGPoint(around target: Date, in points: [BGPoint]) -> BGPoint? {
        guard !points.isEmpty else { return nil }
        // Binärsökning på tid (points är sorterade på date)
        var lo = 0
        var hi = points.count - 1
        var bestIndex = 0
        var bestDiff = abs(points[0].date.timeIntervalSince(target))

        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = points[mid].date
            let diff = abs(d.timeIntervalSince(target))
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = mid
            }
            if d < target {
                lo = mid + 1
            } else if d > target {
                hi = mid - 1
            } else {
                break
            }
        }
        return points[bestIndex]
    }
    
    /// Hämtar alla Carb Correction-treatments med 🍬 i notes (lågbehandlingar) och mappar till LowTreatmentEntry.
    private func loadLowTreatments() {
        showActivity()

        Task {
            let now = Date()
            let cal = Calendar.current

            // Hämta t.ex. hela cachefönstret (samma retention som övrig cache)
            let start = cal.date(
                byAdding: .day,
                value: -NightscoutCache.retentionDays,
                to: now
            ) ?? now.addingTimeInterval(-91 * 24 * 60 * 60)

            // Antag att NightscoutCache.loadWindow(from:to:) returnerar (sgv, treatments)
            let (sgvs, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            // Bygg CGM-punkter i mmol/L från SGV-datan
            let cgmPoints: [CGMPoint] = sgvs
                .map { sgv in
                    CGMPoint(
                        date: Date(timeIntervalSince1970: sgv.date),
                        mmol: Double(sgv.sgv) / 18.0182
                    )
                }
                .sorted { $0.date < $1.date }

            // Plocka ut alla BG Check-datum (för korsning mot dextro) samt mmol-värde
            var bgCheckDates: [Date] = []
            var bgCheckMmol: [Double] = []
            for t in treatments {
                guard t.eventType == "BG Check" else { continue }
                let date = t.created_at
                guard let raw = t.glucose else { continue }

                let mmol: Double
                if let units = t.units, units.lowercased().contains("mmol") {
                    mmol = raw
                } else {
                    // mg/dL -> mmol/L
                    mmol = raw / 18.0182
                }

                bgCheckDates.append(date)
                bgCheckMmol.append(mmol)
            }

            let windowSeconds: TimeInterval = 15 * 60 // ±15 min

            let lowTreatments: [LowTreatmentEntry] = treatments.compactMap { t -> LowTreatmentEntry? in
                // Endast Carb Correction med carbs > 0 och minst en 🍬 i notes
                guard t.eventType == "Carb Correction" else { return nil }
                guard let carbs = t.carbs, carbs > 0 else { return nil }
                guard let notes = t.notes, notes.contains("🍬") else { return nil }

                let date = t.created_at

                // Hitta närmaste BG Check i tid och se om den ligger inom ±15 minuter
                var nearestBGIndex: Int?
                var bestDelta = windowSeconds + 1
                for (idx, bgDate) in bgCheckDates.enumerated() {
                    let delta = abs(bgDate.timeIntervalSince(date))
                    if delta < bestDelta {
                        bestDelta = delta
                        nearestBGIndex = idx
                    }
                }

                let hasBGCheckNearby: Bool
                let bgCheckMmolNearby: Double?
                if let idx = nearestBGIndex, bestDelta <= windowSeconds {
                    hasBGCheckNearby = true
                    bgCheckMmolNearby = bgCheckMmol[idx]
                } else {
                    hasBGCheckNearby = false
                    bgCheckMmolNearby = nil
                }

                // Hitta närmaste CGM-värde vid tidpunkten för dextrobehandlingen
                let cgmPoint = nearestCGMPoint(around: date, in: cgmPoints)
                let cgmMmol = cgmPoint?.mmol

                return LowTreatmentEntry(
                    date: date,
                    grams: carbs,
                    hasBGCheckNearby: hasBGCheckNearby,
                    cgmMmol: cgmMmol,
                    bgCheckMmol: bgCheckMmolNearby
                )
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.dextroEntries = lowTreatments
                self.dextroBGCheckDates = bgCheckDates
                self.dextroBGCheckMmol = bgCheckMmol
                self.tableView.reloadData()
                self.updateDatePickerBounds()
                // Autoscrolla till det datum som redan är valt i datePickern, nu baserat på dextro-listan
                self.datePickerChanged(self.datePicker)
                self.hideActivity()
            }
        }
    }

    // Hittar närmaste CGM-punkt tidsmässigt runt ett givet mål.
    private func nearestCGMPoint(around target: Date, in points: [CGMPoint]) -> CGMPoint? {
        guard !points.isEmpty else { return nil }

        var lo = 0
        var hi = points.count - 1
        var bestIndex = 0
        var bestDiff = abs(points[0].date.timeIntervalSince(target))

        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = points[mid].date
            let diff = abs(d.timeIntervalSince(target))
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = mid
            }
            if d < target {
                lo = mid + 1
            } else if d > target {
                hi = mid - 1
            } else {
                break
            }
        }
        return points[bestIndex]
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .fingerstick:
            return fingerstickEntries.count
        case .dextro:
            return dextroEntries.count
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch mode {
        case .fingerstick:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BGCheckCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BGCheckCell")
            cell.textLabel?.numberOfLines = 1

            let entry = fingerstickEntries[indexPath.row]

            let mmolString = valueFormatter.string(from: NSNumber(value: entry.mmol)) ?? String(format: "%.1f", entry.mmol)

            var text = "\(mmolString) mmol/L".replacingOccurrences(of: ",", with: ".")
            if entry.hasDextroNearby {
                text += " 🍬"
            }

        cell.textLabel?.text = text
        cell.textLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)//.systemFont(ofSize: 17)

            if let cgm10 = entry.cgm10mMmol, let delta = entry.delta10m {
                let cgmString = valueFormatter.string(from: NSNumber(value: cgm10)) ?? String(format: "%.1f", cgm10)
                let deltaString = deltaFormatter.string(from: NSNumber(value: delta)) ?? String(format: "%+.1f", delta)

                cell.detailTextLabel?.text = "CGM +10 min: \(cgmString) Δ \(deltaString)".replacingOccurrences(of: ",", with: ".")
                cell.detailTextLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)//.systemFont(ofSize: 12)
                cell.detailTextLabel?.textColor = .secondaryLabel
            } else {
                cell.detailTextLabel?.text = nil
            }

            cell.imageView?.image = UIImage(systemName: "drop.fill")
            cell.imageView?.tintColor = .systemRed

            let rightLabel = UILabel()
            rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
            rightLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)//.systemFont(ofSize: 14)
            rightLabel.textColor = .secondaryLabel
            rightLabel.textAlignment = .right
            rightLabel.sizeToFit()
            cell.accessoryView = rightLabel

            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.backgroundView = nil
            if #available(iOS 14.0, *) {
                cell.backgroundConfiguration = nil
            }
            cell.textLabel?.backgroundColor = .clear
            cell.detailTextLabel?.backgroundColor = .clear

            cell.selectionStyle = .default
            cell.accessoryType = .none
            let selected = UIView()
            selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
            selected.layer.cornerRadius = 10
            selected.layer.masksToBounds = true
            cell.selectedBackgroundView = selected
            return cell

        case .dextro:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LowTreatmentCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "LowTreatmentCell")
            cell.textLabel?.numberOfLines = 1

            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.backgroundView = nil
            if #available(iOS 14.0, *) {
                cell.backgroundConfiguration = nil
            }
            cell.textLabel?.backgroundColor = .clear
            cell.detailTextLabel?.backgroundColor = .clear

            let entry = dextroEntries[indexPath.row]
            let gramsString = gramsFormatter.string(from: NSNumber(value: entry.grams)) ?? String(format: "%.0f", entry.grams)

            if let cgm = entry.cgmMmol {
                let cgmString = mmolFormatter.string(from: NSNumber(value: cgm)) ?? String(format: "%.1f", cgm)
                if entry.hasBGCheckNearby, let bg = entry.bgCheckMmol {
                    let bgString = mmolFormatter.string(from: NSNumber(value: bg)) ?? String(format: "%.1f", bg)
                    cell.detailTextLabel?.text = "CGM: \(cgmString) • Finger: \(bgString) mmol/L".replacingOccurrences(of: ",", with: ".")
                } else {
                    cell.detailTextLabel?.text = "CGM: \(cgmString) mmol/L".replacingOccurrences(of: ",", with: ".")
                }
                cell.detailTextLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)//.systemFont(ofSize: 12)
                cell.detailTextLabel?.textColor = .secondaryLabel
            } else {
                cell.detailTextLabel?.text = nil
            }

            var text = "Dextro • \(gramsString) g".replacingOccurrences(of: ",", with: ".")
            if entry.hasBGCheckNearby {
                text += " 🩸"
            }
            cell.textLabel?.text = text
            cell.textLabel?.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)//.systemFont(ofSize: 17)

            cell.imageView?.image = UIImage(systemName: "pill.fill")
            cell.imageView?.tintColor = .label

            let rightLabel = UILabel()
            rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
            rightLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)//.systemFont(ofSize: 14)
            rightLabel.textColor = .secondaryLabel
            rightLabel.textAlignment = .right
            rightLabel.sizeToFit()
            cell.accessoryView = rightLabel

            cell.selectionStyle = .default
            cell.accessoryType = .none
            let selected = UIView()
            selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
            selected.layer.cornerRadius = 10
            selected.layer.masksToBounds = true
            cell.selectedBackgroundView = selected
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entryDate: Date
        let modalTitle: String
        
        switch mode {
        case .fingerstick:
            let entry = fingerstickEntries[indexPath.row]
            entryDate = entry.date
            modalTitle = "Analys Stick"
        case .dextro:
            let entry = dextroEntries[indexPath.row]
            entryDate = entry.date
            modalTitle = "Analys Dextro"
        }
        let startDate = entryDate - 60 * 20  // 20 min före
        let endDate = entryDate + 60 * 180  // 160 min efter

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let tabBar = window.rootViewController as? UITabBarController,
            let tabViewControllers = tabBar.viewControllers
        else {
            return
        }

        var mainVC: MainViewController?

        for vc in tabViewControllers {
            if let nav = vc as? UINavigationController {
                if let candidate = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                    mainVC = candidate
                    break
                }
            } else if let candidate = vc as? MainViewController {
                mainVC = candidate
                break
            }
        }

        guard let mainVC else {
            return
        }

        let events = mainVC.buildEventsForMealAnalysis()

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            initialEnd: nil,
            modalWithTimestamp: true,
            modalTitleString: modalTitle,
            preSelectedSegment: 2
        )
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        self.present(nav, animated: true) { [weak self] in
            self?.tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

final class BGCheckStatsViewController: ThemedTableViewController {

    // Full data set (upp till t.ex. 90 dagar)
    private let allDays: [Date]
    private let allCounts: [Int]
    private let allDextroCounts: [Int]
    private let allBGCheckDates: [Date]
    private let allBGCheckDextroDates: [Date]
    private let allBGCheckEntries: [BGCheckEntry]

    // Aktuell vy (styrd av segmented control)
    private var selectedDays: [Date] = []
    private var selectedCounts: [Int] = []
    private var selectedDextroCounts: [Int] = []
    private var selectedBGCheckDates: [Date] = []
    private var selectedBGCheckDextroDates: [Date] = []
    private var selectedBGCheckEntries: [BGCheckEntry] = []

    private enum PeriodOption: CaseIterable {
        case d7, d14, d30, d90

        var days: Int {
            switch self {
            case .d7:  return 7
            case .d14: return 14
            case .d30: return 30
            case .d90: return 90
            }
        }

        var title: String {
            switch self {
            case .d7:  return "7 d"
            case .d14: return "14 d"
            case .d30: return "30 d"
            case .d90: return "90 d"
            }
        }
    }

    private enum ChartMode: CaseIterable {
        case count, time

        var title: String {
            switch self {
            case .count: return "Antal"
            case .time:  return "Tid"
            }
        }
    }

    private var selectedPeriod: PeriodOption = .d90

    private var selectedMode: ChartMode = .count

    private lazy var modeControl: UISegmentedControl = {
        let items = ChartMode.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = ChartMode.allCases.firstIndex(of: selectedMode) ?? 0
        sc.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        return sc
    }()

    private lazy var periodControl: UISegmentedControl = {
        let items = PeriodOption.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = PeriodOption.allCases.firstIndex(of: selectedPeriod) ?? (items.count - 1)
        sc.addTarget(self, action: #selector(periodChanged(_:)), for: .valueChanged)
        return sc
    }()

    private let chartView: BarChartView = {
        let v = BarChartView()
        v.legend.enabled = false
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1000000
        return v
    }()

    private let timeChartView: ScatterChartView = {
        let v = ScatterChartView()
        v.legend.enabled = true
        v.chartDescription.enabled = false
        v.rightAxis.enabled = false
        v.minOffset = 8
        v.pinchZoomEnabled = false
        v.doubleTapToZoomEnabled = true
        v.scaleXEnabled = true
        v.scaleYEnabled = false
        v.dragEnabled = true
        v.highlightPerTapEnabled = false
        v.highlightPerDragEnabled = false
        v.drawMarkers = false
        v.maxVisibleCount = 1000000
        return v
    }()

    init(days: [Date], counts: [Int], dextroCounts: [Int], bgCheckEntries: [BGCheckEntry], bgCheckDates: [Date], bgCheckDextroDates: [Date]) {
        self.allDays = days
        self.allCounts = counts
        self.allDextroCounts = dextroCounts
        self.allBGCheckDates = bgCheckDates
        self.allBGCheckDextroDates = bgCheckDextroDates
        self.allBGCheckEntries = bgCheckEntries
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func defaultPeriod() -> PeriodOption {
        let count = allDays.count
        // Defaulta till 14 dagar om möjligt,
        // annars falla tillbaka till kortare perioder vid behov.
        if count >= 14 { return .d14 }
        if count >= 7  { return .d7 }
        return .d7
    }

    private func applyPeriod(_ period: PeriodOption) {
        selectedPeriod = period
        let total = allDays.count
        guard total > 0 else {
            selectedDays = []
            selectedCounts = []
            selectedDextroCounts = []
            selectedBGCheckDates = []
            chartView.data = nil
            timeChartView.data = nil
            tableView.reloadData()
            return
        }

        let n = min(period.days, total)
        let startIndex = max(0, total - n)
        selectedDays = Array(allDays[startIndex..<total])
        selectedCounts = Array(allCounts[startIndex..<total])
        selectedDextroCounts = Array(allDextroCounts[startIndex..<total])

        // Compute date range for the selected days and filter BGCheck timestamps into it.
        if let firstDay = selectedDays.first, let lastDay = selectedDays.last {
            let cal = Calendar.current
            let start = cal.startOfDay(for: firstDay)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastDay)) ?? Date.distantFuture
            selectedBGCheckDates = allBGCheckDates
                .filter { $0 >= start && $0 < end }
                .sorted()
            selectedBGCheckDextroDates = allBGCheckDextroDates
                .filter { $0 >= start && $0 < end }
                .sorted()
            selectedBGCheckEntries = allBGCheckEntries
                .filter { $0.date >= start && $0.date < end }
                .sorted { $0.date < $1.date }
        } else {
            selectedBGCheckDates = []
            selectedBGCheckDextroDates = []
            selectedBGCheckEntries = []
        }

        loadChartData()
        tableView.reloadData()
    }

    @objc private func periodChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < PeriodOption.allCases.count else { return }
        let period = PeriodOption.allCases[index]
        applyPeriod(period)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.backgroundView = tableView.backgroundView
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Statistick"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BGStatsCell")

        // Välj en rimlig defaultperiod baserat på hur många dagar vi har
        let initialPeriod = defaultPeriod()
        selectedPeriod = initialPeriod
        if let idx = PeriodOption.allCases.firstIndex(of: initialPeriod) {
            periodControl.selectedSegmentIndex = idx
        }

        // Default: Antal
        selectedMode = .count
        if let idx2 = ChartMode.allCases.firstIndex(of: selectedMode) {
            modeControl.selectedSegmentIndex = idx2
        }

        setupChartHeader()
        applyPeriod(initialPeriod)
    }

    // MARK: - Chart header

    private func setupChartHeader() {
        let container = UIView()
        container.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 340)
        container.backgroundColor = .clear

        chartView.backgroundColor = .clear
        timeChartView.backgroundColor = .clear
        periodControl.backgroundColor = .clear
        modeControl.backgroundColor = .clear

        container.addSubview(periodControl)
        container.addSubview(modeControl)
        container.addSubview(chartView)
        container.addSubview(timeChartView)

        periodControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        timeChartView.translatesAutoresizingMaskIntoConstraints = false

        // Default visibility
        chartView.isHidden = false
        timeChartView.isHidden = true

        NSLayoutConstraint.activate([
            periodControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            periodControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            periodControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            modeControl.topAnchor.constraint(equalTo: periodControl.bottomAnchor, constant: 8),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            chartView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            chartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            chartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),

            timeChartView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            timeChartView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            timeChartView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            timeChartView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -0)
        ])

        tableView.tableHeaderView = container
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            let targetSize = CGSize(width: tableView.bounds.width, height: 340)
            if header.frame.size != targetSize {
                header.frame.size = targetSize
                tableView.tableHeaderView = header
            }
        }
    }

    private func loadChartData() {
        guard selectedDays.count == selectedCounts.count, !selectedDays.isEmpty else {
            chartView.data = nil
            timeChartView.data = nil
            chartView.setNeedsDisplay()
            timeChartView.setNeedsDisplay()
            return
        }

        switch selectedMode {
        case .count:
            loadCountChartData()
        case .time:
            loadTimeChartData()
        }
    }

    private func loadCountChartData() {
        var entries: [BarChartDataEntry] = []
        entries.reserveCapacity(selectedDays.count)

        var maxCount = 0
        for (idx, count) in selectedCounts.enumerated() {
            entries.append(BarChartDataEntry(x: Double(idx), y: Double(count)))
            if count > maxCount { maxCount = count }
        }

        let dataSet = BarChartDataSet(entries: entries, label: "")
        dataSet.setColor(.systemRed)
        dataSet.drawValuesEnabled = false
        dataSet.barBorderColor = .black
        dataSet.barBorderWidth = 0.5

        let data = BarChartData(dataSet: dataSet)
        chartView.data = data
        chartView.autoScaleMinMaxEnabled = false
        chartView.notifyDataSetChanged()
        chartView.drawGridBackgroundEnabled = true
        chartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // X-axis labels = datum (kompakt format) för varje index
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"

        let labels = selectedDays.map { df.string(from: $0) }
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y-axel – dynamiskt max utifrån högsta antal stick på en dag
        let yAxis = chartView.leftAxis
        yAxis.axisMinimum = 0
        let maxY = max(1, maxCount)
        yAxis.axisMaximum = Double(maxY) * 1.2
        yAxis.granularity = 1
        yAxis.granularityEnabled = true
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            String(format: "%.0f ggr", value)
        }

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        chartView.rightAxis.enabled = false
        chartView.setNeedsDisplay()
    }

    private func loadTimeChartData() {
        let cal = Calendar.current

        // Index per dag för x-position
        var indexByDay: [Date: Int] = [:]
        for (idx, d) in selectedDays.enumerated() {
            indexByDay[cal.startOfDay(for: d)] = idx
        }

        // Hjälpfunktion: timestamp -> timmar på dygnet (0–24)
        func hourOfDay(for date: Date) -> Double {
            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            let h = Double(comps.hour ?? 0)
            let m = Double(comps.minute ?? 0)
            let s = Double(comps.second ?? 0)
            return h + (m / 60.0) + (s / 3600.0)
        }

        // Dataset 1: Alla fingersticks
        var allPoints: [ChartDataEntry] = []
        allPoints.reserveCapacity(selectedBGCheckDates.count)
        for d in selectedBGCheckDates {
            let dayStart = cal.startOfDay(for: d)
            guard let dayIndex = indexByDay[dayStart] else { continue }
            allPoints.append(ChartDataEntry(x: Double(dayIndex), y: hourOfDay(for: d)))
        }
        
        // Viktigt: sortera entries för att undvika Charts-bug där punkter kan försvinna vid zoom/scroll
        allPoints.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        // Dataset 2: Fingerstick -> 🍬 (subset)
        var dextroPoints: [ChartDataEntry] = []
        dextroPoints.reserveCapacity(selectedBGCheckDextroDates.count)
        for d in selectedBGCheckDextroDates {
            let dayStart = cal.startOfDay(for: d)
            guard let dayIndex = indexByDay[dayStart] else { continue }
            dextroPoints.append(ChartDataEntry(x: Double(dayIndex), y: hourOfDay(for: d)))
        }
        
        // Viktigt: sortera entries för att undvika Charts-bug där punkter kan försvinna vid zoom/scroll
        dextroPoints.sort {
            if $0.x == $1.x { return $0.y < $1.y }
            return $0.x < $1.x
        }

        let redColor = UIColor.systemRed
        let purpleColor = UIColor.systemPurple

        let dsAll = ScatterChartDataSet(entries: allPoints, label: "Fingerstick")
        dsAll.setColor(redColor)
        dsAll.setScatterShape(.circle)
        dsAll.scatterShapeSize = 7
        dsAll.drawValuesEnabled = false

        let dsDextro = ScatterChartDataSet(entries: dextroPoints, label: "Fingerstick → 🍬")
        dsDextro.setColor(purpleColor)
        dsDextro.setScatterShape(.circle)
        dsDextro.scatterShapeSize = 7
        dsDextro.drawValuesEnabled = false

        // Lägg dsDextro sist så lila ritas ovanpå röd vid samma koordinat
        let data = ScatterChartData(dataSets: [dsAll, dsDextro])
        timeChartView.data = data
        timeChartView.autoScaleMinMaxEnabled = false
        timeChartView.notifyDataSetChanged()
        
        timeChartView.drawGridBackgroundEnabled = true
        timeChartView.gridBackgroundColor = NSUIColor.systemBackground.withAlphaComponent(0.5)

        // Legend under grafen
        timeChartView.legend.enabled = true
        timeChartView.legend.verticalAlignment = .bottom
        timeChartView.legend.horizontalAlignment = .center
        timeChartView.legend.orientation = .horizontal
        timeChartView.legend.drawInside = false
        timeChartView.legend.yOffset = 6

        let e1 = LegendEntry(label: "Fingerstick")
        e1.form = .circle
        e1.formSize = 8
        e1.formColor = redColor

        let e2 = LegendEntry(label: "Fingerstick → 🍬")
        e2.form = .circle
        e2.formSize = 8
        e2.formColor = purpleColor

        timeChartView.legend.setCustom(entries: [e1, e2])
        timeChartView.extraBottomOffset = 8

        // X-axis labels = datum (kompakt format) för varje index
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "dd/MM"
        let labels = selectedDays.map { df.string(from: $0) }

        let xAxis = timeChartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.granularity = 1
        xAxis.granularityEnabled = true
        xAxis.valueFormatter = IndexAxisValueFormatter(values: labels)
        xAxis.setLabelCount(min(6, labels.count), force: false)

        // Y-axel = timmar på dygnet 0–24
        let yAxis = timeChartView.leftAxis
        yAxis.axisMinimum = 0
        yAxis.axisMaximum = 24

        // Dashad grid för varje timme, men endast labels vid 00/06/12/18/24
        yAxis.granularity = 1
        yAxis.granularityEnabled = true
        yAxis.setLabelCount(25, force: false)
        yAxis.valueFormatter = DefaultAxisValueFormatter { value, _ in
            let v = Int(value.rounded())
            guard [0, 6, 12, 18, 24].contains(v) else { return "" }
            return String(format: "%02d:00", v)
        }

        // Rensa tidigare limit-lines
        yAxis.removeAllLimitLines()

        // Solida huvudlinjer vid 00/06/12/18/24
        let majorLineColor = UIColor.lightGray.withAlphaComponent(0.65)
        for hour in [0.0, 6.0, 12.0, 18.0, 24.0] {
            let ll = ChartLimitLine(limit: hour)
            ll.lineWidth = 0.8
            ll.lineColor = majorLineColor
            ll.lineDashLengths = []
            ll.label = ""
            yAxis.addLimitLine(ll)
        }

        let gridLineColor = UIColor.lightGray.withAlphaComponent(0.5)
        xAxis.gridColor = gridLineColor
        xAxis.gridLineWidth = 0.5
        xAxis.gridLineDashLengths = [2, 2]

        yAxis.gridColor = gridLineColor
        yAxis.gridLineWidth = 0.5
        yAxis.gridLineDashLengths = [2, 2]

        timeChartView.rightAxis.enabled = false
        timeChartView.setNeedsDisplay()
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        guard index >= 0 && index < ChartMode.allCases.count else { return }
        selectedMode = ChartMode.allCases[index]

        let showCount = (selectedMode == .count)
        chartView.isHidden = !showCount
        timeChartView.isHidden = showCount

        loadChartData()
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: - Stats helpers

    private var totalDays: Int { selectedDays.count }
    private var daysWithSticks: Int { selectedCounts.filter { $0 > 0 }.count }
    private var totalSticks: Int { selectedCounts.reduce(0, +) }
    private var totalDextroSticks: Int { selectedDextroCounts.reduce(0, +) }
    private var maxSticksPerDay: Int { selectedCounts.max() ?? 0 }
    private var meanCgm10mDelta: Double? {
        let deltas = selectedBGCheckEntries.compactMap { $0.delta10m }
        guard !deltas.isEmpty else { return nil }
        return deltas.reduce(0, +) / Double(deltas.count)
    }
    private let deltaFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "sv_SE")
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        nf.positivePrefix = "+"
        nf.negativePrefix = "-"
        return nf
    }()

    private func longestStreakWithoutSticks() -> Int {
        var best = 0
        var current = 0
        for c in selectedCounts {
            if c == 0 {
                current += 1
                if current > best { best = current }
            } else {
                current = 0
            }
        }
        return best
    }

    private func percentageString(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "0 %" }
        let p = Double(numerator) * 100.0 / Double(denominator)
        return String(format: "%.0f% %", p)
    }

    // MARK: - Table view

    private enum Row: Int, CaseIterable {
        case totalSticks
        case avgPerDay
        case daysWithSticks
        case avgPerStickDay
        case maxPerStickDay
        case longestNoStickStreak
        case dextroShare
        case meanCgm10mDelta
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "BGStatsCell")
        cell.selectionStyle = .none
        
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        if #available(iOS 14.0, *) {
            var bg = UIBackgroundConfiguration.clear()
            bg.backgroundColor = .systemGray.withAlphaComponent(0.15)
            cell.backgroundConfiguration = bg
        }
        cell.textLabel?.backgroundColor = .clear
        cell.detailTextLabel?.backgroundColor = .clear

        let row = Row(rawValue: indexPath.row)!
        switch row {
        case .totalSticks:
            cell.textLabel?.text = "Totalt antal stick"
            cell.detailTextLabel?.text = "\(totalSticks) ggr"

        case .avgPerDay:
            cell.textLabel?.text = "Medel stick per dag"
            if totalDays > 0 {
                let avg = Double(totalSticks) / Double(totalDays)
                cell.detailTextLabel?.text = String(format: "%.1f ggr", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }
            
        case .daysWithSticks:
            cell.textLabel?.text = "Andel dagar med stick"
            cell.detailTextLabel?.text = "\(percentageString(daysWithSticks, totalDays))"
            
        case .avgPerStickDay:
            cell.textLabel?.text = "Medel stick per stick-dag"
            if daysWithSticks > 0 {
                let avg = Double(totalSticks) / Double(daysWithSticks)
                cell.detailTextLabel?.text = String(format: "%.1f ggr", avg)
            } else {
                cell.detailTextLabel?.text = "–"
            }

        case .maxPerStickDay:
            cell.textLabel?.text = "Högsta antal stick per stick-dag"
            cell.detailTextLabel?.text = "\(maxSticksPerDay) ggr"
        case .longestNoStickStreak:
            cell.textLabel?.text = "Längsta streak utan stick"
            let streak = longestStreakWithoutSticks() * 24
            cell.detailTextLabel?.text = "\(streak) h"
        case .dextroShare:
            cell.textLabel?.text = "Andel stick ⇢ 🍬"
            if totalSticks > 0 {
                cell.detailTextLabel?.text = percentageString(totalDextroSticks, totalSticks)
            } else {
                cell.detailTextLabel?.text = "–"
            }
        case .meanCgm10mDelta:
            cell.textLabel?.text = "CGM (+10m) medel Δ"
            if let mean = meanCgm10mDelta {
                let s = deltaFormatter.string(from: NSNumber(value: mean)) ?? String(format: "%+.1f", mean)
                cell.detailTextLabel?.text = "\(s) mmol/L"
            } else {
                cell.detailTextLabel?.text = "–"
            }
        }

        return cell
    }
}
