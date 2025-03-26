import UIKit
import LocalAuthentication
import AudioToolbox

class Value1TableViewCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        // Always use .value1 style
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Updated Treatment model includes the documentId (_id from the database)
struct Treatment {
    let documentId: String?
    let eventType: String
    let amount: String?
    let timestamp: Date
    let rawData: [String: AnyObject]
    
    // For override entries, we store additional info.
    let overrideNotes: String?
    let overrideDuration: Double? // in minutes
    
    // For Sensor Start entries, store notes
    let sensorStartNotes: String?
    
    // For Temp Basal entries
    let tempBasalDuration: Double?
    
    /// Failable initializer that creates a Treatment from a dictionary.
    init?(dictionary: [String: AnyObject]) {
        // Capture the _id (if available)
        self.documentId = dictionary["_id"] as? String
        
        guard let eventType = dictionary["eventType"] as? String else { return nil }
        self.eventType = eventType
        
        // Parse date from "timestamp" or "created_at".
        var dateString: String?
        if let ts = dictionary["timestamp"] as? String {
            dateString = ts
        } else if let ts = dictionary["created_at"] as? String {
            dateString = ts
        }
        guard let ds = dateString, let date = NightscoutUtils.parseDate(ds) else { return nil }
        self.timestamp = date
        
        self.rawData = dictionary
        
        // Fetch the note if the event type is Sensor Start
        if eventType == "Sensor Start" || eventType == "Sensor Change" || eventType == "Sensorbyte" || eventType == "Sensorstart" {
            self.sensorStartNotes = dictionary["notes"] as? String
        } else {
            self.sensorStartNotes = nil
        }
        
        // Create a number formatter that trims trailing zeros.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        
        var computedAmount: String? = nil
        var computedTempBasalDuration: Double? = nil
        
        if let insulin = dictionary["insulin"] as? Double {
            let insulinString = formatter.string(from: NSNumber(value: insulin)) ?? "\(insulin)"
            computedAmount = "\(insulinString) E"
        } else if let carbs = dictionary["carbs"] as? Double {
            let carbsString = formatter.string(from: NSNumber(value: carbs)) ?? "\(carbs)"
            computedAmount = "\(carbsString) g"
        } else if eventType == "Temp Basal", let absolute = dictionary["absolute"] as? Double {
            let absoluteString = formatter.string(from: NSNumber(value: absolute)) ?? "\(absolute)"
            computedAmount = "\(absoluteString) E/h"
            // Capture the duration (in minutes) for temp basal events
            computedTempBasalDuration = dictionary["duration"] as? Double
        }
        
        self.amount = computedAmount
        self.tempBasalDuration = computedTempBasalDuration
        // For override treatments, capture the notes and duration.
        if eventType == "Temporary Override" || eventType == "Exercise" || eventType == "Override" {
            self.overrideNotes = dictionary["notes"] as? String
            // Assume the "duration" field is in minutes.
            self.overrideDuration = dictionary["duration"] as? Double
        } else {
            self.overrideNotes = nil
            self.overrideDuration = nil
        }
    }
}

/// A view controller that downloads and displays all treatments in a table view,
/// with a segmented control above the table to filter the results.
class TreatmentsTableView: UIViewController, UITableViewDataSource, UITableViewDelegate, TwilioRequestable {

    private let tableView = UITableView()
    // The complete set of downloaded treatments.
    private var treatments: [Treatment] = []
    // Segmented control to filter treatments.
    private var segmentedControl: UISegmentedControl!
    
    // Define event type arrays for filtering.
    private let basalType = "Temp Basal"
    private let bolusTypes = ["Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna", "SMB"]
    private let mealTypes = ["Carb Correction", "Kolhydrater", "Dextro", "Måltid"]
    
    // Computed property that returns the treatments filtered by the segmented control.
    private var filteredTreatments: [Treatment] {
        switch segmentedControl.selectedSegmentIndex {
        case 1: // Basal – only Temp Basal entries
            return treatments.filter { $0.eventType == basalType }
        case 2: // Bolus – filter for all bolus-related entries
            return treatments.filter { bolusTypes.contains($0.eventType) }
        case 3: // Måltider
            return treatments.filter { mealTypes.contains($0.eventType) }
        case 4: // Övrigt – not any insulin or meal entries
            let insulinTypes = bolusTypes + [basalType]
            return treatments.filter { !insulinTypes.contains($0.eventType) && !mealTypes.contains($0.eventType) }
        default: // Allt
            return treatments
        }
    }
    
    // Activity indicator property for refresh progress
    private var activityIndicator: UIActivityIndicatorView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Behandlingslogg"
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupSegmentedControl()
        setupTableView()
        setupConstraints()
        loadTreatments()
        
        // Register observers for shortcut callback notifications
            NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutSuccess), name: NSNotification.Name("ShortcutSuccess"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutError), name: NSNotification.Name("ShortcutError"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutCancel), name: NSNotification.Name("ShortcutCancel"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutPasscode), name: NSNotification.Name("ShortcutPasscode"), object: nil)

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        // Right bar button remains as the Klar button.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Klar",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        // Add new left bar button item with arrow.clockwise symbol for refresh.
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    private func updateDuplicateIndicator() {
        // Check if any duplicate exists in the filtered treatments, excluding "Note" eventType
        let duplicatesExist = filteredTreatments.contains { treatment in
            guard treatment.eventType != "Note" else { return false }
            
            let count = filteredTreatments.filter {
                $0.timestamp == treatment.timestamp &&
                $0.eventType == treatment.eventType &&
                $0.eventType != "Note"
            }.count
            
            return count > 1
        }
        
        // Determine which refresh button to show: if a refresh is in progress, use the activity indicator.
        let refreshButton: UIBarButtonItem
        if let indicator = activityIndicator {
            refreshButton = UIBarButtonItem(customView: indicator)
        } else {
            refreshButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(refreshButtonTapped))
        }
        
        if duplicatesExist {
            let duplicateIndicator = UIBarButtonItem(
                image: UIImage(systemName: "document.on.document"),
                style: .plain,
                target: self,
                action: #selector(duplicateIndicatorTapped)
            )
            duplicateIndicator.tintColor = .systemRed
            navigationItem.leftBarButtonItems = [refreshButton, duplicateIndicator]
        } else {
            navigationItem.leftBarButtonItems = [refreshButton]
        }
    }
    
    @objc private func duplicateIndicatorTapped() {
        // Find the first non-Note treatment that has a duplicate (same timestamp and event type)
        if let duplicateIndex = filteredTreatments.firstIndex(where: { treatment in
            guard treatment.eventType != "Note" else { return false }
            
            let duplicateCount = filteredTreatments.filter {
                $0.timestamp == treatment.timestamp &&
                $0.eventType == treatment.eventType &&
                $0.eventType != "Note"
            }.count
            return duplicateCount > 1
        }) {
            let indexPath = IndexPath(row: duplicateIndex, section: 0)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
        }
    }
    
    // MARK: - Refresh Button Action
    
    @objc private func refreshButtonTapped() {
        showRefreshIndicator()
        loadTreatments()
    }
    
    private func showRefreshIndicator() {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        self.activityIndicator = indicator
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: indicator)
    }
    
    private func hideRefreshIndicator() {
        activityIndicator = nil
        updateDuplicateIndicator()
    }
    
    // MARK: - Setup Segmented Control
    
    private func setupSegmentedControl() {
        let segments = ["Allt", "Basal", "Bolus", "Måltider", "Övrigt"]
        segmentedControl = UISegmentedControl(items: segments)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
    }
    
    @objc private func filterChanged() {
        tableView.reloadData()
        updateDuplicateIndicator()
    }
    
    // MARK: - Setup TableView
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        // Register the custom cell class so that cells are always .value1 style.
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "TreatmentCell")
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    // MARK: - Setup Constraints
    
    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadTreatments() {
        if !UserDefaultsRepository.downloadTreatments.value {
            hideRefreshIndicator()
            return
        }
        
        let startTimeString = dateTimeUtils.getDateTimeString(addingDays: -1 * UserDefaultsRepository.downloadDays.value)
        let currentTimeString = dateTimeUtils.getDateTimeString(addingHours: 6)
        let parameters: [String: String] = [
            "find[created_at][$gte]": startTimeString,
            "find[created_at][$lte]": currentTimeString
        ]
        
        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: parameters) { (result: Result<Any, Error>) in
            switch result {
            case .success(let data):
                if let entries = data as? [[String: AnyObject]] {
                    var downloadedTreatments: [Treatment] = []
                    for entry in entries {
                        if let treatment = Treatment(dictionary: entry) {
                            downloadedTreatments.append(treatment)
                        }
                    }
                    downloadedTreatments.sort { $0.timestamp > $1.timestamp }
                    
                    DispatchQueue.main.async {
                        self.treatments = downloadedTreatments
                        self.tableView.reloadData()
                        self.hideRefreshIndicator()
                    }
                } else {
                    LogManager.shared.log(category: .nightscout, message: "TreatmentsTableView, Unexpected data structure")
                    DispatchQueue.main.async {
                        self.hideRefreshIndicator()
                    }
                }
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "TreatmentsTableView, error \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.hideRefreshIndicator()
                }
            }
        }
    }
    
    @objc private func refreshTreatments(_ sender: UIRefreshControl) {
        loadTreatments()
        // End refreshing after data is loaded; you might also call this in the completion of loadTreatments()
        sender.endRefreshing()
    }
    
    // MARK: - UITableViewDataSource Methods
    
    private func previewOverrideText(for text: String) -> String {
        if text.count > 16 {
            return String(text.prefix(16)) + "…"
        } else {
            return text
        }
    }
    
    private func previewCarbsText(for text: String) -> String {
        if text.count > 5 {
            return String(text.prefix(5)) + "…"
        } else {
            return text
        }
    }
    
    private func previewNoteText(for text: String) -> String {
        if text.count > 22 {
            return String(text.prefix(22)) + "…"
        } else {
            return text
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    // Helper to determine symbol name and color for a given event type.
    private func symbolForEventType(_ eventType: String, foodType: String? = nil) -> (name: String, color: UIColor) {
        if eventType == "Carb Correction" {
            // If foodType is empty or nil, use brown; otherwise use systemOrange.
            if let food = foodType, !food.isEmpty {
                return ("circle.fill", .systemOrange.withAlphaComponent(0.8))
            } else {
                return ("circle.fill", .brown.withAlphaComponent(0.4))
            }
        }
        
        switch eventType {
        case "Temp Basal":
            return ("circle.fill", .systemBlue.withAlphaComponent(0.2))
        case "Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna":
            return ("circle.fill", .systemBlue.withAlphaComponent(0.8))
        case "SMB":
            return ("bolt.circle.fill", .systemBlue.withAlphaComponent(0.8))
        case "Kolhydrater", "Dextro", "Måltid":
            return ("circle.fill", .systemOrange.withAlphaComponent(0.8))
        case "BG Check":
            return ("circle.fill", .systemRed.withAlphaComponent(1.0))
        case "Exercise":
            return ("circle.fill", .systemPurple.withAlphaComponent(0.7))
        case "Note", "Announcement":
            return ("circle.fill", .label.withAlphaComponent(0.5))
        default:
            return ("circle.fill", .label.withAlphaComponent(0.5))
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredTreatments.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TreatmentCell", for: indexPath) as? Value1TableViewCell else {
            return UITableViewCell(style: .value1, reuseIdentifier: "TreatmentCell")
        }
        
        let treatment = filteredTreatments[indexPath.row]
        let displayEventType: String
        if treatment.eventType == "Carb Correction" {
            if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                displayEventType = "Kh"
            } else {
                displayEventType = "Fett / Protein"
            }
        } else {
            displayEventType = treatment.eventType
        }
        
        // Special handling for BG Check entries.
        if treatment.eventType == "BG Check" {
            if let glucose = treatment.rawData["glucose"] as? Double,
               let units = treatment.rawData["units"] as? String {
                let mmol: Double = units.lowercased().contains("mmol") ? glucose : glucose / 18.0
                cell.textLabel?.text = "Fingerstick • \(String(format: "%.1f", mmol)) mmol/L"
            } else {
                cell.textLabel?.text = displayEventType
            }
            cell.accessoryType = .none
        }
        // Handling for override treatments.
        else if treatment.eventType == "Temporary Override" || treatment.eventType == "Exercise" || treatment.eventType == "Override" {
            if let notes = treatment.overrideNotes {
                let preview = previewOverrideText(for: notes)
                if let duration = treatment.overrideDuration {
                    // Check if duration is more than 1440 minutes.
                    if duration > 1440 {
                        cell.textLabel?.text = "\(preview) • Tillsvidare"
                    } else {
                        cell.textLabel?.text = "\(preview) • \(Int(duration)) m"
                    }
                } else {
                    cell.textLabel?.text = preview
                }
            } else {
                cell.textLabel?.text = displayEventType
            }
            cell.accessoryType = .none
        }
        // For Carb Correction: we display foodType similarly.
        else if treatment.eventType == "Carb Correction" {
            let mainText = treatment.amount != nil ? "\(displayEventType) • \(treatment.amount!)" : displayEventType
            if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                let cleanedFoodType = foodType.replacingOccurrences(of: "\u{FE0F}", with: "")
                let preview = previewCarbsText(for: cleanedFoodType)
                let combinedText = mainText + " • " + preview
                cell.textLabel?.text = combinedText
                cell.textLabel?.font = .systemFont(ofSize: 17)
                cell.textLabel?.numberOfLines = 0
            } else {
                cell.textLabel?.text = mainText
            }
            cell.accessoryType = .none
        }
        // Handling for Note entries.
        else if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let note = treatment.rawData["notes"] as? String {
                let preview = previewNoteText(for: note)
                cell.textLabel?.text = "Not: " + preview
            } else {
                cell.textLabel?.text = displayEventType
            }
            //cell.accessoryType = .disclosureIndicator
        }
        // Handling for Temp Basal entries.
        else if treatment.eventType == "Temp Basal" {
            if let duration = treatment.tempBasalDuration, let amount = treatment.amount {
                // Display the duration as an integer (you can also format with decimals if needed)
                cell.textLabel?.text = "\(treatment.eventType) • \(amount) • \(Int(duration)) m"
            } else {
                cell.textLabel?.text = treatment.eventType
            }
            cell.accessoryType = .none
        }
        // All other treatments.
        else {
            // If the treatment is a Carb Correction (which we display as "Meal")
            // and has a foodType value, show an attributed text with a second line.
            if treatment.eventType == "Carb Correction" {
                let mainText = treatment.amount != nil ? "\(displayEventType) • \(treatment.amount!)" : displayEventType
                if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                    // Remove variation selectors if desired.
                    let cleanedFoodType = foodType.replacingOccurrences(of: "\u{FE0F}", with: "")
                    
                    // Just do a single plain string with a newline
                    let combinedText = mainText + " • " + cleanedFoodType
                    cell.textLabel?.text = combinedText
                    cell.textLabel?.font = .systemFont(ofSize: 17)
                    cell.textLabel?.numberOfLines = 0
                } else {
                    cell.textLabel?.text = mainText
                }
            } else {
                // For non-carb-correction entries, use the standard text.
                if let amount = treatment.amount {
                    cell.textLabel?.text = "\(displayEventType) • \(amount)"
                } else {
                    cell.textLabel?.text = displayEventType
                }
            }
            cell.accessoryType = .none
        }
        
        // Format timestamp as HH:mm:ss.
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        cell.detailTextLabel?.text = timeFormatter.string(from: treatment.timestamp)
        
        // Determine symbol and color.
        let symbolInfo: (name: String, color: UIColor)
            if treatment.eventType == "Carb Correction" {
                let foodType = treatment.rawData["foodType"] as? String
                symbolInfo = symbolForEventType(treatment.eventType, foodType: foodType)
            } else {
                symbolInfo = symbolForEventType(treatment.eventType)
            }
        if let image = UIImage(systemName: symbolInfo.name) {
            cell.imageView?.image = image
            cell.imageView?.tintColor = symbolInfo.color
        }
        
        cell.selectionStyle = .none
        
        // Check for duplicates: only count duplicates that have the same timestamp AND the same event type (excluding "Note").
        let duplicateCount = filteredTreatments.filter {
            $0.timestamp == treatment.timestamp &&
            $0.eventType == treatment.eventType &&
            $0.eventType != "Note"
        }.count
        
        // Apply red background only if duplicates exist and the eventType isn't "Note".
        if duplicateCount > 1 && treatment.eventType != "Note" {
            cell.backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        } else {
            cell.backgroundColor = UIColor.systemBackground
        }
        
        return cell
    }
    
    // MARK: - Swipe to Delete (Editing Style)
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let treatment = filteredTreatments[indexPath.row]
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: treatment.timestamp)
        
        let deleteAction = UIContextualAction(style: .destructive, title: nil) { (action, view, completionHandler) in
            // Retrieve remote type from Storage.
            let remoteType = Storage.shared.remoteType.value
            
            // If the treatment is a Carb Correction and remote type is SMS, present the three-option alert.
            if treatment.eventType == "Carb Correction",
               let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty,
               remoteType == .sms {
                let alert = UIAlertController(
                    title: "Radera måltid?",
                    message: "\nVälj om du vill: \n\n• Radera måltiden i Trio (vilket också raderar den i Nightscout) \n\n• Radera endast måltiden i Nightscout (vilket INTE raderar den i Trio!)",
                    preferredStyle: .alert)
                
                alert.addAction(UIAlertAction(title: "Trio & Nightscout", style: .default, handler: { _ in
                    self.deleteEntryInTrio(for: treatment)
                    completionHandler(true)
                }))
                
                alert.addAction(UIAlertAction(title: "Endast Nightscout", style: .destructive, handler: { _ in
                    guard let treatmentId = treatment.documentId else {
                        completionHandler(false)
                        return
                    }
                    NightscoutUtils.executeDeleteRequest(treatmentId: treatmentId) { result in
                        switch result {
                        case .success(_):
                            DispatchQueue.main.async {
                                if let index = self.treatments.firstIndex(where: { $0.documentId == treatment.documentId }) {
                                    self.treatments.remove(at: index)
                                }
                                self.tableView.reloadData()
                                self.updateDuplicateIndicator()
                            }
                        case .failure(let error):
                            DispatchQueue.main.async {
                                let failureAlert = UIAlertController(
                                    title: "Kunde inte radera!",
                                    message: "Kontrollera att du har skrivåtkomst i din Nightscout token",
                                    preferredStyle: .alert)
                                failureAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(failureAlert, animated: true, completion: nil)
                            }
                            print("Failed to delete treatment: \(error.localizedDescription)")
                        }
                        completionHandler(true)
                    }
                }))
                
                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))
                self.present(alert, animated: true, completion: nil)
            } else {
                // Use a custom display name for deletion alerts.
                let displayEventName: String
                if treatment.eventType == "Carb Correction" {
                    if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                        displayEventName = "Kolhydrater"
                    } else {
                        displayEventName = "Fett / Protein"
                    }
                } else if treatment.eventType == "Note" {
                    displayEventName = "Notering"
                } else if treatment.eventType == "Exercise" {
                    displayEventName = "Override"
                } else {
                    displayEventName = treatment.eventType
                }
                
                let message = "Vill du verkligen radera:\n \(displayEventName) • \(timeString)?"
                let alert = UIAlertController(title: "Radera behandling?", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))
                alert.addAction(UIAlertAction(title: "OK", style: .destructive, handler: { _ in
                    guard let treatmentId = treatment.documentId else {
                        completionHandler(false)
                        return
                    }
                    NightscoutUtils.executeDeleteRequest(treatmentId: treatmentId) { result in
                        switch result {
                        case .success(_):
                            DispatchQueue.main.async {
                                if let index = self.treatments.firstIndex(where: { $0.documentId == treatment.documentId }) {
                                    self.treatments.remove(at: index)
                                }
                                self.tableView.reloadData()
                                self.updateDuplicateIndicator()
                            }
                        case .failure(let error):
                            DispatchQueue.main.async {
                                let failureAlert = UIAlertController(
                                    title: "Kunde inte radera!",
                                    message: "Kontrollera att du har skrivåtkomst i din Nightscout token",
                                    preferredStyle: .alert)
                                failureAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(failureAlert, animated: true, completion: nil)
                            }
                        }
                        completionHandler(true)
                    }
                }))
                self.present(alert, animated: true, completion: nil)
            }
        }
        
        // Set the trashcan SF Symbol and customize appearance.
        deleteAction.image = UIImage(systemName: "trash")
        deleteAction.backgroundColor = .red
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    // MARK: - Remote Delete for Carb Correction (Trio)
        private func deleteEntryInTrio(for treatment: Treatment) {
            // Extract carbohydrates from treatment's rawData.
            let carbsValue: Double
            if let carbsStr = treatment.rawData["carbs"] as? String, let value = Double(carbsStr) {
                carbsValue = value
            } else if let carbsNum = treatment.rawData["carbs"] as? Double {
                carbsValue = carbsNum
            } else {
                carbsValue = 0
            }
            
            // Format the treatment's timestamp.
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let formattedDate = dateFormatter.string(from: treatment.timestamp)
            
            // Retrieve additional details from user defaults.
            let name = UserDefaultsRepository.caregiverName.value
            let secret = UserDefaultsRepository.remoteSecretCode.value
            
            // Get current timestamp.
            let currentTimestamp = Date()
            let formattedTimestamp = dateFormatter.string(from: currentTimestamp)
            
            // Build the combined command string.
            let combinedString = "Remote Delete\nKolhydrater: \(carbsValue)g\nDatum: \(formattedDate)\nInlagt av: \(name)\nSecret: \(secret)\nSkickades: \(formattedTimestamp)"
            
            // Send the remote command.
            sendRemoteDeleteCommand(combinedString: combinedString)
        }

    private func sendRemoteDeleteCommand(combinedString: String) {
        // Retrieve the method from user defaults.
        let method = UserDefaultsRepository.method.value
        
        if method != "SMS API" {
            // Use the Shortcuts URL scheme.
            guard let encodedString = combinedString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                print("Failed to encode URL string")
                return
            }
            // Define callback URLs.
            let successCallback = "loop://completed"
            let errorCallback = "loop://error"
            let cancelCallback = "loop://cancel"
            
            guard let successEncoded = successCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let errorEncoded = errorCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let cancelEncoded = cancelCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                print("Failed to encode callback URLs")
                return
            }
            
            let urlString = "shortcuts://x-callback-url/run-shortcut?name=Remote%20Delete&input=text&text=\(encodedString)&x-success=\(successEncoded)&x-error=\(errorEncoded)&x-cancel=\(cancelEncoded)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            print("Waiting for shortcut completion...")
        } else {
            // For SMS API, first show a confirmation alert with authentication.
            showRemoteDeleteConfirmationAlert(combinedString: combinedString)
        }
    }

    /// Presents a confirmation alert for SMS deletion. If the user selects "Ja", we authenticate first.
    private func showRemoteDeleteConfirmationAlert(combinedString: String) {
        let confirmationAlert = UIAlertController(
            title: "Bekräfta radering",
            message: "Är du säker på att du vill radera måltiden i Trio?",
            preferredStyle: .alert)
        
        confirmationAlert.addAction(UIAlertAction(title: "Ja", style: .default, handler: { _ in
            // Authenticate with biometrics; on success, send the command.
            self.authenticateWithBiometrics {
                self.sendRemoteDeleteCommandInternal(combinedString: combinedString)
            }
        }))
        
        confirmationAlert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
            self.handleAlertDismissal()
        }))
        
        self.present(confirmationAlert, animated: true, completion: nil)
    }

    /// Actually sends the remote delete command via Twilio (SMS API).
    private func sendRemoteDeleteCommandInternal(combinedString: String) {
        twilioRequest(combinedString: combinedString) { result in
            switch result {
            case .success:
                AudioServicesPlaySystemSound(SystemSoundID(1322))
                DispatchQueue.main.async {
                    self.showAlert(title: "Lyckades!", message: "Meddelandet levererades") { }
                }
            case .failure(let error):
                AudioServicesPlaySystemSound(SystemSoundID(1053))
                DispatchQueue.main.async {
                    self.showAlert(title: "Fel", message: error.localizedDescription) { }
                }
            }
        }
    }

    /// MARK: - Authentication & Alert Helpers

    func authenticateWithBiometrics(completion: @escaping () -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Authenticate with biometrics to proceed"
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        completion()
                    } else {
                        if let error = authenticationError as NSError?,
                           error.code == LAError.biometryNotAvailable.rawValue ||
                           error.code == LAError.biometryNotEnrolled.rawValue {
                            self.authenticateWithPasscode(completion: completion)
                        } else {
                            print("Authentication failed: \(authenticationError?.localizedDescription ?? "unknown error")")
                            self.handleAlertDismissal()
                        }
                    }
                }
            }
        } else {
            self.authenticateWithPasscode(completion: completion)
        }
    }

    func authenticateWithPasscode(completion: @escaping () -> Void) {
        let context = LAContext()
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate with passcode to proceed") { success, error in
            DispatchQueue.main.async {
                if success {
                    completion()
                } else {
                    print("Authentication failed: \(error?.localizedDescription ?? "unknown error")")
                    self.handleAlertDismissal()
                }
            }
        }
    }


    // MARK: - Shortcut Callback Handlers (without dismissing the view)

    @objc private func handleShortcutSuccess() {
        print("Shortcut succeeded")
        AudioServicesPlaySystemSound(SystemSoundID(1322))
        showAlert(title: NSLocalizedString("Lyckades", comment: "Lyckades"),
                  message: NSLocalizedString("Meddelandet levererades", comment: "Meddelandet levererades"),
                  completion: { /* No dismissal here */ })
    }

    @objc private func handleShortcutError() {
        print("Shortcut failed, showing error alert...")
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Misslyckades", comment: "Misslyckades"),
                  message: NSLocalizedString("Ett fel uppstod när genvägen skulle köras. Du kan försöka igen.", comment: "Ett fel uppstod när genvägen skulle köras. Du kan försöka igen."),
                  completion: { /* Re-enable send button if needed */ })
    }

    @objc private func handleShortcutCancel() {
        print("Shortcut was cancelled, showing cancellation alert...")
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Avbröts", comment: "Avbröts"),
                  message: NSLocalizedString("Genvägen avbröts innan den körts färdigt. Du kan försöka igen.", comment: "Genvägen avbröts innan den körts färdigt. Du kan försöka igen."),
                  completion: { /* Re-enable send button if needed */ })
    }

    @objc private func handleShortcutPasscode() {
        print("Shortcut was cancelled due to wrong passcode, showing passcode alert...")
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Fel lösenkod", comment: "Fel lösenkod"),
                  message: NSLocalizedString("Genvägen avbröts pga fel lösenkod. Du kan försöka igen.", comment: "Genvägen avbröts pga fel lösenkod. Du kan försöka igen."),
                  completion: { /* Re-enable send button if needed */ })
    }
    
    /// Presents an alert with a title, message, and calls completion after dismissal.
    private func showAlert(title: String, message: String, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completion()
        }))
        self.present(alert, animated: true, completion: nil)
    }

    /// Called when an alert is dismissed (e.g. after cancellation or authentication failure).
    private func handleAlertDismissal() {
        // For example, re-enable any disabled buttons; here we simply print.
        print("Alert dismissed, re-enabling controls if needed.")
    }

    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let treatment = filteredTreatments[indexPath.row]
        
        // Create a time formatter to display the timestamp as "HH:mm"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: treatment.timestamp)
        
        // Fetch reason-string from device status for the particular event timestamp
        if treatment.eventType == "Bolus" || treatment.eventType == "SMB" || treatment.eventType == "Temp Basal" {
            // Adjust timestamp by adding 30 seconds
            let adjustedTimestamp = treatment.timestamp.addingTimeInterval(30)
            
            NightscoutUtils.fetchDeviceStatusReasonBeforeTimestamp(timestamp: adjustedTimestamp) { result in
                switch result {
                case .success(let reason):
                    let formattedReason = self.formatReason(reason)
                    let alert = UIAlertController(title: "Trio behandlingsbeslut", message: formattedReason, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    
                case .failure(let error):
                    let alert = UIAlertController(title: "Fel", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
        
        // For Note entries:
        if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let fullNote = treatment.rawData["notes"] as? String {
                let title = "Notering \(timeString)"
                let message = "\(fullNote)"
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        }
        
        // Handle Sensor Start Notes
        if treatment.eventType == "Sensor Start" || treatment.eventType == "Sensor Change" || treatment.eventType == "Sensorbyte" || treatment.eventType == "Sensorstart" {
            let title = "Sensorbyte \(timeString)"
            let message = treatment.sensorStartNotes ?? "Inga anteckningar"
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
        
        // For override treatments:
        else if treatment.eventType == "Temporary Override" ||
                    treatment.eventType == "Exercise" ||
                    treatment.eventType == "Override" {
            if let fullOverride = treatment.overrideNotes {
                let title = "Override \(timeString)"
                var message = "\(fullOverride)"
                if let duration = treatment.overrideDuration {
                    message += "\nVaraktighet: \(Int(duration)) min"
                }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        }
        // For Carb Correction entries:
        else if treatment.eventType == "Carb Correction" {
            // Retrieve the foodType as an optional String:
            let foodType = treatment.rawData["foodType"] as? String
            let title = "Måltid \(timeString)"
            // Build the message string. If foodType is nil, "nil" will appear in the string.
            // You could replace "nil" with any placeholder text if desired.
            var message = "\(foodType ?? "Kolhydratsekvivalenter")"
            
            // Carbohydrates:
            let carbsValue: Double = (treatment.rawData["carbs"] as? Double) ?? 0.0
            message += "\nKolhydrater: \(formatValue(carbsValue)) g"
            
            // Fat:
            let fatValue: Double = (treatment.rawData["fat"] as? Double) ?? 0.0
            if fatValue != 0 {
                message += "\nFett: \(formatValue(fatValue)) g"
            }
            
            // Protein:
            let proteinValue: Double = (treatment.rawData["protein"] as? Double) ?? 0.0
            if proteinValue != 0 {
                message += "\nProtein: \(formatValue(proteinValue)) g"
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }

    }
    
    func formatReason(_ reason: String) -> String {
        var formatted = reason
        
        // Step 1: Handle AF and SMB Ratio before other replacements.
        // Regex pattern to match: "AF: <number> (optionally, , SMB Ratio: <number>) ;"
        let patternAFSMB = "AF:\\s([0-9]\\.[0-9]{1,2})(?:,\\sSMB Ratio:\\s([0-9]\\.[0-9]{1,2}))?;"
        if let regexAFSMB = try? NSRegularExpression(pattern: patternAFSMB, options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            // Enumerate matches in reverse order to avoid index shifts.
            let matches = regexAFSMB.matches(in: formatted, options: [], range: range)
            for match in matches.reversed() {
                let fullRange = match.range(at: 0)
                let afValue = (formatted as NSString).substring(with: match.range(at: 1))
                var replacement = "AF: \(afValue)\n"
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    let smbValue = (formatted as NSString).substring(with: match.range(at: 2))
                    if !smbValue.isEmpty {
                        replacement += "• SMB Ratio: \(smbValue)\n"
                    }
                }
                replacement += "\n\n👉  OREF SLUTSATS:\n•"
                formatted = (formatted as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }
        
        // Step 2: Replace all commas with a line break bullet.
        formatted = formatted.replacingOccurrences(of: ",", with: "\n•")
        
        // Step 3: Specific replacements.
        formatted = formatted.replacingOccurrences(of: "SMB INAKTIVERADE!", with: "SMB Inaktiverade 🚫")
        formatted = formatted.replacingOccurrences(of: "Mikrobolus:", with: "\n🔹 Mikrobolus:")
        formatted = formatted.replacingOccurrences(of: "Microbolusing", with: "\n🔹 Mikrobolus:")
        formatted = formatted.replacingOccurrences(of: "E. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "U. ", with: "E\n")
        
        // Step 4: Replace "; " with a line break bullet.
        formatted = formatted.replacingOccurrences(of: "; ", with: "\n•")
        
        // Step 5: Other formatting rules.
        formatted = formatted.replacingOccurrences(of: "add'l carbs req w/in", with: "g kh behövs inom")
        
        // Replace TDD: <number> U with bold TDD (using regex)
        if let regexTDD = try? NSRegularExpression(pattern: "TDD:\\s(\\d+(?:\\.\\d{1,2})?)\\sU", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexTDD.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "TDD: $1E")
        }
        
        // Replace temp <number>&lt;<number>U/hr. with "Temp <number>&lt;<number>E/h"
        if let regexTemp = try? NSRegularExpression(pattern: "temp\\s(\\d+\\.\\d{1,2})&lt;(\\d+\\.\\d{1,2})U/hr\\.", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexTemp.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "Temp $1&lt;$2E/h")
        }
        
        // Replace "insulinReq" with "Insulinbehov:"
        formatted = formatted.replacingOccurrences(of: "insulinReq", with: "Insulinbehov:")
        
        // New step: Replace HTML encoded less-than and greater-than signs
        formatted = formatted.replacingOccurrences(of: "&lt;", with: "<")
        formatted = formatted.replacingOccurrences(of: "&gt;", with: ">")
        
        return formatted
    }
}
