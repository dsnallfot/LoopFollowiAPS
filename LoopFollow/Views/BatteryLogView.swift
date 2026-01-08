//
//  BatteryLogView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-01-08.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Battery Log

struct BatteryEntry {
    let date: Date
    let percent: Double
    let isCharging: Bool
}

/// Simple day-filtered battery log table.
final class BatteryLogViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    private var entries: [BatteryEntry] = []
    private var selectedDate: Date = Date()

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .date
        dp.preferredDatePickerStyle = .compact
        dp.translatesAutoresizingMaskIntoConstraints = false
        return dp
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trio Batterilogg"
        updateBackgroundForCurrentMode()

        setupNavigationBar()
        setupTableView()
        setupHeader()
        setupConstraints()

        // Date picker bounds follow cache retention
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day, value: -BatteryCache.retentionDays + 1, to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)

        loadDay(selectedDate)
    }

    private func setupNavigationBar() {
        let done = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

        let stats = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(showStats)
        )
        stats.tintColor = .label

        navigationItem.rightBarButtonItems = [done, stats]
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func showStats() {
        let statsVC = BatteryLogStatsViewController()
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

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "BatteryCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.isOpaque = false
    }

    private func setupHeader() {
        // Simple header: date picker only (day filter)
        view.addSubview(datePicker)
        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true
    }

    private func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            datePicker.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),

            tableView.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadDay(selectedDate)
    }

    private func loadDay(_ date: Date) {
        Task {
            let samples = await BatteryCache.loadDay(date)
            let mapped: [BatteryEntry] = samples.map {
                BatteryEntry(date: Date(timeIntervalSince1970: $0.date), percent: $0.percent, isCharging: $0.isCharging)
            }

            await MainActor.run {
                // Newest first
                self.entries = mapped.sorted { $0.date > $1.date }
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(entries.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "BatteryCell", for: indexPath) as? Value1TableViewCell else {
            return UITableViewCell(style: .value1, reuseIdentifier: "BatteryCell")
        }

        if entries.isEmpty {
            cell.textLabel?.text = "Inga batteridata"
            cell.detailTextLabel?.text = ""
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell
        }

        let e = entries[indexPath.row]
        let timeStr = timeFormatter.string(from: e.date)
        let charging = e.isCharging ? "⚡" : ""

        cell.textLabel?.text = String(format: "%.0f%% %@", e.percent, charging)
        cell.detailTextLabel?.text = timeStr
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

/// Placeholder stats view – we’ll design charts later.
final class BatteryLogStatsViewController: ThemedTableViewController {

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateBackgroundForCurrentMode()
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.layer.backgroundColor = UIColor.clear.cgColor
        title = "Batteristatistik"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BatteryStatsCell")
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BatteryStatsCell", for: indexPath)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = "Graf/visualisering kommer i nästa steg.\n\nJust nu bygger vi bara upp batterihistoriken lokalt (upp till 91 dagar)."
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        return cell
    }
}
