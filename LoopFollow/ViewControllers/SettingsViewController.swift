//
//  SettingsViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/3/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//


import UIKit
import Eureka
import EventKit
import EventKitUI
import SwiftUI

@available(iOS 26.0, *)
class SettingsViewController: ThemedFormViewController, NightscoutSettingsViewModelDelegate {
    var tokenRow: TextRow?
    var appStateController: AppStateController?
    var statusLabelRow: LabelRow!

    func showHideNSDetails() {
        var isHidden = false
        var isEnabled = true
        if !IsNightscoutEnabled() {
            isHidden = true
            isEnabled = false
        }

        if let row1 = form.rowBy(tag: "informationDisplaySettings") as? ButtonRow {
            row1.hidden = .function(["hide"],  {form in
                return isHidden
            })
            row1.evaluateHidden()
        }

        if IsNightscoutEnabled() {
            isEnabled = true
        }

        guard let nightscoutTab = self.tabBarController?.tabBar.items![3] else { return }
        nightscoutTab.isEnabled = isEnabled
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }

        let buildDetails = BuildDetails.default
        let formattedBuildDate = dateTimeUtils.formattedDate(from: buildDetails.buildDate())
        let branchAndSha = buildDetails.branchAndSha
        let expiration = dateTimeUtils.formattedDate(from: buildDetails.calculateExpirationDate())
        let expirationHeaderString = buildDetails.expirationHeaderString
        let versionManager = AppVersionManager()
        let version = versionManager.version()
        let trioExpiration = ProfileManager.shared.trioExpirationFormatted ?? "Unknown"

        form
        +++ Section("Historik & statistik")
        <<< ButtonRow() { [weak self] row in
            row.title = "Aggregerad statistik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }

                    // Build AggregatedStatsViewModel using the MainViewController from the tab bar if available
                    let mainVC = self.resolveMainViewController()
                    let viewModel = AggregatedStatsViewModel(mainViewController: mainVC)

                    // SwiftUI root view
                    let rootView = AggregatedStatsView(viewModel: viewModel, showsDoneButton: false)

                    // Host in a UIKit controller that can be pushed on the navigation stack
                    let hostingController = UIHostingController(rootView: rootView)
                    hostingController.title = "Statistik"
                    hostingController.hidesBottomBarWhenPushed = false

                    // Respect forced dark mode if enabled
                    if UserDefaultsRepository.forceDarkMode.value {
                        hostingController.overrideUserInterfaceStyle = .dark
                    }

                    return hostingController
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Behandlingshistorik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let treatmentsVC = TreatmentsTableView()
                    treatmentsVC.title = "Behandlingar"
                    treatmentsVC.hidesBottomBarWhenPushed = false
                    return treatmentsVC
                }),
                onDismiss: nil
            )
        }
        /*
        <<< ButtonRow() { row in
            row.title = "Dextrohistorik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let lowTreatVC = LowTreatmentsView()
                    lowTreatVC.title = "Dextro"
                    lowTreatVC.hidesBottomBarWhenPushed = false
                    return lowTreatVC
                }),
                onDismiss: nil
            )
        }
         */
        
        <<< ButtonRow() { row in
            row.title = "Fingerstick och dextrohistorik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let bgCheckVC = BGCheckView()
                    bgCheckVC.title = "Fingerstick"
                    bgCheckVC.hidesBottomBarWhenPushed = false
                    return bgCheckVC
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Glukoshistorik & sensorfel"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let glucoseVC = GlucoseView()
                    glucoseVC.title = "Glukos"
                    glucoseVC.hidesBottomBarWhenPushed = false
                    return glucoseVC
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Poddhistorik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let pumpHistoryVC = PumpHistoryViewController()
                    pumpHistoryVC.title = "Poddar"
                    pumpHistoryVC.hidesBottomBarWhenPushed = false
                    return pumpHistoryVC
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Sensorhistorik"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let sensorHistoryVC = SensorHistoryViewController()
                    sensorHistoryVC.title = "Sensorer"
                    sensorHistoryVC.hidesBottomBarWhenPushed = false
                    return sensorHistoryVC
                }),
                onDismiss: nil
            )
        }
        
        +++ Section("\nTrio inställningar och status")
        <<< ButtonRow() {
            $0.title = "Trio algoritminställningar & analys"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let trioView = TrioPreferencesView()
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: trioView)
                    hostingController.title = "Trio algoritm & analys"

                    hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.hidesBottomBarWhenPushed = false

                    return hostingController
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Trio hälsodata & profilinställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let profileSchedulesView = ProfileSchedulesView(onDone: { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    })
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: profileSchedulesView)
                    hostingController.title = "Profil"

                    hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.hidesBottomBarWhenPushed = false

                    return hostingController
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Trio oref realtidsstatus"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let trioOrefView = TrioOrefView()
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: trioOrefView)

                    hostingController.overrideUserInterfaceStyle = isDark ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.hidesBottomBarWhenPushed = false

                    return hostingController
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Trio inställningslogg"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let settingsLogVC = TrioSettingsLogView()
                    settingsLogVC.title = "Trio inställningslogg"
                    settingsLogVC.hidesBottomBarWhenPushed = false
                    settingsLogVC.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
                    return settingsLogVC
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Trio batterilogg"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let batteryVC = BatteryLogViewController()
                    batteryVC.title = "Trio batterilogg"
                    batteryVC.hidesBottomBarWhenPushed = false
                    return batteryVC
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { row in
            row.title = "Trio omstartslogg"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let restartsVC = TrioRestartsView()
                    restartsVC.title = "Trio omstartslogg"
                    restartsVC.hidesBottomBarWhenPushed = false
                    return restartsVC
                }),
                onDismiss: nil
            )
        }
        
        +++ Section(header: "\nDatafångstinställningar", footer: "")
        <<< SegmentedRow<String>("units") { row in
            row.title = "Enhet"
            row.options = ["mg/dL", "mmol/L"]
            row.value = UserDefaultsRepository.units.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.units.value = value
        }
        <<< ButtonRow("nightscout") { [weak self] row in
            row.title = "Nightscoutinställningar"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeNightscoutSettingsViewController()
                }),
                onDismiss: nil
            )
        }
        <<< ButtonRow("dexcom") { [weak self] row in
            row.title = "Dexcominställningar"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeDexcomSettingsViewController()
                }),
                onDismiss: nil
            )
        }

        +++ Section("\nAppinställningar")
        
        <<< ButtonRow("alarmsSettings") {
            $0.title = "Alarm"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let alarmVC = ViewControllerManager.shared.alarmViewController else {
                        fatalError("AlarmViewController should be pre-instantiated and available")
                    }
                    return alarmVC
                }), onDismiss: nil)
        }
        
        <<< ButtonRow() {
            $0.title = "Allmänna inställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let controller = GeneralSettingsViewController()
                    controller.appStateController = self.appStateController
                    return controller
                }
                                             ), onDismiss: nil)
        }
        <<< ButtonRow("graphSettings") {
            $0.title = "Grafinställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let controller = GraphSettingsViewController()
                    controller.appStateController = self.appStateController
                    return controller
                }
                                             ), onDismiss: nil)
        }
        <<< ButtonRow("informationDisplaySettings") { [weak self] row in
            row.title = "Informationsinställningar"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeInfoDisplaySettingsViewController()
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() { [weak self] row in
            row.title = "Avancerade inställningar"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeAdvancedSettingsViewController()
                }),
                onDismiss: nil
            )
        }

        +++ Section("\nIntegrationer")
        
        <<< ButtonRow("backgroundRefreshSettings") { [weak self] row in
            row.title = "Bakgrundsaktivitet"
            row.presentationMode = .none
            row.cellUpdate { cell, _ in
                cell.textLabel?.textAlignment = .left
                cell.textLabel?.textColor = .label
                cell.accessoryType = .disclosureIndicator
            }
            row.onCellSelection { [weak self] _, _ in
                self?.presentBackgroundRefreshSettings()
            }
        }
        <<< ButtonRow("syncNewSensor") { [weak self] row in
            row.title = "Dexcom heartbeat synk"
            row.presentationMode = .none
            row.cellUpdate { cell, _ in
                cell.textLabel?.textAlignment = .left
                cell.textLabel?.textColor = .label
                cell.accessoryType = .disclosureIndicator
            }
            row.onCellSelection { [weak self] _, _ in
                self?.presentSyncNewSensorView()
            }
        }
        
        <<< ButtonRow("remoteSettings") { [weak self] row in
            row.title = "Fjärrkontrollinställningar"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeRemoteSettingsViewController()
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Kalendertrick"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    let controller = WatchSettingsViewController()
                    controller.appStateController = self.appStateController
                    return controller
                }
                                             ), onDismiss: nil)
        }
        <<< ButtonRow("contact") { [weak self] row in
            row.title = "Kontakttrick"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeContactSettingsViewController()
                }),
                onDismiss: nil
            )
        }
        
        +++ Section("\nSystemlogg")
        <<< ButtonRow("viewlog") { [weak self] row in
            row.title = "Se logg"
            row.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    guard let self = self else { return UIViewController() }
                    return self.makeLogViewController()
                }),
                onDismiss: nil
            )
        }
        <<< ButtonRow("shareLogs") {
            $0.title = "Dela logg"
            $0.cellSetup { cell, _ in
                cell.accessibilityIdentifier = "ShareLogsButton"
            }
            $0.cellUpdate { cell, _ in
                cell.textLabel?.textAlignment = .left
            }
            $0.onCellSelection { [weak self] _, _ in
                self?.shareLogs()
            }
        }

            +++ Section("\nAppinformation")
            <<< LabelRow() {
                $0.title = "Version"
                $0.value = version
                $0.tag = "currentVersionRow"
            }
            <<< LabelRow() {
                $0.title = "Senaste version"
                $0.value = "Fetching..."
                $0.tag = "latestVersionRow"
            }
            <<< LabelRow() {
                $0.title = expirationHeaderString
                $0.value = expiration
                $0.hidden = Condition(booleanLiteral: isMacApp())
            }
            <<< LabelRow() {
                $0.title = "Bygge"
                $0.value = formattedBuildDate
            }
            <<< LabelRow() {
                $0.title = "Branch"
                $0.value = branchAndSha
            }
            <<< LabelRow() {
                $0.title = "Trio löper ut"
                $0.value = trioExpiration
                $0.tag = "trioExpirationRow"
                $0.hidden = Condition(booleanLiteral: isMacApp())
            }

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
                if let currentVersionRow = self.form.rowBy(tag: "currentVersionRow") as? LabelRow {
                    currentVersionRow.cell.detailTextLabel?.textColor = self.getColor(isBlacklisted: isBlacklisted, isNewer: isNewer, isCurrent: latestVersion == versionManager.version())
                    currentVersionRow.updateCell()
                }

                if let latestVersionRow = self.form.rowBy(tag: "latestVersionRow") as? LabelRow {
                    latestVersionRow.value = latestVersion ?? "Unknown"
                    latestVersionRow.updateCell()
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
