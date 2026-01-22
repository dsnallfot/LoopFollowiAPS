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
        <<< ButtonRow() {
            $0.title = "Aggregerad statistik"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentStatsView()
                    return UIViewController()
                }), onDismiss: nil)
        }
        
        <<< ButtonRow() {
            $0.title = "Behandlingslogg"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    // Instantiate the TreatmentsTableView.
                    let treatmentsVC = TreatmentsTableView()
                    // For a table view controller, you might choose to embed it in a UINavigationController.
                    return UINavigationController(rootViewController: treatmentsVC)
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
                $0.title = "Dextrologg"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let lowTreatVC = LowTreatmentsView()
                        return UINavigationController(rootViewController: lowTreatVC)
                    }),
                    onDismiss: nil
                )
            }
        
        <<< ButtonRow() {
                $0.title = "Fingersticklogg"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let bgCheckVC = BGCheckView()
                        return UINavigationController(rootViewController: bgCheckVC)
                    }),
                    onDismiss: nil
                )
            }
        
        <<< ButtonRow() {
                $0.title = "Glukoslogg & sensorfel"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let glucoseVC = GlucoseView()
                        return UINavigationController(rootViewController: glucoseVC)
                    }),
                    onDismiss: nil
                )
            }
        
        <<< ButtonRow() {
                $0.title = "Poddhistorik"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let pumpHistoryVC = PumpHistoryViewController()
                        return UINavigationController(rootViewController: pumpHistoryVC)
                    }),
                    onDismiss: nil
                )
            }
        
        <<< ButtonRow() {
                $0.title = "Sensorhistorik"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let sensorHistoryVC = SensorHistoryViewController()
                        return UINavigationController(rootViewController: sensorHistoryVC)
                    }),
                    onDismiss: nil
                )
            }
        
        +++ Section("\nTrio inställningar och status")
        <<< ButtonRow() {
            $0.title = "Trio användare & profilinställningar"
            $0.presentationMode = .presentModally(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let profileSchedulesView = ProfileSchedulesView(onDone: { [weak self] in
                        self?.dismissPresentedController()
                    })
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: profileSchedulesView)
                    hostingController.title = "Trio profil"

                    // Transparent hosting background
                    hostingController.view.backgroundColor = .clear
                    hostingController.view.isOpaque = false
                    hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

                    let nav = UINavigationController(rootViewController: hostingController)
                    nav.modalPresentationStyle = .formSheet

                    // Transparent modal container
                    nav.view.backgroundColor = .clear
                    nav.view.isOpaque = false
                    nav.view.layer.backgroundColor = UIColor.clear.cgColor

                    // Transparent navigation bar
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    nav.navigationBar.standardAppearance = appearance
                    nav.navigationBar.scrollEdgeAppearance = appearance
                    nav.navigationBar.compactAppearance = appearance

                    // Match current interface style
                    nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

                    return nav
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Trio användarinställningar & analys"
            $0.presentationMode = .presentModally(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let trioView = TrioPreferencesView()
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: trioView)
                    hostingController.title = "Trio användarinställningar"

                    hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
                        title: "Klar",
                        style: .plain,
                        target: self,
                        action: #selector(self.dismissPresentedController)
                    )

                    // Transparent hosting background
                    hostingController.view.backgroundColor = .clear
                    hostingController.view.isOpaque = false
                    hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

                    let nav = UINavigationController(rootViewController: hostingController)
                    nav.modalPresentationStyle = .formSheet

                    // Transparent modal container
                    nav.view.backgroundColor = .clear
                    nav.view.isOpaque = false
                    nav.view.layer.backgroundColor = UIColor.clear.cgColor

                    // Transparent navigation bar
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    nav.navigationBar.standardAppearance = appearance
                    nav.navigationBar.scrollEdgeAppearance = appearance
                    nav.navigationBar.compactAppearance = appearance

                    // Match current interface style
                    nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

                    return nav
                }),
                onDismiss: nil
            )
        }
        
        
        <<< ButtonRow() {
            $0.title = "Trio oref status"
            $0.presentationMode = .presentModally(
                controllerProvider: .callback(builder: {
                    let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
                    let trioOrefView = TrioOrefView()
                        .preferredColorScheme(isDark ? .dark : .light)
                        .environment(\.colorScheme, isDark ? .dark : .light)

                    let hostingController = UIHostingController(rootView: trioOrefView)

                    hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
                        title: "Klar",
                        style: .plain,
                        target: self,
                        action: #selector(self.dismissPresentedController)
                    )

                    // Transparent hosting background
                    hostingController.view.backgroundColor = .clear
                    hostingController.view.isOpaque = false
                    hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

                    let nav = UINavigationController(rootViewController: hostingController)
                    nav.modalPresentationStyle = .formSheet

                    // Transparent modal container
                    nav.view.backgroundColor = .clear
                    nav.view.isOpaque = false
                    nav.view.layer.backgroundColor = UIColor.clear.cgColor

                    // Transparent navigation bar
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    nav.navigationBar.standardAppearance = appearance
                    nav.navigationBar.scrollEdgeAppearance = appearance
                    nav.navigationBar.compactAppearance = appearance

                    // Match current interface style
                    nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
                    hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

                    return nav
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
            $0.title = "Trio inställningslogg"
            $0.presentationMode = .presentModally(
                controllerProvider: .callback(builder: {
                    let settingsLogVC = TrioSettingsLogView()

                    let nav = UINavigationController(rootViewController: settingsLogVC)
                    nav.modalPresentationStyle = .formSheet

                    // Transparent modal container
                    nav.view.backgroundColor = .clear
                    nav.view.isOpaque = false
                    nav.view.layer.backgroundColor = UIColor.clear.cgColor

                    // Transparent navigation bar
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    nav.navigationBar.standardAppearance = appearance
                    nav.navigationBar.scrollEdgeAppearance = appearance
                    nav.navigationBar.compactAppearance = appearance

                    // Match current interface style
                    nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
                    settingsLogVC.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

                    return nav
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow() {
                $0.title = "Trio batterilogg"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let batteryVC = BatteryLogViewController()
                        return UINavigationController(rootViewController: batteryVC)
                    }),
                    onDismiss: nil
                )
            }
        
        <<< ButtonRow() {
                $0.title = "Trio omstartslogg"
                $0.presentationMode = .show(
                    controllerProvider: .callback(builder: {
                        let restartsVC = TrioRestartsView()
                        return UINavigationController(rootViewController: restartsVC)
                    }),
                    onDismiss: nil
                )
            }
        
        +++ Section(header: "\nDatafångst inställningar", footer: "")
        <<< SegmentedRow<String>("units") { row in
            row.title = "Enhet"
            row.options = ["mg/dL", "mmol/L"]
            row.value = UserDefaultsRepository.units.value
        }.onChange { row in
            guard let value = row.value else { return }
            UserDefaultsRepository.units.value = value
        }
        <<< ButtonRow("nightscout") {
            $0.title = "Nightscoutinställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentNightscoutSettingsView()
                    return UIViewController()
                }), onDismiss: nil
            )
        }
        <<< ButtonRow("dexcom") {
            $0.title = "Dexcominställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentDexcomSettingsView()
                    return UIViewController()
                }), onDismiss: nil
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
        <<< ButtonRow("informationDisplaySettings") {
            $0.title = "Informationinställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentInfoDisplaySettings()
                    return UIViewController()
                }
                                             ), onDismiss: nil)
        }
        
        <<< ButtonRow() {
            $0.title = "Avancerade inställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentAdvancedSettingsView()
                    return UIViewController()
                }), onDismiss: nil)
            
        }

        +++ Section("\nIntegrationer")
        
        <<< ButtonRow("backgroundRefreshSettings") {
            $0.title = "Bakgrundsaktivitet"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentBackgroundRefreshSettings()
                    return UIViewController()
                }),
                onDismiss: nil
            )
        }
        <<< ButtonRow("syncNewSensor") {
            $0.title = "Dexcom heartbeat synk"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentSyncNewSensorView()
                    return UIViewController()
                }),
                onDismiss: nil
            )
        }
        
        <<< ButtonRow("remoteSettings") {
            $0.title = "Fjärrkontrollinställningar"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentRemoteSettings()
                    return UIViewController()
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
        <<< ButtonRow("contact") {
            $0.title = "Kontakttrick"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentContactSettings()
                    return UIViewController()
                }
                                             ), onDismiss: nil)
        }
        
        +++ Section("\nSystemlogg")
        <<< ButtonRow("viewlog") {
            $0.title = "Se logg"
            $0.presentationMode = .show(
                controllerProvider: .callback(builder: {
                    self.presentLogView()
                    return UIViewController()
                }), onDismiss: nil)
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
        let viewModel = InfoDisplaySettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = InfoDisplaySettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Informationinställningar"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    func presentRemoteSettings() {
        let viewModel = RemoteSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = RemoteSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Fjärrkontrollinställningar"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    func presentContactSettings() {
        let viewModel = ContactSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let contactSettingsView = ContactSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: contactSettingsView)
        hostingController.title = "Kontakttrick"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    func presentBackgroundRefreshSettings() {
        let viewModel = BackgroundRefreshSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = BackgroundRefreshSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Bakgrundsaktivitet"

        // Provide the close button via UIKit navigation bar
        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        // Match current interface style
        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true, completion: nil)
    }
    
    func presentSyncNewSensorView() {
        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = SyncNewSensorView()
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Synka heartbeat för ny sensor"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        // Match current interface style
        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    @available(iOS 26.0, *)
    func presentLogView() {
        let viewModel = LogViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let logView = LogView(viewModel: viewModel, onDone: { [weak self] in
            self?.dismissPresentedController()
        })
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: logView)
        hostingController.title = "Dagens logg"

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    func presentNightscoutSettingsView() {
        let viewModel = NightscoutSettingsViewModel()
        //viewModel.delegate = self

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = NightscoutSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Nightscoutinställningar"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    func nightscoutSettingsDidFinish() {
        showHideNSDetails()
    }

    func presentDexcomSettingsView() {
        let viewModel = DexcomSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let settingsView = DexcomSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Dexcominställningar"

        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        // Match current interface style
        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }
    
    func presentAdvancedSettingsView() {
        let viewModel = AdvancedSettingsViewModel()

        let isDark = UserDefaultsRepository.forceDarkMode.value || self.traitCollection.userInterfaceStyle == .dark
        let view = AdvancedSettingsView(viewModel: viewModel)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = "Avancerade inställningar"

        // Provide the close button via UIKit navigation bar (avoids double titles)
        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedController)
        )

        // Transparent hosting background
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.layer.backgroundColor = UIColor.clear.cgColor

        let nav = UINavigationController(rootViewController: hostingController)
        nav.modalPresentationStyle = .formSheet

        // Transparent modal container
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        nav.view.layer.backgroundColor = UIColor.clear.cgColor

        // Transparent navigation bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance

        // Match current interface style
        nav.overrideUserInterfaceStyle = UserDefaultsRepository.forceDarkMode.value ? .dark : self.traitCollection.userInterfaceStyle
        hostingController.overrideUserInterfaceStyle = nav.overrideUserInterfaceStyle

        present(nav, animated: true)
    }

    @objc private func dismissPresentedController() {
        presentedViewController?.dismiss(animated: true)
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
