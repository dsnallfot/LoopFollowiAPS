//
//  TrioSettingsLogView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-12-17.

//

import UIKit
import Charts

/// Enkel loggvy för att fånga noteringar innehållande "Trio startades om" , inspirerad av BGCheckView.
final class TrioSettingsLogView: ThemedViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    // MARK: - Model

    struct SettingsEntry {
        let date: Date
        let note: String
    }

    private var entries: [SettingsEntry] = []

    private var allEntries: [SettingsEntry] = []

    private let searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Sök ändrade inställningar"
        sb.autocapitalizationType = .none
        sb.autocorrectionType = .no
        sb.searchBarStyle = .minimal
        return sb
    }()
    
    private let initialSearchText: String?

    private let topSearchContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

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
    private var reloadButton: UIBarButtonItem?

    init(initialSearchText: String? = nil) {
        self.initialSearchText = initialSearchText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.initialSearchText = nil
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        title = "Trio inställningslogg"

        setupNavigationBar()
        searchBar.delegate = self
        // Pre-filter directly when opened from TrioPreferencesView
        if let initial = initialSearchText, !initial.isEmpty {
            searchBar.text = initial
        }
        // Make search text field background partially translucent for blend
        if #available(iOS 13.0, *) {
            searchBar.searchTextField.backgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
        }
        installPinnedSearchBar()
        setupTableView()
        setupConstraints()
        navigationItem.hidesSearchBarWhenScrolling = false

        loadSettings()
        // Apply filter immediately (will also be applied again after load finishes)
        applyFilter(searchText: searchBar.text)
    }

    // MARK: - Nav bar

    private func setupNavigationBar() {
        // Behåll "Klar" när vi är modalt root, men göm den när vi är pushade.
        let isModalRoot = navigationController?.viewControllers.first === self

        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        self.reloadButton = reload

        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        if isModalRoot {
            // Modal: Klar till höger, reload till vänster.
            navigationItem.rightBarButtonItems = [done]
            navigationItem.leftBarButtonItem = reload
        } else {
            // Pushad under Settings: ingen Klar, back + reload.
            navigationItem.rightBarButtonItems = []
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItems = [reload]
        }
    }

    @objc private func doneTapped() {
        // If presented modally (wrapped in a UINavigationController), dismiss.
        if presentingViewController != nil {
            dismiss(animated: true)
            return
        }

        // If pushed in a nav stack, pop.
        navigationController?.popViewController(animated: true)
    }

    @objc private func refreshTapped() {
        loadSettings()
    }
    
    private func installPinnedSearchBar() {
        // Add a non-scrolling container under the nav bar
        view.addSubview(topSearchContainer)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topSearchContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            topSearchContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            topSearchContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ])

        let sb = searchBar
        sb.translatesAutoresizingMaskIntoConstraints = false
        topSearchContainer.addSubview(sb)
        NSLayoutConstraint.activate([
            sb.leadingAnchor.constraint(equalTo: topSearchContainer.leadingAnchor, constant: 12),
            sb.trailingAnchor.constraint(equalTo: topSearchContainer.trailingAnchor, constant: -12),
            sb.topAnchor.constraint(equalTo: topSearchContainer.topAnchor, constant: 6),
            sb.bottomAnchor.constraint(equalTo: topSearchContainer.bottomAnchor, constant: -2)
        ])
/*
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor.separator
        topSearchContainer.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.heightAnchor.constraint(equalToConstant: 0.5),
            sep.leadingAnchor.constraint(equalTo: topSearchContainer.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: topSearchContainer.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: topSearchContainer.bottomAnchor)
        ])
        */
    }

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.rowHeight = 50
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .onDrag
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false

        // Searchbar under navbaren
        searchBar.delegate = self
        searchBar.sizeToFit()
    }

    private func setupConstraints() {
        let guide = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topSearchContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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

    /// Hämtar alla `Note`-treatments från cachen vars notes innehåller "Trio startades om".
    private func loadSettings() {
        showActivity()

        Task {
            let now = Date()
            let cal = Calendar.current

            let start = cal.date(
                byAdding: .day,
                value: -NightscoutCache.retentionDays,
                to: now
            ) ?? now.addingTimeInterval(-90 * 24 * 60 * 60)

            let (_, treatments) = await NightscoutCache.loadWindow(from: start, to: now)

            let settingsNotes: [SettingsEntry] = treatments.compactMap { t -> SettingsEntry? in
                guard t.eventType == "Note" else { return nil }

                guard
                    let note = t.notes,
                    note.contains("Justerad") || note.contains("ändrades")
                else {
                    return nil
                }

                let date = t.created_at
                return SettingsEntry(date: date, note: note)
            }
            .sorted { $0.date > $1.date }

            await MainActor.run {
                self.allEntries = settingsNotes
                self.applyFilter(searchText: self.searchBar.text)
                self.hideActivity()
            }
        }
    }

    func setSearchTextAndFilter(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Ensure UI updates happen on the main thread
        DispatchQueue.main.async {
            if self.searchBar.text != trimmed {
                self.searchBar.text = trimmed
            }
            self.applyFilter(searchText: trimmed)
        }
    }

    private func applyFilter(searchText: String?) {
        let raw = (searchText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize so that searches are tolerant to formatting differences like "adjustmentFactor" vs "adjustment_Factor"
        func normalize(_ s: String) -> String {
            return s
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
        }

        let q = normalize(raw)

        if q.isEmpty {
            entries = allEntries
        } else {
            entries = allEntries.filter { normalize($0.note).contains(q) }
        }

        tableView.reloadData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText: searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        applyFilter(searchText: nil)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return entries.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SettingsCell")
        cell.textLabel?.numberOfLines = 1

        let entry = entries[indexPath.row]

        // Leading text = note (kompakt, en rad)
        let note = entry.note
        let compact = note.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "Justerad inställning: ", with: "").replacingOccurrences(of: " ändrades", with: "")
        cell.textLabel?.text = "\(compact)"
        cell.textLabel?.font = .systemFont(ofSize: 16)

        // SF-symbol i imageView (leading) – settings
        cell.imageView?.image = UIImage(systemName: "gearshape")
        cell.imageView?.tintColor = .label.withAlphaComponent(0.5)

        // Right-aligned full date
        let rightLabel = UILabel()
        rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .none)
        rightLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)//.systemFont(ofSize: 14)
        rightLabel.textColor = .secondaryLabel
        rightLabel.textAlignment = .right
        rightLabel.sizeToFit()
        cell.accessoryView = rightLabel

        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .default
        cell.accessoryType = .none
        // Match Treatments-style selection highlight (subtle overlay over the gradient)
        let selected = UIView()
        selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        selected.layer.cornerRadius = 10
        selected.layer.masksToBounds = true
        cell.selectedBackgroundView = selected
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.row]
        
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "dd MMM HH:mm:ss"
        let timeString = timeFormatter.string(from: entry.date)


        // Titel = datum/tid, Message = hela note-texten
        let titleString = timeString //DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        let messageString = entry.note.replacingOccurrences(of: "Justerad inställning: ", with: "Justerad inställning: \n").replacingOccurrences(of: "ändrades: ", with: "ändrades: \n").replacingOccurrences(of: ", ", with: "\n")

        let alert = UIAlertController(title: titleString, message: messageString, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Analys", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            tableView.deselectRow(at: indexPath, animated: true)
            self.presentAnalysisModal(startDate: entry.date)
        }))

        alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { _ in
            tableView.deselectRow(at: indexPath, animated: true)
        }))

        present(alert, animated: true)
    }
    
    private func presentAnalysisModal(startDate: Date) {
        // Hitta MainViewController via root UITabBarController för att få events,
        // men presentera modalen härifrån så vi kommer tillbaka hit när den stängs.

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
            if let nav = vc as? UINavigationController,
               let candidate = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                mainVC = candidate
                break
            } else if let candidate = vc as? MainViewController {
                mainVC = candidate
                break
            }
        }

        guard let mainVC else {
            return
        }

        // Bygg events via MainViewController, men presentera modalen härifrån.
        let events = mainVC.buildEventsForMealAnalysis()
        let endDate = startDate + 60 * 60 * 12

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            initialEnd: endDate,
            modalWithTimestamp: true,
            modalTitleString: "Analys ändring",
            preSelectedSegment: 4
        )
        let nav = UINavigationController(rootViewController: analysisVC)
        nav.modalPresentationStyle = .formSheet
        self.present(nav, animated: true)
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}
