import UIKit

class Value1TableViewCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        // Always use .value1 style
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A simple model representing a treatment entry.
struct Treatment {
    let eventType: String
    let amount: String?
    let timestamp: Date
    let rawData: [String: AnyObject]
    
    // For override entries, we store additional info.
    let overrideNotes: String?
    let overrideDuration: Double? // in minutes
    
    /// Failable initializer that creates a Treatment from a dictionary.
    init?(dictionary: [String: AnyObject]) {
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
        
        // Create a number formatter that trims trailing zeros.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        
        // Determine amount for non-override cases.
        if let insulin = dictionary["insulin"] as? Double {
            let insulinString = formatter.string(from: NSNumber(value: insulin)) ?? "\(insulin)"
            self.amount = "\(insulinString) E"
        } else if let carbs = dictionary["carbs"] as? Double {
            let carbsString = formatter.string(from: NSNumber(value: carbs)) ?? "\(carbs)"
            self.amount = "\(carbsString) g"
        } else if eventType == "Temp Basal", let absolute = dictionary["absolute"] as? Double {
            let absoluteString = formatter.string(from: NSNumber(value: absolute)) ?? "\(absolute)"
            self.amount = "\(absoluteString) E/h"
        } else {
            self.amount = nil
        }
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
class TreatmentsTableView: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    private let tableView = UITableView()
    // The complete set of downloaded treatments.
    private var treatments: [Treatment] = []
    // Segmented control to filter treatments.
    private var segmentedControl: UISegmentedControl!
    
    // Define event type arrays for filtering.
    private let insulinTypes = ["Temp Basal", "Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna", "SMB"]
    private let mealTypes = ["Carb Correction", "Kolhydrater", "Dextro", "Måltid"]
    
    // Computed property that returns the treatments filtered by the segmented control.
    private var filteredTreatments: [Treatment] {
        switch segmentedControl.selectedSegmentIndex {
        case 1: // Insulin
            return treatments.filter { insulinTypes.contains($0.eventType) }
        case 2: // Meals
            return treatments.filter { mealTypes.contains($0.eventType) }
        case 3: // Other: not insulin and not meals.
            return treatments.filter { !insulinTypes.contains($0.eventType) && !mealTypes.contains($0.eventType) }
        default: // All
            return treatments
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Behandlingslogg"
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupSegmentedControl()
        setupTableView()
        setupConstraints()
        loadTreatments()
    }
    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Setup Segmented Control
    
    private func setupSegmentedControl() {
        let segments = ["Allt", "Insulin", "Måltider", "Övrigt"]
        segmentedControl = UISegmentedControl(items: segments)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
    }
    
    @objc private func filterChanged() {
        tableView.reloadData()
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
            // Place the segmented control at the top.
            segmentedControl.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
            
            // Place the table view below the segmented control.
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadTreatments() {
        if !UserDefaultsRepository.downloadTreatments.value { return }
        
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
                    }
                } else {
                    LogManager.shared.log(category: .nightscout, message: "TreatmentsTableView, Unexpected data structure")
                }
            case .failure(let error):
                LogManager.shared.log(category: .nightscout, message: "TreatmentsTableView, error \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - UITableViewDataSource Methods
    
    // Helper to determine symbol name and color for a given event type.
    private func symbolForEventType(_ eventType: String) -> (name: String, color: UIColor) {
        switch eventType {
        case "Temp Basal":
            return ("circle.fill", .systemBlue.withAlphaComponent(0.3))
        case "Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna":
            return ("circle.fill", .systemBlue.withAlphaComponent(0.75))
        case "SMB":
            return ("bolt.circle.fill", .systemBlue.withAlphaComponent(0.75))
        case "Carb Correction", "Kolhydrater", "Dextro", "Måltid":
            return ("circle.fill", .systemOrange.withAlphaComponent(0.75))
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
        
        // For display purposes, replace "Carb Correction" with "Meal"
        let displayEventType = treatment.eventType == "Carb Correction" ? "Kolhydrater" : treatment.eventType
        
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
                if let duration = treatment.overrideDuration {
                    cell.textLabel?.text = "\(notes) • \(Int(duration)) min"
                } else {
                    cell.textLabel?.text = notes
                }
            } else {
                cell.textLabel?.text = displayEventType
            }
            cell.accessoryType = .none
        }
        // Handling for Note entries.
        else if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let note = treatment.rawData["notes"] as? String {
                let previewText = note.count > 20 ? String(note.prefix(20)) + "…" : note
                cell.textLabel?.text = "Not: " + previewText
            } else {
                cell.textLabel?.text = displayEventType
            }
            //cell.accessoryType = .disclosureIndicator
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
        
        // Format timestamp as HH:mm.
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        cell.detailTextLabel?.text = timeFormatter.string(from: treatment.timestamp)
        
        // Determine symbol and color.
        let symbolInfo = symbolForEventType(treatment.eventType)
        if let image = UIImage(systemName: symbolInfo.name) {
            cell.imageView?.image = image
            cell.imageView?.tintColor = symbolInfo.color
        }
        
        cell.selectionStyle = .none
        return cell
    }
    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let treatment = filteredTreatments[indexPath.row]
        // If the treatment is a Note entry, show an alert with the full note.
        if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let fullNote = treatment.rawData["notes"] as? String {
                let alert = UIAlertController(title: "Notering", message: fullNote, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        }
    }
}
