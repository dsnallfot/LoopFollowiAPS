//
//  SettingsViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/3/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//


import UIKit
import EventKit
import EventKitUI
import SwiftUI

@available(iOS 26.0, *)
class SettingsViewController: ThemedViewController, NightscoutSettingsViewModelDelegate, UITableViewDataSource, UITableViewDelegate {
    var appStateController: AppStateController?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Background color used for section "cards", mirroring TrioOrefView list row background.
    private let sectionBackgroundColor = UIColor.systemGray.withAlphaComponent(0.1)
    
    // Controls whether the Nightscout-specific "Informationsinställningar" row is shown.
    private var hideNightscoutInfoRow = false
    
    // App info strings for the "Appinformation" section.
    private var currentVersion: String = ""
    private var latestVersion: String = "Fetching..."
    private var buildDateString: String = ""
    private var branchAndShaString: String = ""
    private var expirationHeaderString: String = ""
    private var expirationDateString: String = ""
    private var trioExpirationString: String = ""
    private var versionStatusColor: UIColor = .secondaryLabel
    
    // Section + row modeling for the table view.
    private enum Section: Int, CaseIterable {
        case historyStats
        case trioSettings
        case dataCapture
        case appSettings
        case integrations
        case systemLog
        case appInfo
    }
    
    private enum AppSettingsRow {
        case alarms, general, graphs, infoDisplay, advanced
    }
    
    private enum AppInfoRow {
        case version, latestVersion, expiration, build, branch, trioExpiration
    }
    
    private var appSettingsRows: [AppSettingsRow] {
        hideNightscoutInfoRow
        ? [.alarms, .general, .graphs, .advanced]
        : [.alarms, .general, .graphs, .infoDisplay, .advanced]
    }
    
    private var appInfoRows: [AppInfoRow] {
        var rows: [AppInfoRow] = [.version, .latestVersion]
        if !isMacApp() {
            rows.append(.expiration)
        }
        rows.append(contentsOf: [.build, .branch])
        if !isMacApp() {
            rows.append(.trioExpiration)
        }
        return rows
    }

    func showHideNSDetails() {
        let isEnabled = IsNightscoutEnabled()
        hideNightscoutInfoRow = !isEnabled
        
        // Enable/disable the Nightscout tab.
        if let nightscoutTab = self.tabBarController?.tabBar.items?[3] {
            nightscoutTab.isEnabled = isEnabled
        }
        
        // Update the settings list to hide/show the Nightscout info row.
        tableView.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "App & Data"
        
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        
        // Prepare static app info values.
        let buildDetails = BuildDetails.default
        buildDateString = dateTimeUtils.formattedDate(from: buildDetails.buildDate())
        branchAndShaString = buildDetails.branchAndSha
        expirationDateString = dateTimeUtils.formattedDate(from: buildDetails.calculateExpirationDate())
        expirationHeaderString = buildDetails.expirationHeaderString
        let versionManager = AppVersionManager()
        currentVersion = versionManager.version()
        trioExpirationString = ProfileManager.shared.trioExpirationFormatted ?? "Unknown"
        
        // Configure table view.
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        showHideNSDetails()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        refreshVersionInfo()
    }

    func refreshVersionInfo() {
        let versionManager = AppVersionManager()
        versionManager.checkForNewVersion { latestVersion, isNewer, isBlacklisted in
            DispatchQueue.main.async {
                self.versionStatusColor = self.getColor(
                    isBlacklisted: isBlacklisted,
                    isNewer: isNewer,
                    isCurrent: latestVersion == versionManager.version()
                )
                self.latestVersion = latestVersion ?? "Unknown"
                
                // Reload only the Appinformation section.
                if let sectionIndex = Section.allCases.firstIndex(of: .appInfo) {
                    self.tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
                } else {
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func getColor(isBlacklisted: Bool, isNewer: Bool, isCurrent: Bool) -> UIColor {
        if isBlacklisted {
            return .red
        } else if isNewer {
            return .orange
        } else if isCurrent {
            return .green
        } else {
            return .secondaryLabel
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionKind = Section(rawValue: section) else { return 0 }
        switch sectionKind {
        case .historyStats:
            // Statistik, Behandlingar, Fingerstick & dextro, Glukos & sensorfel, Poddar, Sensorer
            return 6
        case .trioSettings:
            // Algoritminställningar, Hälsodata & profil, Oref-status, Inställningslogg, Batterilogg, Omstartslogg
            return 6
        case .dataCapture:
            // Enhet, Nightscoutinställningar, Dexcominställningar
            return 3
        case .appSettings:
            return appSettingsRows.count
        case .integrations:
            // Bakgrundsaktivitet, Sensorbyten synk, Fjärrkontrollinställningar, Kalendertrick, Kontakttrick
            return 5
        case .systemLog:
            // Se dagens logg, Dela logg
            return 2
        case .appInfo:
            return appInfoRows.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionKind = Section(rawValue: section) else { return nil }
        switch sectionKind {
        case .historyStats:
            return "Historik & statistik"
        case .trioSettings:
            return "\nTrio inställningar och status"
        case .dataCapture:
            return "\nDatafångstinställningar"
        case .appSettings:
            return "\nAppinställningar"
        case .integrations:
            return "\nIntegrationer"
        case .systemLog:
            return "\nSystemlogg"
        case .appInfo:
            return "\nAppinformation"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionKind = Section(rawValue: indexPath.section) else {
            return UITableViewCell(style: .default, reuseIdentifier: "Cell")
        }

        switch sectionKind {
        case .historyStats:
            let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell") ?? UITableViewCell(style: .default, reuseIdentifier: "HistoryCell")
            cell.accessoryType = .disclosureIndicator
            switch indexPath.row {
            case 0: cell.textLabel?.text = "Statistik"
            case 1: cell.textLabel?.text = "Behandlingar"
            case 2: cell.textLabel?.text = "Fingerstick & dextro"
            case 3: cell.textLabel?.text = "Glukos & sensorfel"
            case 4: cell.textLabel?.text = "Poddar"
            case 5: cell.textLabel?.text = "Sensorer"
            default: break
            }
            return cell

        case .trioSettings:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TrioCell") ?? UITableViewCell(style: .default, reuseIdentifier: "TrioCell")
            cell.accessoryType = .disclosureIndicator
            switch indexPath.row {
            case 0: cell.textLabel?.text = "Algoritminställningar & analys"
            case 1: cell.textLabel?.text = "Hälsodata & profilinställningar"
            case 2: cell.textLabel?.text = "Oref realtidsstatus"
            case 3: cell.textLabel?.text = "Inställningslogg"
            case 4: cell.textLabel?.text = "Batterilogg"
            case 5: cell.textLabel?.text = "Omstartslogg"
            default: break
            }
            return cell

        case .dataCapture:
            if indexPath.row == 0 {
                // Enhet with segmented control
                let cell = tableView.dequeueReusableCell(withIdentifier: "UnitsCell") ?? UITableViewCell(style: .default, reuseIdentifier: "UnitsCell")
                cell.textLabel?.text = "Enhet"
                cell.selectionStyle = .none

                let segmented = UISegmentedControl(items: ["mg/dL", "mmol/L"])
                let currentUnits = UserDefaultsRepository.units.value
                segmented.selectedSegmentIndex = (currentUnits == "mg/dL") ? 0 : 1
                segmented.addTarget(self, action: #selector(unitsSegmentChanged(_:)), for: .valueChanged)
                cell.accessoryView = segmented
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "DataCaptureCell") ?? UITableViewCell(style: .default, reuseIdentifier: "DataCaptureCell")
                cell.accessoryType = .disclosureIndicator
                if indexPath.row == 1 {
                    cell.textLabel?.text = "Nightscoutinställningar"
                } else {
                    cell.textLabel?.text = "Dexcominställningar"
                }
                return cell
            }

        case .appSettings:
            let rowKind = appSettingsRows[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "AppSettingsCell") ?? UITableViewCell(style: .default, reuseIdentifier: "AppSettingsCell")
            cell.accessoryType = .disclosureIndicator
            switch rowKind {
            case .alarms:
                cell.textLabel?.text = "Alarminställningar"
            case .general:
                cell.textLabel?.text = "Allmänna inställningar"
            case .graphs:
                cell.textLabel?.text = "Grafinställningar"
            case .infoDisplay:
                cell.textLabel?.text = "Informationsinställningar"
            case .advanced:
                cell.textLabel?.text = "Avancerade inställningar"
            }
            return cell

        case .integrations:
            let cell = tableView.dequeueReusableCell(withIdentifier: "IntegrationsCell") ?? UITableViewCell(style: .default, reuseIdentifier: "IntegrationsCell")
            cell.accessoryType = .disclosureIndicator
            switch indexPath.row {
            case 0: cell.textLabel?.text = "Bakgrundsaktivitet"
            case 1: cell.textLabel?.text = "Sensorbyten synk"
            case 2: cell.textLabel?.text = "Fjärrkontrollinställningar"
            case 3: cell.textLabel?.text = "Kalendertrick"
            case 4: cell.textLabel?.text = "Kontakttrick"
            default: break
            }
            return cell

        case .systemLog:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SystemLogCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SystemLogCell")
            if indexPath.row == 0 {
                cell.textLabel?.text = "Se dagens logg"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Dela logg"
                cell.accessoryType = .none
            }
            return cell

        case .appInfo:
            let rowKind = appInfoRows[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "AppInfoCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "AppInfoCell")
            cell.selectionStyle = .none
            cell.accessoryType = .none

            switch rowKind {
            case .version:
                cell.textLabel?.text = "Version"
                cell.detailTextLabel?.text = currentVersion
                cell.detailTextLabel?.textColor = versionStatusColor
            case .latestVersion:
                cell.textLabel?.text = "Senaste version"
                cell.detailTextLabel?.text = latestVersion
                cell.detailTextLabel?.textColor = .secondaryLabel
            case .expiration:
                cell.textLabel?.text = expirationHeaderString
                cell.detailTextLabel?.text = expirationDateString
                cell.detailTextLabel?.textColor = .secondaryLabel
            case .build:
                cell.textLabel?.text = "Bygge"
                cell.detailTextLabel?.text = buildDateString
                cell.detailTextLabel?.textColor = .secondaryLabel
            case .branch:
                cell.textLabel?.text = "Branch"
                cell.detailTextLabel?.text = branchAndShaString
                cell.detailTextLabel?.textColor = .secondaryLabel
            case .trioExpiration:
                cell.textLabel?.text = "Trio löper ut"
                cell.detailTextLabel?.text = trioExpirationString
                cell.detailTextLabel?.textColor = .secondaryLabel
            }
            return cell
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        // Matcha kort-bakgrunden (inkl. bakom chevrons)
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = sectionBackgroundColor
            cell.backgroundConfiguration = background
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionKind = Section(rawValue: indexPath.section) else { return }

        switch sectionKind {
        case .historyStats:
            switch indexPath.row {
            case 0:
                // Statistik
                let mainVC = resolveMainViewController()
                let viewModel = AggregatedStatsViewModel(mainViewController: mainVC)
                let rootView = AggregatedStatsView(viewModel: viewModel, showsDoneButton: false)
                let hostingController = UIHostingController(rootView: rootView)
                hostingController.title = "Statistik"
                hostingController.hidesBottomBarWhenPushed = false
                if UserDefaultsRepository.forceDarkMode.value {
                    hostingController.overrideUserInterfaceStyle = .dark
                }
                navigationController?.pushViewController(hostingController, animated: true)

            case 1:
                // Behandlingar
                let treatmentsVC = TreatmentsTableView()
                treatmentsVC.title = "Behandlingar"
                treatmentsVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(treatmentsVC, animated: true)

            case 2:
                // Fingerstick & dextro
                let bgCheckVC = BGCheckView()
                bgCheckVC.title = "Fingerstick"
                bgCheckVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(bgCheckVC, animated: true)

            case 3:
                // Glukos & sensorfel
                let glucoseVC = GlucoseView()
                glucoseVC.title = "Glukos"
                glucoseVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(glucoseVC, animated: true)

            case 4:
                // Poddar
                let pumpHistoryVC = PumpHistoryViewController()
                pumpHistoryVC.title = "Poddar"
                pumpHistoryVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(pumpHistoryVC, animated: true)

            case 5:
                // Sensorer
                let sensorHistoryVC = SensorHistoryViewController()
                sensorHistoryVC.title = "Sensorer"
                sensorHistoryVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(sensorHistoryVC, animated: true)

            default:
                break
            }

        case .trioSettings:
            switch indexPath.row {
            case 0:
                // Algoritminställningar & analys
                let isDark = UserDefaultsRepository.forceDarkMode.value || traitCollection.userInterfaceStyle == .dark
                let trioView = TrioPreferencesView()
                    .preferredColorScheme(isDark ? .dark : .light)
                    .environment(\.colorScheme, isDark ? .dark : .light)
                let hostingController = UIHostingController(rootView: trioView)
                hostingController.title = "Trio algoritm & analys"
                hostingController.overrideUserInterfaceStyle = isDark ? .dark : traitCollection.userInterfaceStyle
                hostingController.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(hostingController, animated: true)

            case 1:
                // Hälsodata & profilinställningar
                let isDark = UserDefaultsRepository.forceDarkMode.value || traitCollection.userInterfaceStyle == .dark
                let profileSchedulesView = ProfileSchedulesView(onDone: { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                })
                    .preferredColorScheme(isDark ? .dark : .light)
                    .environment(\.colorScheme, isDark ? .dark : .light)
                let hostingController = UIHostingController(rootView: profileSchedulesView)
                hostingController.title = "Profil"
                hostingController.overrideUserInterfaceStyle = isDark ? .dark : traitCollection.userInterfaceStyle
                hostingController.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(hostingController, animated: true)

            case 2:
                // Oref realtidsstatus
                let isDark = UserDefaultsRepository.forceDarkMode.value || traitCollection.userInterfaceStyle == .dark
                let trioOrefView = TrioOrefView()
                    .preferredColorScheme(isDark ? .dark : .light)
                    .environment(\.colorScheme, isDark ? .dark : .light)
                let hostingController = UIHostingController(rootView: trioOrefView)
                hostingController.overrideUserInterfaceStyle = isDark ? .dark : traitCollection.userInterfaceStyle
                hostingController.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(hostingController, animated: true)

            case 3:
                // Inställningslogg
                let settingsLogVC = TrioSettingsLogView()
                settingsLogVC.title = "Inställningslogg"
                settingsLogVC.hidesBottomBarWhenPushed = false
                settingsLogVC.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : traitCollection.userInterfaceStyle
                navigationController?.pushViewController(settingsLogVC, animated: true)

            case 4:
                // Batterilogg
                let batteryVC = BatteryLogViewController()
                batteryVC.title = "Batterilogg"
                batteryVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(batteryVC, animated: true)

            case 5:
                // Omstartslogg
                let restartsVC = TrioRestartsView()
                restartsVC.title = "Omstartslogg"
                restartsVC.hidesBottomBarWhenPushed = false
                navigationController?.pushViewController(restartsVC, animated: true)

            default:
                break
            }

        case .dataCapture:
            switch indexPath.row {
            case 0:
                // Units row has segmented control; no navigation.
                break
            case 1:
                // Nightscoutinställningar
                let controller = makeNightscoutSettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            case 2:
                // Dexcominställningar
                let controller = makeDexcomSettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            default:
                break
            }

        case .appSettings:
            let rowKind = appSettingsRows[indexPath.row]
            switch rowKind {
            case .alarms:
                if let alarmVC = ViewControllerManager.shared.alarmViewController {
                    navigationController?.pushViewController(alarmVC, animated: true)
                }
            case .general:
                let controller = GeneralSettingsViewController()
                controller.appStateController = appStateController
                navigationController?.pushViewController(controller, animated: true)
            case .graphs:
                let controller = GraphSettingsViewController()
                controller.appStateController = appStateController
                navigationController?.pushViewController(controller, animated: true)
            case .infoDisplay:
                let controller = makeInfoDisplaySettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            case .advanced:
                let controller = makeAdvancedSettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            }

        case .integrations:
            switch indexPath.row {
            case 0:
                // Bakgrundsaktivitet (modal)
                presentBackgroundRefreshSettings()
            case 1:
                // Sensorbyten synk (modal)
                presentSyncNewSensorView()
            case 2:
                // Fjärrkontrollinställningar
                let controller = makeRemoteSettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            case 3:
                // Kalendertrick
                let controller = WatchSettingsViewController()
                controller.appStateController = appStateController
                navigationController?.pushViewController(controller, animated: true)
            case 4:
                // Kontakttrick
                let controller = makeContactSettingsViewController()
                navigationController?.pushViewController(controller, animated: true)
            default:
                break
            }

        case .systemLog:
            if indexPath.row == 0 {
                // Se dagens logg
                let controller = makeLogViewController()
                navigationController?.pushViewController(controller, animated: true)
            } else {
                // Dela logg
                shareLogs()
            }

        case .appInfo:
            // Static info-only rows; no navigation.
            break
        }
    }

    @objc private func unitsSegmentChanged(_ sender: UISegmentedControl) {
        let value = sender.selectedSegmentIndex == 0 ? "mg/dL" : "mmol/L"
        UserDefaultsRepository.units.value = value
    }

    func isMacApp() -> Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    func presentInfoDisplaySettings() {
        let controller = makeInfoDisplaySettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeInfoDisplaySettingsViewController() -> UIViewController {
        let viewModel = InfoDisplaySettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = InfoDisplaySettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Informationsinställningar"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func presentRemoteSettings() {
        let controller = makeRemoteSettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeRemoteSettingsViewController() -> UIViewController {
        let viewModel = RemoteSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = RemoteSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Fjärrkontrollinställningar"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func presentContactSettings() {
        let controller = makeContactSettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeContactSettingsViewController() -> UIViewController {
        let viewModel = ContactSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let contactSettingsView = ContactSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: contactSettingsView)
        hostingController.title = "Kontakttrick"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func presentBackgroundRefreshSettings() {
        let controller = makeBackgroundRefreshSettingsViewController()
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(dismissPresentedController)
        )
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func makeBackgroundRefreshSettingsViewController() -> UIViewController {
        let viewModel = BackgroundRefreshSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = BackgroundRefreshSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Bakgrundsaktivitet"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }
    
    func presentSyncNewSensorView() {
        let controller = makeSyncNewSensorViewController()
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(dismissPresentedController)
        )
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    private func makeSyncNewSensorViewController() -> UIViewController {
        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = SyncNewSensorView()
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Synka heartbeat för ny sensor"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    @available(iOS 26.0, *)
    func presentLogView() {
        let controller = makeLogViewController()
        navigationController?.show(controller, sender: self)
    }

    @available(iOS 26.0, *)
    private func makeLogViewController() -> UIViewController {
        let viewModel = LogViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let logView = LogView(viewModel: viewModel, onDone: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: logView)
        hostingController.title = "Dagens logg"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func presentNightscoutSettingsView() {
        let controller = makeNightscoutSettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeNightscoutSettingsViewController() -> UIViewController {
        let viewModel = NightscoutSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = NightscoutSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Nightscoutinställningar"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func nightscoutSettingsDidFinish() {
        showHideNSDetails()
    }

    func presentDexcomSettingsView() {
        let controller = makeDexcomSettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeDexcomSettingsViewController() -> UIViewController {
        let viewModel = DexcomSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = DexcomSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Dexcominställningar"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    func presentAdvancedSettingsView() {
        let controller = makeAdvancedSettingsViewController()
        navigationController?.show(controller, sender: self)
    }

    private func makeAdvancedSettingsViewController() -> UIViewController {
        let viewModel = AdvancedSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = AdvancedSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Avancerade inställningar"
        hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.hidesBottomBarWhenPushed = false
        return hostingController
    }

    @objc private func dismissPresentedController() {
        presentedViewController?.dismiss(animated: true)
    }

    @objc private func popSettingsChildController() {
        navigationController?.popViewController(animated: true)
    }
    
    private func resolveMainViewController() -> MainViewController? {
        // 1) If we're embedded in a navigation stack, search upwards in that stack
        if let nav = navigationController,
           let found = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
            return found
        }

        // 2) Walk up the presenting chain
        var parentVC = presentingViewController
        while let current = parentVC {
            if let main = current as? MainViewController {
                return main
            }
            if let nav = current as? UINavigationController,
               let found = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                return found
            }
            parentVC = current.presentingViewController
        }

        // 3) As a final fallback, search all tabs and their navigation stacks
        if let tabBar = tabBarController {
            for vc in tabBar.viewControllers ?? [] {
                if let main = vc as? MainViewController {
                    return main
                }
                if let nav = vc as? UINavigationController,
                   let found = nav.viewControllers.first(where: { $0 is MainViewController }) as? MainViewController {
                    return found
                }
            }
        }

        return nil
    }

    func presentStatsView() {
        let mainVC = resolveMainViewController()

        if mainVC == nil {
            LogManager.shared.log(
                category: .general,
                message: "SettingsViewController - could not find MainViewController for AggregatedStatsViewModel, falling back to nil",
                isDebug: true
            )
        }

        let viewModel = AggregatedStatsViewModel(mainViewController: mainVC)
        let statsRootView = NavigationView {
            if #available(iOS 26.0, *) {
                AggregatedStatsView(viewModel: viewModel)
            } else {
                // Fallback on earlier versions
            }
        }

        let hostingController = UIHostingController(rootView: statsRootView)
        hostingController.modalPresentationStyle = .formSheet

        if UserDefaultsRepository.forceDarkMode.value {
            hostingController.overrideUserInterfaceStyle = .dark
        }

        present(hostingController, animated: true, completion: nil)
    }

    private func shareLogs() {
        let logFilesToShare = LogManager.shared.logFilesForTodayAndYesterday()

        if !logFilesToShare.isEmpty {
                     let activityViewController = UIActivityViewController(activityItems: logFilesToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = self.view
            present(activityViewController, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(title: "No Logs Available", message: "There are no logs to share.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true, completion: nil)
        }
    }
}
