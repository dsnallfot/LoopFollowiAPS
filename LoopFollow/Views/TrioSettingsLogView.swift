//
//  TrioSettingsLogView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-12-17.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import UIKit
import Charts

/// Enkel loggvy för att fånga noteringar innehållande "Trio startades om" , inspirerad av BGCheckView.
final class TrioSettingsLogView: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trio inställningslogg"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        searchBar.delegate = self
        installPinnedSearchBar()
        setupTableView()
        setupConstraints()
        navigationItem.hidesSearchBarWhenScrolling = false

        loadSettings()
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

        navigationItem.rightBarButtonItems = [done]
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
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

    private func applyFilter(searchText: String?) {
        let q = (searchText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            entries = allEntries
        } else {
            let lower = q.lowercased()
            entries = allEntries.filter { $0.note.lowercased().contains(lower) }
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
        rightLabel.font = .systemFont(ofSize: 15)
        rightLabel.textColor = .secondaryLabel
        rightLabel.textAlignment = .right
        rightLabel.sizeToFit()
        cell.accessoryView = rightLabel

        cell.selectionStyle = .default
        cell.accessoryType = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.row]
        
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "dd MMM HH:mm:ss"
        let timeString = timeFormatter.string(from: entry.date)

        // Låt raden highlightas kort enligt default-beteende
        tableView.deselectRow(at: indexPath, animated: true)

        // Titel = datum/tid, Message = hela note-texten
        let titleString = timeString //DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        let messageString = entry.note.replacingOccurrences(of: "Justerad inställning: ", with: "Justerad inställning: \n").replacingOccurrences(of: "ändrades: ", with: "ändrades: \n").replacingOccurrences(of: ", ", with: "\n")

        let alert = UIAlertController(title: titleString, message: messageString, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Analys", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.presentAnalysisModal(startDate: entry.date)
        }))

        alert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))

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

        let analysisVC = MealAnalysisView(
            events: events,
            initialStart: startDate,
            modalWithTimestamp: true,
            modalTitleString: "Utv. efter ändring"
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
