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
final class TrioSettingsLogView: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Model

    struct SettingsEntry {
        let date: Date
        let note: String
    }

    private var entries: [SettingsEntry] = []

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
        setupTableView()
        setupConstraints()

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

    // MARK: - Setup table

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
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
                self.entries = settingsNotes
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SettingsCell")
        cell.textLabel?.numberOfLines = 1

        let entry = entries[indexPath.row]

        // Leading text = note (kompakt, en rad)
        let note = entry.note
        let compact = note.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "Justerad inställning: ", with: "")
        cell.textLabel?.text = "\(compact)"
        cell.textLabel?.font = .systemFont(ofSize: 16)

        // SF-symbol i imageView (leading) – settings
        cell.imageView?.image = UIImage(systemName: "gearshape")
        cell.imageView?.tintColor = .label.withAlphaComponent(0.5)

        // Right-aligned full date + time
        let rightLabel = UILabel()
        rightLabel.text = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
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

        // Låt raden highlightas kort enligt default-beteende
        tableView.deselectRow(at: indexPath, animated: true)

        // Titel = datum/tid, Message = hela note-texten
        let titleString = DateFormatter.localizedString(from: entry.date, dateStyle: .short, timeStyle: .short)
        let messageString = entry.note

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
