import UIKit

class PumpHistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var pumpHistory: [PumpChangeHistoryEntry] = []
    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    /// Snapshot när modalen öppnas – används för pågående session (från senaste pumpbyte till nu).
    private let openedAt = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pumplogg"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupConstraints()

        loadPumpHistoryFromStorage()
        fetchInitialPumpChangesIfNeeded()
    }

    // MARK: - UI setup

    private func setupNavigationBar() {
        let addBtn = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addManualPumpChange)
        )

        let doneBtn = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        navigationItem.leftBarButtonItem = addBtn
        navigationItem.rightBarButtonItem = doneBtn
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PumpHistoryCell")
    }

    private func setupConstraints() {
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: guide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func addManualPumpChange() {
        let addVC = AddManualPumpViewController()
        addVC.delegate = self
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }

    // MARK: - Storage

    private func loadPumpHistoryFromStorage() {
        pumpHistory = Storage.shared.pumpChangeHistory.sorted { $0.date > $1.date }
        tableView.reloadData()
    }

    // MARK: - Nightscout initial fetch (~90 dagar)

    /// Enkel intern modell för CAge / Site Change från Nightscout.
    private struct PumpCageData: Codable {
        let created_at: String
    }

    private func fetchInitialPumpChangesIfNeeded() {
        // Om vi redan har historik i storage hoppar vi över första fetchen.
        guard Storage.shared.pumpChangeHistory.isEmpty else { return }

        let now = Date()
        guard let since = Calendar.current.date(byAdding: .day, value: -90, to: now) else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)

        let params: [String: String] = [
            "find[eventType]": "Site Change",
            "find[created_at][$gte]": iso.string(from: since),
            "find[created_at][$lte]": iso.string(from: now)
        ]

        // Vi använder .cage för semantik, men endpointen är samma som treatments.
        NightscoutUtils.executeRequest(
            eventType: .cage,
            parameters: params
        ) { (result: Result<[PumpCageData], Error>) in
            switch result {
            case .failure(let error):
                LogManager.shared.log(
                    category: .treatments,
                    message: "❌ Failed to fetch pump Site Change history: \(error)",
                    isDebug: true
                )
            case .success(let cageEntries):
                var merged = Storage.shared.pumpChangeHistory
                for c in cageEntries {
                    guard let date = NightscoutUtils.parseDate(c.created_at) else { continue }
                    let entry = PumpChangeHistoryEntry(date: date.timeIntervalSince1970)
                    if !merged.contains(where: { $0.date == entry.date }) {
                        merged.append(entry)
                    }
                }
                merged.sort { $0.date > $1.date }
                Storage.shared.pumpChangeHistory = merged
                self.pumpHistory = merged
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Helpers – sessionstid

    private func sessionColor(for hours: Int, isOngoing: Bool) -> UIColor {
        if isOngoing { return .systemBlue }
        if hours < 50 { return .systemRed }
        if hours < 70 { return .systemOrange }
        return .systemGreen
    }

    private func sessionInfo(for index: Int) -> (text: String, hours: Int, isOngoing: Bool) {
        let current = pumpHistory[index]
        let currentStart = Date(timeIntervalSince1970: current.date)
        let isOngoing = (index == 0)
        let endDate: Date = isOngoing ? openedAt : Date(timeIntervalSince1970: pumpHistory[index - 1].date)
        let interval = max(0, endDate.timeIntervalSince(currentStart))
        let hours = Int(interval / 3600)
        let prefix = isOngoing ? "Pågående" : "Session"
        return ("(\(prefix): \(hours) timmar)", hours, isOngoing)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pumpHistory.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "PumpHistoryCell",
            for: indexPath
        )

        let entry = pumpHistory[indexPath.row]
        let date = Date(timeIntervalSince1970: entry.date)

        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = df.string(from: date)

        let sessionInfo = sessionInfo(for: indexPath.row)

        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let smallBody = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: baseFont.withSize(baseFont.pointSize - 1))

        let attrsBase: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: cell.textLabel?.textColor ?? UIColor.label
        ]

        let sessionAttrs: [NSAttributedString.Key: Any] = [
            .font: smallBody,
            .foregroundColor: sessionColor(for: sessionInfo.hours, isOngoing: sessionInfo.isOngoing)
        ]

        let composed = NSMutableAttributedString()
        composed.append(NSAttributedString(string: dateString, attributes: attrsBase))
        composed.append(NSAttributedString(string: " \(sessionInfo.text)\n", attributes: sessionAttrs))
        composed.append(NSAttributedString(string: "Pumpbyte", attributes: attrsBase))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = composed

        return cell
    }

    // MARK: - Swipe actions (Redigera / Radera)

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {

        let entry = pumpHistory[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Radera") { _, _, completion in
            var stored = Storage.shared.pumpChangeHistory
            if let idx = stored.firstIndex(where: { $0.date == entry.date }) {
                stored.remove(at: idx)
                Storage.shared.pumpChangeHistory = stored
            }
            self.pumpHistory.removeAll(where: { $0.date == entry.date })
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }

        let editAction = UIContextualAction(style: .normal, title: "Redigera") { _, _, completion in
            let editVC = AddManualPumpViewController()
            editVC.delegate = self
            editVC.configureForEditing(entry: entry, index: indexPath.row)
            let nav = UINavigationController(rootViewController: editVC)
            self.present(nav, animated: true)
            completion(true)
        }

        editAction.backgroundColor = .systemBlue

        let config = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

// MARK: - AddManualPumpDelegate

extension PumpHistoryViewController: AddManualPumpDelegate {
    func didAddManualPumpChange(entry: PumpChangeHistoryEntry) {
        var stored = Storage.shared.pumpChangeHistory
        if !stored.contains(where: { $0.date == entry.date }) {
            stored.append(entry)
            stored.sort { $0.date > $1.date }
            Storage.shared.pumpChangeHistory = stored
        }
        pumpHistory = stored
        tableView.reloadData()
    }

    func didUpdateManualPumpChange(entry: PumpChangeHistoryEntry, at index: Int) {
        var stored = Storage.shared.pumpChangeHistory

        // Original entry i tabellens nuvarande ordning
        let original = pumpHistory[index]
        if let storedIndex = stored.firstIndex(where: { $0.date == original.date }) {
            stored[storedIndex] = entry
            stored.sort { $0.date > $1.date }
            Storage.shared.pumpChangeHistory = stored
        }
        pumpHistory = stored
        tableView.reloadData()
    }
}
