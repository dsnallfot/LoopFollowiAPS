//
//  RemoteSettingsViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2024-03-22.

//

import UIKit
import EventKit
import EventKitUI


class RemoteSettingsViewController: ThemedViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    weak var delegate: RemoteSettingsDelegate?
    var appStateController: AppStateController?
    var mealViewController: MealViewController?

    private enum Section: Int, CaseIterable {
        case method
        case twilio
        case shortcutsExamples
        case remoteConfig
        case presets
        case advanced
        case guardrails
    }

    private enum ShortcutsExampleRow {
        case remoteMealBolus
        case remoteMeal
        case remoteBolus
        case remoteOverride
        case remoteTempTarget
        case remoteCustomAction
    }

    private enum PresetRow {
        case overrides
        case tempTargets
        case customActions
    }

    private enum AdvancedRow {
        case showCustomActions
        case showRemoteBolus
        case showBolusCalc
        case useDynCr
    }

    private enum GuardrailRow: Int {
        case maxCarbs
        case maxFatProtein
        case maxBolus
    }

    // MARK: - Visible Sections Helper
    private var visibleSections: [Section] {
        var sections: [Section] = [.method]
        // Only show the shortcuts examples section for iOS Shortcuts
        if selectedMethod == "iOS Genvägar" {
            sections.append(.shortcutsExamples)
        }
        // Only show the Twilio section for SMS API
        if selectedMethod == "SMS API" {
            sections.append(.twilio)
        }
        sections.append(contentsOf: [.remoteConfig, .presets, .advanced, .guardrails])
        return sections
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    private enum CellID {
        static let basic = "BasicCell"
        static let subtitle = "SubtitleCell"
        static let method = "MethodCell"
        static let textField = "TextFieldCell"
        static let guardrail = "GuardrailCell"
    }
    
    private let cardBackgroundColor =
        UIColor.gray.withAlphaComponent(0.15)

    // Local state for segmented control (method)
    private var selectedMethod: String = UserDefaultsRepository.method.value

    override func viewDidLoad() {
        super.viewDidLoad()

        // Dark mode override if needed
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
        updateBackgroundForCurrentMode()

        title = "Fjärrkommandon inställningar"
        configureNavigationItems()
        configureTableView()
    }

    // This will catch both the "Klar" button dismissal and swipe-down dismissals.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            delegate?.remoteSettingsDidUpdateMethod()
        }
    }

    // MARK: - Setup

    private func configureNavigationItems() {
        let doneItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.rightBarButtonItem = doneItem
    }

    @objc private func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag

        // Registrera celltyper
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: CellID.basic)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: CellID.method)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: CellID.textField)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: CellID.guardrail)
        // SubtitleCell skapar vi med rätt style i cellForRow (ingen registrering behövs)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Helpers for dynamic rows

    private var hideRemoteBolus: Bool {
        return UserDefaultsRepository.hideRemoteBolus.value
    }

    private var hideRemoteCustomActions: Bool {
        return UserDefaultsRepository.hideRemoteCustomActions.value
    }

    private var shortcutsExampleRows: [ShortcutsExampleRow] {
        var rows: [ShortcutsExampleRow] = []

        // Remote meal/bolus examples depend on hideRemoteBolus
        if hideRemoteBolus {
            rows.append(.remoteMeal)
        } else {
            rows.append(.remoteMealBolus)
            rows.append(.remoteBolus)
        }

        rows.append(.remoteOverride)
        rows.append(.remoteTempTarget)

        if !hideRemoteCustomActions {
            rows.append(.remoteCustomAction)
        }

        return rows
    }

    private var presetRows: [PresetRow] {
        var rows: [PresetRow] = [.overrides, .tempTargets]
        if !hideRemoteCustomActions {
            rows.append(.customActions)
        }
        return rows
    }

    private var advancedRows: [AdvancedRow] {
        var rows: [AdvancedRow] = [.showCustomActions, .showRemoteBolus]
        // Show "Show Bolus Calculations" only when Remote Bolus is visible
        if !hideRemoteBolus {
            rows.append(.showBolusCalc)
        }
        rows.append(.useDynCr)
        return rows
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection sectionIndex: Int) -> Int {
        let section = visibleSections[sectionIndex]
        switch section {
        case .method:
            return 1
        case .shortcutsExamples:
            return shortcutsExampleRows.count
        case .twilio:
            return 4
        case .remoteConfig:
            return 2
        case .presets:
            return presetRows.count
        case .advanced:
            return advancedRows.count
        case .guardrails:
            return 3
        }
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection sectionIndex: Int) -> String? {
        let section = visibleSections[sectionIndex]
        switch section {
        case .method:
            return "Välj metod för fjärrkommandon"
        case .shortcutsExamples:
            return "iOS Genvägsnamn • Exempelsträngar"
        case .twilio:
            return "Twilio Settings"
        case .remoteConfig:
            return "Fjärrkommandon avsändare"
        case .presets:
            return "Fjärrkommandon förval"
        case .advanced:
            return "Avancerat (Omstart app krävs)"
        case .guardrails:
            return "Maxgränser och säkerhet"
        }
    }

    func tableView(_ tableView: UITableView,
                   titleForFooterInSection sectionIndex: Int) -> String? {
        let section = visibleSections[sectionIndex]
        switch section {
        case .method:
            return nil
        case .shortcutsExamples:
            return "När iOS genvägar är vald som metod för fjärrkommandon, kommer alla registreringar om skapas att vidarebefordras som en textsträng när du klickar på 'Skicka måltid/Bolus/Override/Tillfälligt mål'-knapparna. Kommandot '\\n' i textsträngarna skapar radbrytningar för bättre läsbarhet i iMessage. (Textsträngarna kan användas som input i dina genvägar).\n\nDu måste skapa och anpassa dina egna iOS genvägar och använda de fördefinierade namnen listande ovan."
        case .twilio:
            return nil
        case .remoteConfig:
            return "Fjärranvändarens namn kommer att visas i alla fjärrkommando-meddelanden som skickas till den mottagande telefonen.\n\nDen hemliga koden (max 10 tecken) ska vara unik, och exakt samma kod behöver anges i importfrågan som ställs vid installationen av den förkonfigurerade genvägen som används för att kunna utföra fjärrkommandon på den mottagande telefonen."
        case .presets:
            return "Lägg till de förvalda actions som du villl kunna välja mellan i resp vys picker. Separera dem med komma + blanksteg. Exempel: Override 1, Override 2, Override 3"
        case .advanced:
            return nil
        case .guardrails:
            return nil
        }
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = visibleSections[indexPath.section]
        switch section {
        case .method:
            return configureMethodCell(tableView, indexPath: indexPath)
        case .shortcutsExamples:
            return configureShortcutsExampleCell(tableView, indexPath: indexPath)
        case .twilio:
            return configureTwilioCell(tableView, indexPath: indexPath)
        case .remoteConfig:
            return configureRemoteConfigCell(tableView, indexPath: indexPath)
        case .presets:
            return configurePresetCell(tableView, indexPath: indexPath)
        case .advanced:
            return configureAdvancedCell(tableView, indexPath: indexPath)
        case .guardrails:
            return configureGuardrailCell(tableView, indexPath: indexPath)
        }
    }

    // MARK: - Cell Configuration

    private func configureMethodCell(_ tableView: UITableView,
                                     indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellID.method, for: indexPath)
        cell.selectionStyle = .none
        cell.backgroundColor = .clear

        // Rensa bara egna subviews (den här cellen används *bara* för segmented)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let segmented = UISegmentedControl(items: ["iOS Genvägar", "SMS API"])
        segmented.selectedSegmentIndex = (selectedMethod == "SMS API") ? 1 : 0
        segmented.addTarget(self, action: #selector(methodChanged(_:)), for: .valueChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(segmented)

        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            segmented.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            segmented.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor)
        ])

        return cell
    }

    @objc private func methodChanged(_ sender: UISegmentedControl) {
        let newValue = (sender.selectedSegmentIndex == 1) ? "SMS API" : "iOS Genvägar"
        selectedMethod = newValue
        UserDefaultsRepository.method.value = newValue
        tableView.reloadData()
    }

    private func makeTextFieldCell(_ tableView: UITableView,
                                   indexPath: IndexPath,
                                   title: String,
                                   placeholder: String?,
                                   text: String?,
                                   keyboardType: UIKeyboardType = .default,
                                   tag: Int) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellID.textField, for: indexPath)
        cell.selectionStyle = .none
        cell.backgroundColor = cardBackgroundColor

        // Den här celltypen är bara vår egen, så vi kan rensa alla subviews tryggt
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let textField = UITextField()
        textField.placeholder = placeholder
        textField.text = text
        textField.keyboardType = keyboardType
        textField.textAlignment = .right
        textField.delegate = self
        textField.tag = tag
        textField.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),

            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        return cell
    }

    private func configureTwilioCell(_ tableView: UITableView,
                                     indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            // Twilio SID
            let value = UserDefaultsRepository.twilioSIDString.value
            let display = value.isEmpty ? nil : String(repeating: "*", count: value.count)
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Twilio SID",
                placeholder: "Ange SID",
                text: display,
                keyboardType: .default,
                tag: 100
            )

        case 1:
            // Twilio Secret
            let value = UserDefaultsRepository.twilioSecretString.value
            let display = value.isEmpty ? nil : String(repeating: "*", count: value.count)
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Twilio Secret",
                placeholder: "Ange Secret",
                text: display,
                keyboardType: .default,
                tag: 101
            )

        case 2:
            // From number
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Twilio frånnummer",
                placeholder: "Ange frånnummer",
                text: UserDefaultsRepository.twilioFromNumberString.value,
                keyboardType: .phonePad,
                tag: 102
            )

        default:
            // To number
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Twilio tillnummer",
                placeholder: "Ang tillnummer",
                text: UserDefaultsRepository.twilioToNumberString.value,
                keyboardType: .phonePad,
                tag: 103
            )
        }
    }

    private func configureShortcutsExampleCell(_ tableView: UITableView,
                                               indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellID.subtitle)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: CellID.subtitle)

        cell.selectionStyle = .none
        cell.backgroundColor = cardBackgroundColor
        cell.textLabel?.font = UIFont.systemFont(ofSize: 10)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = nil

        let row = shortcutsExampleRows[indexPath.row]

        switch row {
        case .remoteMealBolus:
            cell.textLabel?.text = "Remote Meal • Remote Måltid\\nKolhydrater: 25.5g\\nFett: 20g\\nProtein: 15g\\nNotering: Testmåltid\\nDatum: 2024-06-02T20:03:44.849Z\\nInsulin: 1.55E\\nEntered by: Dad\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        case .remoteMeal:
            cell.textLabel?.text = "Remote Meal • Remote Måltid\\nKolhydrater: 25.5g\\nFett: 20g\\nProtein: 15g\\nNotes: Testmåltid\\nDatum: 2024-06-02T20:03:44.849Z\\nInlagt av: Pappa\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        case .remoteBolus:
            cell.textLabel?.text = "Remote Bolus • Remote Bolus\\nInsulin: 0.75U\\nInlagt av: Pappa\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        case .remoteOverride:
            cell.textLabel?.text = "Remote Override • Remote Override\\n🎉 Partytime\\nInlagt av: Pappa\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        case .remoteTempTarget:
            cell.textLabel?.text = "Remote Temp Target • Remote Tillfälligt mål\\n🏃‍♂️ Exercise\\nInlagt av: Pappa\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        case .remoteCustomAction:
            cell.textLabel?.text = "Remote Custom Action • Remote Custom Action\\n🍿 Popcorn\\nInlagt av: Pappa\\nSecret: S3cr3tc0d3\\nSkickades: 2024-06-02T20:03:45.149Z"
        }

        return cell
    }

    private func configureRemoteConfigCell(_ tableView: UITableView,
                                           indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Fjärranvändares namn",
                placeholder: "Ange ditt namn",
                text: UserDefaultsRepository.caregiverName.value,
                keyboardType: .default,
                tag: 200
            )
        default:
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Hemlig kod",
                placeholder: "Ange en hemlig kod",
                text: UserDefaultsRepository.remoteSecretCode.value,
                keyboardType: .default,
                tag: 201
            )
        }
    }

    private func configurePresetCell(_ tableView: UITableView,
                                     indexPath: IndexPath) -> UITableViewCell {
        let row = presetRows[indexPath.row]

        switch row {
        case .overrides:
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Overrides:",
                placeholder: "👻 Resistance, 🤧 Sick day, 🏃‍♂️ Exercise, 😴 Nightmode",
                text: UserDefaultsRepository.overrideString.value,
                keyboardType: .default,
                tag: 300
            )
        case .tempTargets:
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Tillfälliga mål:",
                placeholder: "Exercise, Eating soon, Low treatment",
                text: UserDefaultsRepository.tempTargetsString.value,
                keyboardType: .default,
                tag: 301
            )
        case .customActions:
            return makeTextFieldCell(
                tableView,
                indexPath: indexPath,
                title: "Förvalda actions:",
                placeholder: "Custom Command 1, Custom Command 2, Custom Command 3",
                text: UserDefaultsRepository.customActionsString.value,
                keyboardType: .default,
                tag: 302
            )
        }
    }

    private func configureAdvancedCell(_ tableView: UITableView,
                                       indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellID.basic, for: indexPath)
        cell.selectionStyle = .none
        cell.backgroundColor = cardBackgroundColor
        cell.accessoryView = nil
        cell.accessoryType = .none

        let row = advancedRows[indexPath.row]

        switch row {
        case .showCustomActions:
            cell.textLabel?.text = "Visa förvalda actions"
            let toggle = UISwitch()
            toggle.isOn = !UserDefaultsRepository.hideRemoteCustomActions.value
            toggle.addTarget(self, action: #selector(showCustomActionsChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle

        case .showRemoteBolus:
            cell.textLabel?.text = "Visa remote bolus"
            let toggle = UISwitch()
            toggle.isOn = !UserDefaultsRepository.hideRemoteBolus.value
            toggle.addTarget(self, action: #selector(showRemoteBolusChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle

        case .showBolusCalc:
            cell.textLabel?.text = "Visa bolusberäkningar"
            let toggle = UISwitch()
            toggle.isOn = !UserDefaultsRepository.hideBolusCalc.value
            toggle.addTarget(self, action: #selector(showBolusCalcChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle

        case .useDynCr:
            cell.textLabel?.text = "Anv dyn CR i bolusberäkn."
            let toggle = UISwitch()
            toggle.isOn = UserDefaultsRepository.useDynCrInBolusCalc.value
            toggle.addTarget(self, action: #selector(useDynCrChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }

        return cell
    }

    private func configureGuardrailCell(_ tableView: UITableView,
                                        indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellID.guardrail, for: indexPath)
        cell.selectionStyle = .none
        cell.backgroundColor = cardBackgroundColor

        // Egen layout – rensa först
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let guardrail = GuardrailRow(rawValue: indexPath.row) ?? .maxCarbs

        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)

        let valueLabel = UILabel()
        valueLabel.font = UIFont.preferredFont(forTextStyle: .body)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let stepper = UIStepper()
        stepper.addTarget(self, action: #selector(guardrailStepperChanged(_:)), for: .valueChanged)
        stepper.tag = guardrail.rawValue

        switch guardrail {
        case .maxCarbs:
            titleLabel.text = "Max kolhydrater"
            let value = UserDefaultsRepository.maxCarbs.value
            valueLabel.text = "\(Int(value)) g"
            stepper.minimumValue = 0
            stepper.maximumValue = 200
            stepper.stepValue = 5
            stepper.value = value

        case .maxFatProtein:
            titleLabel.text = "Max fett/protein"
            let value = UserDefaultsRepository.maxFatProtein.value
            valueLabel.text = "\(Int(value)) g"
            stepper.minimumValue = 0
            stepper.maximumValue = 200
            stepper.stepValue = 5
            stepper.value = value

        case .maxBolus:
            titleLabel.text = "Max bolus"
            let value = UserDefaultsRepository.maxBolus.value
            valueLabel.text = String(format: "%.1f E", value)
            stepper.minimumValue = 0.1
            stepper.maximumValue = 50
            stepper.stepValue = 0.1
            stepper.value = value
        }

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, stepper])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
        ])

        return cell
    }

    // MARK: - Switch / Stepper handlers

    @objc private func showCustomActionsChanged(_ sender: UISwitch) {
        UserDefaultsRepository.hideRemoteCustomActions.value = !sender.isOn
        tableView.reloadData()
    }

    @objc private func showRemoteBolusChanged(_ sender: UISwitch) {
        UserDefaultsRepository.hideRemoteBolus.value = !sender.isOn
        tableView.reloadData()
    }

    @objc private func showBolusCalcChanged(_ sender: UISwitch) {
        UserDefaultsRepository.hideBolusCalc.value = !sender.isOn
        // Only this section changes layout
        if let sectionIndex = visibleSections.firstIndex(of: .advanced) {
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .automatic)
        } else {
            tableView.reloadData()
        }
    }

    @objc private func useDynCrChanged(_ sender: UISwitch) {
        UserDefaultsRepository.useDynCrInBolusCalc.value = sender.isOn
    }

    @objc private func guardrailStepperChanged(_ sender: UIStepper) {
        guard let row = GuardrailRow(rawValue: sender.tag) else { return }

        switch row {
        case .maxCarbs:
            UserDefaultsRepository.maxCarbs.value = sender.value
        case .maxFatProtein:
            UserDefaultsRepository.maxFatProtein.value = sender.value
        case .maxBolus:
            UserDefaultsRepository.maxBolus.value = sender.value
        }

        if let sectionIndex = visibleSections.firstIndex(of: .guardrails) {
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
        } else {
            tableView.reloadData()
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        let text = textField.text ?? ""

        switch textField.tag {
        // Twilio
        case 100:
            // Twilio SID – store raw value (mask is only display)
            UserDefaultsRepository.twilioSIDString.value = text
        case 101:
            UserDefaultsRepository.twilioSecretString.value = text
        case 102:
            UserDefaultsRepository.twilioFromNumberString.value = text
        case 103:
            UserDefaultsRepository.twilioToNumberString.value = text

        // Remote config
        case 200:
            UserDefaultsRepository.caregiverName.value = text
        case 201:
            let truncated = String(text.prefix(10))
            textField.text = truncated
            UserDefaultsRepository.remoteSecretCode.value = truncated

        // Presets
        case 300:
            UserDefaultsRepository.overrideString.value = text
        case 301:
            UserDefaultsRepository.tempTargetsString.value = text
        case 302:
            UserDefaultsRepository.customActionsString.value = text

        default:
            break
        }
    }
}

protocol RemoteSettingsDelegate: AnyObject {
    func remoteSettingsDidUpdateMethod()
}
