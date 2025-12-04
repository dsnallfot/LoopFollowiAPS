import UIKit

/// Enkel loggvy för fingerstick / BG Check, inspirerad av GlucoseView.
final class BGCheckView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct BGCheckEntry {
        let date: Date
        let mmol: Double
    }

    private var entries: [BGCheckEntry] = []

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

    private var activityIndicator: UIActivityIndicatorView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Fingerstick"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadBGChecks()
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        // Reload-knapp (samma look & feel som GlucoseView)
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )

        navigationItem.leftBarButtonItem = reload

        // Klar-knapp till höger, så det känns som Treatments/Glucose
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.rightBarButtonItem = done
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func refreshTapped() {
        loadBGChecks()
    }

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BGCheckCell")
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safe.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
    }

    // MARK: - Loading from cache

    private func showActivity() {
        if activityIndicator == nil {
            let ind = UIActivityIndicatorView(style: .medium)
            ind.hidesWhenStopped = true
            activityIndicator = ind
            navigationItem.titleView = ind
        }
        activityIndicator?.startAnimating()
    }

    private func hideActivity() {
        activityIndicator?.stopAnimating()
        navigationItem.titleView = nil
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
            ) ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            // Antag att NightscoutCache.loadWindow(from:to:) returnerar (sgv, treatments)
            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

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

                return BGCheckEntry(date: date, mmol: mmol)
            }
            .sorted { $0.date > $1.date } // nyast överst

            await MainActor.run {
                self.entries = bgChecks
                self.tableView.reloadData()
                self.hideActivity()
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BGCheckCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "BGCheckCell")
        cell.textLabel?.numberOfLines = 1

        let entry = entries[indexPath.row]

        // Leading SF Symbol + värde i mmol/L
        let mmolString = valueFormatter.string(from: NSNumber(value: entry.mmol)) ?? String(format: "%.1f", entry.mmol)
        cell.textLabel?.text = " \(mmolString) mmol/L"
        cell.textLabel?.font = .systemFont(ofSize: 17)

        // SF-symbol i imageView (leading)
        cell.imageView?.image = UIImage(systemName: "drop.fill")
        cell.imageView?.tintColor = .systemRed

        // Right‑aligned full date + time
        let rightLabel = UILabel()
        rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        rightLabel.font = .systemFont(ofSize: 15)
        rightLabel.textColor = .secondaryLabel
        rightLabel.textAlignment = .right
        rightLabel.sizeToFit()
        cell.accessoryView = rightLabel

        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}
