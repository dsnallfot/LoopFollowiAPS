import UIKit
import Combine

/// Protocol used by external callers (SnoozeViewController, SAge, Alarms, intents, etc.)
/// to trigger a UI refresh of alarm-related state (snooze/mute) without knowing about
/// the underlying implementation (Eureka vs ModernAlarmViewController).
protocol AlarmUIRefreshing: AnyObject {
    // Legacy API utan value-parameter (många call sites använder denna)
    func reloadSnoozeTime(key: String, setNil: Bool)
    func reloadMuteTime(key: String, setNil: Bool)

    // API där ett specifikt datum skickas med (SnoozeViewController, intents m.m.)
    func reloadSnoozeTime(key: String, setNil: Bool, value: Date)
    func reloadMuteTime(key: String, setNil: Bool, value: Date)

    func reloadIsSnoozed(key: String, value: Bool)
    func reloadIsMuted(key: String, value: Bool)
}

class ModernAlarmViewController: ThemedViewController, UITableViewDelegate {
    
    // UI
    private var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<AlarmSection, AlarmRow>!
    
    // Logic
    private let viewModel = AlarmViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    // Knapp för att visa en snabböversikt över aktiva larm
    private lazy var activeAlarmsButton: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "switch.2"),
            style: .plain,
            target: self,
            action: #selector(activeAlarmsButtonTapped)
        )
        return item
    }()

    // Top Filter Bar (Istället för segments i celler, snyggare i header)
    private lazy var categorySegmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Hög/Låg", "Trend", "Trio", "Teknik", "Övrigt"])
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
        return sc
    }()
    
    private lazy var subCategorySegmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: viewModel.alertBGOptions) // Initialt BG
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(subCategoryChanged), for: .valueChanged)
        return sc
    }()

    @objc private func categoryChanged() {
        viewModel.selectedCategoryIndex = categorySegmentedControl.selectedSegmentIndex
        viewModel.selectedSubCategoryIndex = 0 // Reset till första valet i nya listan
        
        // Uppdatera titlarna i den andra segment-kontrollen
        subCategorySegmentedControl.removeAllSegments()
        let newOptions: [String]
        switch viewModel.selectedCategoryIndex {
        case 0: newOptions = viewModel.alertBGOptions
        case 1: newOptions = viewModel.alertExtraBGOptions
        case 2: newOptions = viewModel.alertSystemOptions
        case 3: newOptions = viewModel.alertHardwareOptions
        case 4: newOptions = viewModel.alertOtherOptions
        default: newOptions = []
        }
        
        for (index, title) in newOptions.enumerated() {
            subCategorySegmentedControl.insertSegment(withTitle: title, at: index, animated: false)
        }
        subCategorySegmentedControl.selectedSegmentIndex = 0
        
        viewModel.updateSnapshotData()
        applySnapshot()
    }

    @objc private func subCategoryChanged() {
        viewModel.selectedSubCategoryIndex = subCategorySegmentedControl.selectedSegmentIndex
        viewModel.updateSnapshotData()
        applySnapshot()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Alarm"
        //view.backgroundColor = .systemGroupedBackground
        updateBackgroundForCurrentMode()
        
        setupTableView()
        configureDataSource()
        
        // Lyssna på ändringar i ViewModel
        viewModel.$selectedCategoryIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySnapshot()
            }
            .store(in: &cancellables)
            
        // Initial load
        viewModel.updateSnapshotData()
        applySnapshot()
        configureDoneButtonIfNeeded()
    }

    // MARK: - Modal Done Button
    /// Konfigurerar alltid switch.2-knappen och lägger till "Klar" när vyn är presenterad modalt.
    private func configureDoneButtonIfNeeded() {
        // Om denna VC är root i en navigation controller och är presenterad modalt
        // ska vi visa både switch.2-knappen och en Klar-knapp.
        if navigationController?.viewControllers.first === self,
           presentingViewController != nil {
            let doneItem = UIBarButtonItem(
                title: "Klar",
                style: .done,
                target: self,
                action: #selector(doneButtonTapped)
            )
            // switch.2 till vänster om Klar
            navigationItem.rightBarButtonItems = [doneItem, activeAlarmsButton]
        } else {
            // I icke-modalt läge visar vi bara switch.2-knappen
            navigationItem.rightBarButtonItems = [activeAlarmsButton]
        }
    }

    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func activeAlarmsButtonTapped() {
        let activeVC = ActiveAlarmsViewController()
        activeVC.onDismiss = { [weak self] in
            guard let self = self else { return }
            // Rebuild snapshot based on any changes done in ActiveAlarmsViewController
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
        let nav = UINavigationController(rootViewController: activeVC)
        nav.modalPresentationStyle = .automatic
        present(nav, animated: true, completion: nil)
    }
    
    private func setupTableView() {
        // 1. Skapa TableView med rätt stil
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.delegate = self
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        
        // 2. Registrera celler
        tableView.register(SettingSwitchCell.self, forCellReuseIdentifier: SettingSwitchCell.reuseIdentifier)
        tableView.register(SettingStepperCell.self, forCellReuseIdentifier: SettingStepperCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DefaultCell")
        
        view.addSubview(tableView)
        
        // 3. Konfigurera Header Container
        // Vi sätter en temporär höjd, layoutIfNeeded kommer fixa resten
        let headerContainer = UIView(frame: CGRect(x: 0, y: 0, width: view.frame.width, height: 92))
        
        let stack = UIStackView(arrangedSubviews: [categorySegmentedControl, subCategorySegmentedControl])
        stack.axis = .vertical
        stack.spacing = 12 // Lite mer luft mellan segmenten ser modernare ut
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        headerContainer.addSubview(stack)
        
        // 4. Constraints för StackView inuti containern
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -26)
        ])
        
        // 5. Viktigt: Tvinga containern att beräkna sin höjd baserat på stackviewns innehåll
        headerContainer.setNeedsLayout()
        headerContainer.layoutIfNeeded()
        
        // Beräkna den exakta storleken som behövs
        let targetSize = CGSize(width: view.frame.width, height: UIView.layoutFittingCompressedSize.height)
        let size = headerContainer.systemLayoutSizeFitting(targetSize)
        headerContainer.frame.size.height = size.height
        
        // Sätt containern som header
        tableView.tableHeaderView = headerContainer
    }
    
    // MARK: - Diffable Data Source
    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] (tableView, indexPath, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            
            switch row {
            case .toggle(let title, let isOn, let id):
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingSwitchCell.reuseIdentifier, for: indexPath) as! SettingSwitchCell
                cell.configure(title: title, isOn: isOn) { [weak self] newValue in
                    guard let self = self else { return }
                    self.viewModel.updateActiveToggle(id: id, value: newValue)
                    // ViewModel har nu uppdaterat sina sektioner, bara applicera snapshot
                    self.applySnapshot()
                }
                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
                cell.backgroundConfiguration = background
                
                return cell
                
            case .valueStepper(let title, let value, let min, let max, let step, let unit, let id):
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingStepperCell.reuseIdentifier, for: indexPath) as! SettingStepperCell
                cell.configure(title: title, value: value, min: min, max: max, step: step, unit: unit) { [weak self] newValue in
                    self?.viewModel.updateAlarmValue(id: id, value: newValue)
                }
                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
                cell.backgroundConfiguration = background
                
                return cell
                
            case .soundPicker(let title, let currentSound, _):
                let cell = tableView.dequeueReusableCell(withIdentifier: "DefaultCell", for: indexPath)

                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
                cell.backgroundConfiguration = background

                cell.textLabel?.text = title
                cell.accessoryType = .disclosureIndicator

                // Skapa en modern detail label
                let detailLabel = UILabel()
                detailLabel.text = currentSound.replacingOccurrences(of: "_", with: " ")
                detailLabel.textColor = .secondaryLabel
                detailLabel.sizeToFit()
                cell.accessoryView = detailLabel
                return cell
                
            case .optionPicker(let title, let currentOption, _, _):
                let cell = tableView.dequeueReusableCell(withIdentifier: "DefaultCell", for: indexPath)

                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
                cell.backgroundConfiguration = background

                cell.textLabel?.text = title
                cell.detailTextLabel?.text = currentOption
                cell.accessoryType = .disclosureIndicator

                let detailLabel = UILabel()
                detailLabel.text = currentOption
                detailLabel.textColor = .secondaryLabel
                detailLabel.sizeToFit()
                cell.accessoryView = detailLabel
                return cell
                
            case .dateValue(let title, let date, let id):
                let cell = tableView.dequeueReusableCell(withIdentifier: "DefaultCell", for: indexPath)

                var background = UIBackgroundConfiguration.listGroupedCell()
                background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
                cell.backgroundConfiguration = background

                cell.textLabel?.text = title

                let detailLabel = UILabel()
                detailLabel.textColor = .secondaryLabel

                if let date = date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    detailLabel.text = formatter.string(from: date)
                } else {
                    // Dynamisk text baserat på ID
                    if id.contains("Snooze") || id.contains("snoozed") {
                        detailLabel.text = "Ej snoozad"
                    } else if id.contains("Mute") {
                        detailLabel.text = "Ej tystad"
                    } else {
                        detailLabel.text = "Ej inställd"
                    }
                }

                detailLabel.sizeToFit()
                cell.accessoryView = detailLabel
                return cell
                
            default:
                return UITableViewCell()
            }
        }
    }
    
    private func applySnapshot(animatingDifferences: Bool = true) {
        guard isViewLoaded, dataSource != nil else { return }
        var snapshot = NSDiffableDataSourceSnapshot<AlarmSection, AlarmRow>()
        snapshot.appendSections(viewModel.sections)
        
        for section in viewModel.sections {
            snapshot.appendItems(viewModel.rows(for: section), toSection: section)
        }
        
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }
    
    // MARK: - TableView Delegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        
        switch row {
        case .dateValue(let title, let currentDate, let id):
            showDateSheet(title: title, currentDate: currentDate, id: id)
            
        case .soundPicker(_, let current, let id):
            showSoundPicker(currentSound: current, id: id)
            
        case .optionPicker(let title, let current, let options, let id):
            showOptionPicker(title: title, current: current, options: options, id: id)
            
        default: break
        }
    }

    // Denna funktion skapar en snygg pop-up med en DatePicker
    private func showDateSheet(title: String, currentDate: Date?, id: String) {
        let vc = UIViewController()
        vc.preferredContentSize = CGSize(width: view.frame.width, height: 260)
        
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.date = currentDate ?? Date()
        datePicker.minuteInterval = 5
        datePicker.locale = Locale(identifier: "sv_SE")
        
        if id.contains("quietHour") {
            datePicker.datePickerMode = .time // Visa bara klockslag för nattinställningar
        } else {
            datePicker.datePickerMode = .dateAndTime // Visa både och för snooze
        }
        
        vc.view.addSubview(datePicker)
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: vc.view.topAnchor),
            datePicker.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            datePicker.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            datePicker.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])
        
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.setValue(vc, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Spara", style: .default) { _ in
            // För nattinställningar vill vi bara spara tiden
            // För snooze/mute vill vi även aktivera togglen (sköts i ViewModel.updateDate)
            self.viewModel.updateDate(id: id, date: datePicker.date)
            self.applySnapshot()
        })
        
        alert.addAction(UIAlertAction(title: "Rensa", style: .destructive) { _ in
            switch id {
            case "low_snoozed_time":
                UserDefaultsRepository.alertLowSnoozedTime.setNil(key: "alertLowSnoozedTime")
                UserDefaultsRepository.alertLowIsSnoozed.value = false
                
            case "alertSnoozeAllTime":
                UserDefaultsRepository.alertSnoozeAllTime.setNil(key: "alertSnoozeAllTime")
                UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = false
                
            case "alertMuteAllTime":
                UserDefaultsRepository.alertMuteAllTime.setNil(key: "alertMuteAllTime")
                UserDefaultsRepository.alertMuteAllIsMuted.value = false
                
            case "quietHourStart", "quietHourEnd":
                break
            default:
                break
            }
            
            self.viewModel.updateSnapshotData()
            self.applySnapshot()
        })
        
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
            
            present(alert, animated: true)
    }
    
    // MARK: - Section Headers & Footers

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let snapshot = dataSource.snapshot()
        guard section >= 0 && section < snapshot.sectionIdentifiers.count else {
            return nil
        }
        let sectionType = snapshot.sectionIdentifiers[section]
        switch sectionType {
        case .globalSettings:
            return "Snooza eller tysta alla larm"
        case .specificAlarm(let name):
            return "Alarminställningar för \(name)"
        case .nightSettings:
            return "Allmänna alarminställningar"
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // Reuse the existing logic to determine the title
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }

        let label = UILabel()
        label.text = title
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel

        let container = UIView()
        container.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        return container
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let snapshot = dataSource.snapshot()
        guard section >= 0 && section < snapshot.sectionIdentifiers.count else {
            return nil
        }
        let sectionType = snapshot.sectionIdentifiers[section]
        if case .specificAlarm(let name) = sectionType, name == "Låg" {
            return "Alerts when BG drops below value. Persistent for minutes will allow the alert to be ignored..."
        }
        return nil
    }
    
    // MARK: - Navigation Helpers
    
    func showSoundPicker(currentSound: String, id: String) {
        let soundVC = SoundSelectionViewController()
        soundVC.selectedSound = currentSound
        soundVC.onSelection = { [weak self] newSound in
            self?.viewModel.updateAlarmStringOption(id: id, value: newSound)
            self?.applySnapshot(animatingDifferences: false)
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(soundVC, animated: true)
    }
    
    func showOptionPicker(title: String, current: String, options: [String], id: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for option in options {
            let action = UIAlertAction(title: option, style: .default) { [weak self] _ in
                self?.viewModel.updateAlarmStringOption(id: id, value: option)
                self?.applySnapshot(animatingDifferences: false)
            }
            // Markera vald?
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        present(alert, animated: true)
    }
    
    func showDatePicker(title: String) {
        // Enkel implementation: ActionSheet med DatePicker inuti, eller en Custom VC
        // För "proffsig" look, pusha in en vy som heter "Snooze Settings"
    }
}

// MARK: - Legacy AlarmUIRefreshing API
// Dessa metoder anropas från andra delar av appen (SnoozeViewController, SAge, Alarms,
// SnoozeMuteIntentHelper, SnoozeStatusView) via ViewControllerManager.shared.alarmViewController.
// I den gamla Eureka-baserade AlarmViewController uppdaterades specifika rader via taggar;
// i ModernAlarmViewController bygger vi istället om snapshoten baserat på UserDefaults.
extension ModernAlarmViewController: AlarmUIRefreshing {

    // 2-param variant: används där datumet inte bryr sig, bara UI-refresh
    func reloadSnoozeTime(key: String, setNil: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }

    // 3-param variant: används där ett explicit datum skickas med
    func reloadSnoozeTime(key: String, setNil: Bool, value: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }

    func reloadIsSnoozed(key: String, value: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }

    func reloadMuteTime(key: String, setNil: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }

    func reloadMuteTime(key: String, setNil: Bool, value: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }

    func reloadIsMuted(key: String, value: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.isViewLoaded,
                  self.dataSource != nil else { return }
            self.viewModel.updateSnapshotData()
            self.applySnapshot(animatingDifferences: false)
        }
    }
}
