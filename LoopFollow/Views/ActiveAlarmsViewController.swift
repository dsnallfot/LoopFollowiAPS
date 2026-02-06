//
//  ActiveAlarmsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2026-02-06.
//

import Combine
import Foundation
import UIKit

// MARK: - ActiveAlarmsViewController

private struct ActiveAlarmRow {
    let title: String
    let getIsOn: () -> Bool
    let setIsOn: (Bool) -> Void
}

private enum ActiveAlarmSection: Int, CaseIterable {
    case bg
    case trend
    case trio
    case tech
    case other

    var title: String {
        switch self {
        case .bg:
            return "Hög/Låg-larm"
        case .trend:
            return "Trendlarm"
        case .trio:
            return "Trio-larm"
        case .tech:
            return "Tekniklarm"
        case .other:
            return "Övriga larm"
        }
    }
}

final class ActiveAlarmsViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate {

    /// Called when the view controller is dismissed, so the caller can refresh its UI
    var onDismiss: (() -> Void)?

    private var tableView: UITableView!
    private var rowsBySection: [[ActiveAlarmRow]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Aktiva alarm"
        updateBackgroundForCurrentMode()
        configureDoneButton()
        buildRows()
        setupTableView()
    }

    private func configureDoneButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    @objc private func doneTapped() {
        // Inform caller so it can refresh its UI (e.g. ModernAlarmViewController)
        onDismiss?()
        dismiss(animated: true, completion: nil)
    }

    private func buildRows() {
        // Hög/Låg-larm
        let bgRows: [ActiveAlarmRow] = [
            ActiveAlarmRow(
                title: "Akut låg",
                getIsOn: { UserDefaultsRepository.alertUrgentLowActive.value },
                setIsOn: { UserDefaultsRepository.alertUrgentLowActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Låg",
                getIsOn: { UserDefaultsRepository.alertLowActive.value },
                setIsOn: { UserDefaultsRepository.alertLowActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Hög",
                getIsOn: { UserDefaultsRepository.alertHighActive.value },
                setIsOn: { UserDefaultsRepository.alertHighActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Akut hög",
                getIsOn: { UserDefaultsRepository.alertUrgentHighActive.value },
                setIsOn: { UserDefaultsRepository.alertUrgentHighActive.value = $0 }
            )
        ]

        // Trendlarm
        let trendRows: [ActiveAlarmRow] = [
            ActiveAlarmRow(
                title: "Sjunker snabbt",
                getIsOn: { UserDefaultsRepository.alertFastDropActive.value },
                setIsOn: { UserDefaultsRepository.alertFastDropActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Stiger snabbt",
                getIsOn: { UserDefaultsRepository.alertFastRiseActive.value },
                setIsOn: { UserDefaultsRepository.alertFastRiseActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Tillfälligt",
                getIsOn: { UserDefaultsRepository.alertTemporaryActive.value },
                setIsOn: { UserDefaultsRepository.alertTemporaryActive.value = $0 }
            )
        ]

        // Trio-larm
        let trioRows: [ActiveAlarmRow] = [
            ActiveAlarmRow(
                title: "Saknar värden",
                getIsOn: { UserDefaultsRepository.alertMissedReadingActive.value },
                setIsOn: { UserDefaultsRepository.alertMissedReadingActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Loopar inte",
                getIsOn: { UserDefaultsRepository.alertNotLoopingActive.value },
                setIsOn: { UserDefaultsRepository.alertNotLoopingActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Lågt batteri",
                getIsOn: { UserDefaultsRepository.alertBatteryActive.value },
                setIsOn: { UserDefaultsRepository.alertBatteryActive.value = $0 }
            )
        ]

        // Tekniklarm
        let techRows: [ActiveAlarmRow] = [
            ActiveAlarmRow(
                title: "Sensorbyte",
                getIsOn: { UserDefaultsRepository.alertSAGEActive.value },
                setIsOn: { UserDefaultsRepository.alertSAGEActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Pumpbyte",
                getIsOn: { UserDefaultsRepository.alertCAGEActive.value },
                setIsOn: { UserDefaultsRepository.alertCAGEActive.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Reservoar",
                getIsOn: { UserDefaultsRepository.alertPump.value },
                setIsOn: { UserDefaultsRepository.alertPump.value = $0 }
            )
        ]

        // Övriga larm
        let otherRows: [ActiveAlarmRow] = [
            ActiveAlarmRow(
                title: "COB",
                getIsOn: { UserDefaultsRepository.alertCOB.value },
                setIsOn: { UserDefaultsRepository.alertCOB.value = $0 }
            ),
            ActiveAlarmRow(
                title: "IOB",
                getIsOn: { UserDefaultsRepository.alertIOB.value },
                setIsOn: { UserDefaultsRepository.alertIOB.value = $0 }
            ),
            ActiveAlarmRow(
                title: "Missad bolus",
                getIsOn: { UserDefaultsRepository.alertMissedBolusActive.value },
                setIsOn: { UserDefaultsRepository.alertMissedBolusActive.value = $0 }
            )
        ]

        rowsBySection = [bgRows, trendRows, trioRows, techRows, otherRows]
    }

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ActiveAlarmCell")
        view.addSubview(tableView)
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return ActiveAlarmSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section >= 0 && section < rowsBySection.count else { return 0 }
        return rowsBySection[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ActiveAlarmCell", for: indexPath)
        guard indexPath.section < rowsBySection.count,
              indexPath.row < rowsBySection[indexPath.section].count else {
            cell.textLabel?.text = nil
            cell.accessoryView = nil
            return cell
        }

        let row = rowsBySection[indexPath.section][indexPath.row]
        cell.textLabel?.text = row.title
        cell.selectionStyle = .none

        let toggle = UISwitch()
        toggle.isOn = row.getIsOn()
        toggle.tag = indexPath.section * 100 + indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
        cell.backgroundConfiguration = background

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionType = ActiveAlarmSection(rawValue: section) else { return nil }
        return sectionType.title
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // Toggla även när man trycker på raden
        guard let cell = tableView.cellForRow(at: indexPath),
              let toggle = cell.accessoryView as? UISwitch else { return }
        toggle.setOn(!toggle.isOn, animated: true)
        toggleChanged(toggle)
    }

    // MARK: - Actions

    @objc private func toggleChanged(_ sender: UISwitch) {
        let section = sender.tag / 100
        let rowIndex = sender.tag % 100
        guard section >= 0, section < rowsBySection.count,
              rowIndex >= 0, rowIndex < rowsBySection[section].count else { return }
        let row = rowsBySection[section][rowIndex]
        row.setIsOn(sender.isOn)
    }
}

