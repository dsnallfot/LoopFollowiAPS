import UIKit
import LocalAuthentication
import AudioToolbox
// Event model is declared in MealAnalysisView.swift

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
class TreatmentsTableView: ThemedViewController, UITableViewDataSource, UITableViewDelegate, TwilioRequestable, MealAnalysisViewDelegate {

    private let tableView = UITableView()
    /// The complete set of downloaded treatments.
    private var treatments: [Treatment] = []
    
    /// Simple BG point model (in mmol/L) for this view's date window
    private struct BGPoint {
        let date: Date
        let mmol: Double
    }

    /// Glucose points loaded for the current date window
    private var bgPoints: [BGPoint] = []
    
    /// Picker for selecting a calendar date (“Valt datum”)
    private let datePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        picker.locale = Locale(identifier: "sv_SE")
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()
    /// Currently selected calendar date
    private var selectedDate: Date = Date()
    // Segmented control to filter treatments.
    private var segmentedControl: UISegmentedControl!
    
    // Define event type arrays for filtering.
    private let autoTypes = ["Temp Basal", "SMB"]
    //private let mealTypes = ["Carb Correction", "Kolhydrater", "Dextro", "Måltid"]
    private let manualTypes = ["Carb Correction", "Kolhydrater", "Dextro", "Måltid", "Bolus", "Correction Bolus", "Meal Bolus", "Insulinpenna", "Exercise", "BG Check"]
    
    // Computed property that returns the treatments filtered by the segmented control.
    private var filteredTreatments: [Treatment] {
        switch segmentedControl.selectedSegmentIndex {
        case 1: // Auto – filter for all auto treatment entries
            return treatments.filter { autoTypes.contains($0.eventType) }
        case 2: // Manual – only Manual entries
            return treatments.filter { treatment in
                if treatment.eventType == "Carb Correction" {
                    // Only include if foodType is non-empty.
                    if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                        return true
                    } else {
                        return false
                    }
                } else {
                    return manualTypes.contains(treatment.eventType)
                }
            }
        case 3: // Övrigt – not any insulin or meal entries
            return treatments.filter { !autoTypes.contains($0.eventType) && !manualTypes.contains($0.eventType) }
        default: // Allt
            return treatments
        }
    }
    
    // Activity indicator property for refresh progress
    private var activityIndicator: UIActivityIndicatorView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Shift table content down to make room for the date picker
        self.title = "Behandlingar"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()
        setupNavigationBar()
        setupSegmentedControl()
        setupTableView()
        // Add “Valt datum” picker
        view.addSubview(datePicker)
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
        // Restrict selectable range to cached window
        let cal = Calendar.current
        if let oldest = cal.date(byAdding: .day,
                                  value: -NightscoutCache.retentionDays + 1,
                                  to: Date()) {
            datePicker.minimumDate = oldest
        }
        datePicker.maximumDate = Date()
        datePicker.date = selectedDate
        setupConstraints()
        
        // Initial load for today (from cache if available, else fallback fetch)
        loadTreatments(for: selectedDate)

        // Listen for cache updates so we can refresh the table when new
        // treatments for the selected day have been written to NightscoutCache.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTreatmentsCacheUpdated(_:)),
            name: NSNotification.Name("TreatmentsCacheUpdated"),
            object: nil
        )
        
        // Register observers for shortcut callback notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutSuccess), name: NSNotification.Name("ShortcutSuccess"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutError), name: NSNotification.Name("ShortcutError"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutCancel), name: NSNotification.Name("ShortcutCancel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutPasscode), name: NSNotification.Name("ShortcutPasscode"), object: nil)

        // Ask MainViewController to perform a lightweight, treatments-only
        // refresh for the currently selected calendar day. It will fetch
        // treatments from Nightscout and update NightscoutCache, which in
        // turn triggers a "TreatmentsCacheUpdated" notification.
        //let cal = Calendar.current

        // IMPORTANT:
        // If the selected date is today, do NOT trigger a day-based cache refresh here.
        // A day-based refresh (midnight→midnight) can overwrite the rolling-window
        // treatments cache and cause MainViewController to temporarily lose pre-midnight
        // treatments in the chart until the next scheduled treatments task repopulates.
        if !cal.isDate(selectedDate, inSameDayAs: Date()) {
            let dayStart = cal.startOfDay(for: selectedDate)
            NotificationCenter.default.post(
                name: NSNotification.Name("RefreshTreatmentsCacheForDay"),
                object: nil,
                userInfo: ["day": dayStart]
            )
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            await NightscoutUtils.retryPendingUploads()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleTreatmentsCacheUpdated(_ notification: Notification) {
        // Only react if the updated day matches the currently selected day
        guard let updatedDayStart = notification.userInfo?["dayStart"] as? Date else { return }
        let cal = Calendar.current
        let selectedDayStart = cal.startOfDay(for: selectedDate)
        guard cal.isDate(updatedDayStart, inSameDayAs: selectedDayStart) else { return }

        // Reload treatments from cache for the selected date now that
        // NightscoutCache has been refreshed.
        loadTreatments(for: selectedDate)
    }
    
    // MARK: - Date sync overlay
    private func showDateSyncOverlay(message: String) {
        // Semi-transparent full-screen overlay
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        overlay.alpha = 0.0
        
        // Centered solid container
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.9)
        container.layer.cornerRadius = 14
        container.clipsToBounds = true
        
        // SF Symbol icon
        let imageView = UIImageView(image: UIImage(systemName: "info.circle"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.textAlignment = .center
        label.textColor = .label
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0
        
        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 40),
            imageView.widthAnchor.constraint(equalToConstant: 40),

            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 17),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -17),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])
        
        overlay.addSubview(container)
        view.addSubview(overlay)
        
        let isModalRoot = navigationController?.viewControllers.first === self
        let containerTopInset: CGFloat = isModalRoot ? 77 : 120

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            container.topAnchor.constraint(equalTo: overlay.topAnchor, constant: containerTopInset),
            container.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12)
        ])
        view.layoutIfNeeded()
        
        // Light haptic feedback when the overlay appears
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        
        UIView.animate(withDuration: 0.25, animations: {
            overlay.alpha = 1.0
        }, completion: { _ in
            UIView.animate(withDuration: 0.3,
                           delay: 2.0,
                           options: [.curveEaseInOut],
                           animations: {
                overlay.alpha = 0.0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
        })
    }
    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        // Detect whether this controller is the *root* of its navigation stack.
        // When presented modally inside its own UINavigationController,
        // TreatmentsTableView will be the first (root) view controller.
        // When pushed from SettingsViewController, it will NOT be the root.
        let isModalRoot = navigationController?.viewControllers.first === self
        
        let klarButton = UIBarButtonItem(
            title: "Klar",
            style: .plain,
            target: self,
            action: #selector(doneButtonTapped)
        )
        let mealAnalysisButton = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar.xaxis.ascending"),
            style: .plain,
            target: self,
            action: #selector(mealAnalysisButtonTapped)
        )
        
        // Right-side items:
        // - In modal (root) mode: show both Meal Analysis and Klar.
        // - When pushed from Settings: hide Klar, keep only Meal Analysis.
        if isModalRoot {
            navigationItem.rightBarButtonItems = [klarButton, mealAnalysisButton]
        } else {
            navigationItem.rightBarButtonItems = [mealAnalysisButton]
        }
        
        // Left-side refresh button:
        let refreshButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshButtonTapped)
        )
        
        if isModalRoot {
            // In modal mode there is no back button, so just show the refresh button.
            navigationItem.leftBarButtonItem = refreshButton
        } else {
            // When pushed in a navigation stack, keep the default back button
            // and *supplement* it with the refresh button.
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItems = [refreshButton]
        }
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func mealAnalysisButtonTapped() {
        let events = buildEventsArray()
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)

        // Detect whether this controller is the root of its navigation stack.
        // If it is, we're in the modal presentation case.
        let isModalRoot = navigationController?.viewControllers.first === self

        if isModalRoot {
            // Modal quick-analysis: wrap in a UINavigationController and show "Klar".
            let analysisVC = MealAnalysisView(
                events: events,
                treatments: self.treatments,
                initialStart: start,
                modalWithTimestamp: true,
                modalTitleString: "Analys tid",
                showsDoneButton: true
            )
            analysisVC.delegate = self
            let navController = UINavigationController(rootViewController: analysisVC)
            navController.modalPresentationStyle = .formSheet
            present(navController, animated: true, completion: nil)
        } else {
            // Navigated from Settings: push onto the existing navigation stack,
            // hide the "Klar" button and rely on the back button instead.
            let analysisVC = MealAnalysisView(
                events: events,
                treatments: self.treatments,
                initialStart: start,
                modalWithTimestamp: true,
                modalTitleString: "Analys tid",
                showsDoneButton: false
            )
            analysisVC.delegate = self
            navigationController?.pushViewController(analysisVC, animated: true)
        }
    }

    private func buildEventsArray() -> [Event] {
        // note: -> Event? in the closure so `return nil` is allowed
        var events: [Event] = treatments.compactMap { treatment -> Event? in
            switch treatment.eventType {
            case "SMB", "Bolus":
                // parse insulin value as before…
                let amt: Double?
                if let v = treatment.rawData["insulin"] as? Double {
                    amt = v
                } else if let str = treatment.amount?
                            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression),
                          let v = Double(str) {
                    amt = v
                } else {
                    amt = nil
                }
                guard let amount = amt else { return nil }
                return Event(
                    date: treatment.timestamp,
                    eventType: treatment.eventType,
                    amount: amount,
                    foodType: nil
                )

            case "Carb Correction":
                // parse carb grams
                let amt: Double?
                if let v = treatment.rawData["carbs"] as? Double {
                    amt = v
                } else if let str = treatment.amount?
                            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression),
                          let v = Double(str) {
                    amt = v
                } else {
                    amt = nil
                }
                guard let amount = amt else { return nil }

                // **here**: grab the foodType from rawData (or nil)
                let foodType = treatment.rawData["foodType"] as? String

                return Event(
                    date: treatment.timestamp,
                    eventType: treatment.eventType,
                    amount: amount,
                    foodType: foodType
                )

            case "BG Check":
                // Map BG Check to Event, converting units to mmol if needed
                if let glucose = treatment.rawData["glucose"] as? Double {
                    let units = treatment.rawData["units"] as? String ?? ""
                    let mmol = units.lowercased().contains("mmol") ? glucose : glucose / 18.0
                    return Event(
                        date: treatment.timestamp,
                        eventType: "BG Check",
                        amount: mmol,
                        foodType: nil
                    )
                }
                return nil
                
            case "Site Change":
                // Map Site changes to Event
                    return Event(
                        date: treatment.timestamp,
                        eventType: "Site Change",
                        amount: 0.0,
                        foodType: nil
                    )

            default:
                return nil
            }
        }
        // Temp Basal → forward the *rate* (U/h) so MealAnalysisView can compute pulses.
        let tempBasals = treatments
            .filter { $0.eventType == "Temp Basal" }
            .sorted { $0.timestamp < $1.timestamp }

        for basal in tempBasals {
            // Use `rate` first, fall back to `absolute`, default 0.0
            let rate = (basal.rawData["rate"] as? Double) ??
                       (basal.rawData["absolute"] as? Double) ?? 0.0

            events.append(
                Event(
                    date: basal.timestamp,
                    eventType: "Temp Basal",
                    amount: rate,          // pass the basal *rate* in U/h
                    foodType: nil
                )
            )
        }
        return events
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
        // Trigger the same global refresh logic used in MainViewController
        NotificationCenter.default.post(name: NSNotification.Name("refresh"), object: nil)

        // Show local loading indicator
        showRefreshIndicator()

        // Reset picker to today
        selectedDate = Date()
        datePicker.setDate(selectedDate, animated: true)

        // Reload treatments after refresh has been triggered
        // (MainViewController will refresh Nightscout data; then we reload from cache)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.loadTreatments(for: self.selectedDate)
        }
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
        let segments = ["Alla", "Auto", "Manuell", "Övriga"]
        segmentedControl = UISegmentedControl(items: segments)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedControl)
        // Constraints added later via headerStack in setupConstraints()
    }
    
    @objc private func filterChanged() {
        tableView.reloadData()
        updateDuplicateIndicator()
    }
    
    // MARK: - Setup TableView
    
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        // Transparent table so ThemedViewController's gradient/background shows through
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.cellLayoutMarginsFollowReadableWidth = false
        view.addSubview(tableView)
        // Register the custom cell class so that cells are always .value1 style.
        tableView.register(Value1TableViewCell.self, forCellReuseIdentifier: "TreatmentCell")
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    // MARK: - Setup Constraints
    
    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide

        // --- Horizontal stack for date picker + segmented control ---
        let headerStack = UIStackView(arrangedSubviews: [datePicker, segmentedControl])
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        // Ensure the date picker shows its full content, let the segmented control shrink first
        datePicker.setContentHuggingPriority(.required, for: .horizontal)
        datePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        segmentedControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        segmentedControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Uniform compact heights (same as in MealAnalysisView)
        datePicker.heightAnchor.constraint(equalToConstant: 30).isActive = true
        segmentedControl.heightAnchor.constraint(equalToConstant: 30).isActive = true
        // Ensure the date text has room after we hid the calendar glyph
        datePicker.widthAnchor.constraint(lessThanOrEqualToConstant: 105).isActive = true

        NSLayoutConstraint.activate([
            // Pin headerStack at the top
            headerStack.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 8),
            headerStack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -8)
        ])

        // TableView below the headerStack
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadTreatments() {
        // For legacy/manual refresh, default to today
        loadTreatments(for: selectedDate)
    }

    /// Load treatments for a full calendar day from NightscoutCache or fall back to dynamic fetch
    private func loadTreatments(for date: Date) {
        let cal = Calendar.current

        let start: Date
        let end: Date

        if cal.isDate(date, inSameDayAs: Date()) {
            // Rolling window for “today”: match MainViewController’s chart window
            // (graphHours = 24 * downloadDays) up to now.
            let hours = 24 * max(1, UserDefaultsRepository.downloadDays.value)
            start = Date().addingTimeInterval(-Double(hours) * 60 * 60)
            end = Date()
        } else {
            // Specific calendar day window
            start = cal.startOfDay(for: date)
            end = cal.date(byAdding: .day, value: 1, to: start)!
        }

        // Visa alltid någon form av "loading" medan vi läser cachen.
        showRefreshIndicator()

        Task {
            // För alla datum (inkl. idag) försöker vi först läsa från NightscoutCache.
                let (sgvs, treatsJSON) = await NightscoutCache.loadWindow(from: start, to: end)
            let newTreatments = treatsJSON.compactMap { tjson in
                Treatment(dictionary: [
                    "_id":      tjson._id as AnyObject,
                    "eventType":tjson.eventType as AnyObject,
                    "enteredBy": tjson.enteredBy as AnyObject,
                    "created_at": ISO8601DateFormatter().string(from: tjson.created_at) as AnyObject,
                    "rate":     tjson.rate    as AnyObject,
                    "absolute": tjson.absolute as AnyObject,
                    "insulin":  tjson.insulin  as AnyObject,
                    "carbs":    tjson.carbs    as AnyObject,
                    "amount":   tjson.amount   as AnyObject,
                    "foodType": tjson.foodType as AnyObject,
                    "notes":    tjson.notes as AnyObject,
                    "glucose":  tjson.glucose as AnyObject,
                    "units":    tjson.units as AnyObject,
                    "duration": tjson.tempBasalDuration as AnyObject
                ])
            }
            
            // Bygg BG-punkter (mmol/L) från SGVs
                let newBGPoints: [BGPoint] = sgvs.map { sgv in
                    BGPoint(
                        date: Date(timeIntervalSince1970: sgv.date),
                        mmol: Double(sgv.sgv) / 18.0182
                    )
                }
                .sorted { $0.date < $1.date }

            DispatchQueue.main.async {
                if !newTreatments.isEmpty {
                    // Cache-data fanns – visa den och avsluta.
                    // NOTE: If "today" is selected, only SHOW entries from local midnight → now.
                    if cal.isDate(date, inSameDayAs: Date()) {
                        let todayStart = cal.startOfDay(for: Date())
                        let now = Date()
                        self.treatments = newTreatments
                            .filter { $0.timestamp >= todayStart && $0.timestamp <= now }
                            .sorted { $0.timestamp > $1.timestamp }
                    } else {
                        self.treatments = newTreatments.sorted { $0.timestamp > $1.timestamp }
                    }
                    
                    // Spara BG-punkterna när vi faktiskt använder cache-datan
                    self.bgPoints = newBGPoints
                    
                    self.tableView.reloadData()
                    self.hideRefreshIndicator()
                } else {
                    // Ingen cache-data för den här dagen: fall back till live-fetch.
                    // Stäng av nuvarande indikator, fallback-metoderna sköter sin egen show/hide.
                    self.hideRefreshIndicator()

                    if cal.isDate(date, inSameDayAs: Date()) {
                        // För "idag" använder vi en rolling-window-fall-back (matchar downloadDays).
                        self.fetchDynamicTreatmentsForToday24h()
                    } else {
                        // För andra dagar hämtar vi ett lokalt kalenderdygn.
                        self.fetchDynamicTreatments(for: date)
                    }
                }
            }
        }
    }

    /// Fallback: hämta de senaste N dagar (rolling window) för dagens datum direkt från Nightscout
    /// (används bara om cachen saknar data för idag).
    private func fetchDynamicTreatmentsForToday24h() {
        // Visa loading-indikator för nätverksanropet.
        showRefreshIndicator()

        let now = Date()
        let hours = 24 * max(1, UserDefaultsRepository.downloadDays.value)
        let since = now.addingTimeInterval(-Double(hours) * 60 * 60)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)

        let params: [String: String] = [
            "find[created_at][$gte]": iso.string(from: since),
            "find[created_at][$lte]": iso.string(from: now)
        ]

        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: params) { result in
            DispatchQueue.main.async {
                if case .success(let raw) = result,
                   let entries = raw as? [[String: AnyObject]] {
                    let fetched = entries.compactMap { Treatment(dictionary: $0) }

                    let cal = Calendar.current
                    let todayStart = cal.startOfDay(for: Date())
                    let now = Date()

                    // Only SHOW today's entries, even though we fetched a rolling window
                    self.treatments = fetched
                        .filter { $0.timestamp >= todayStart && $0.timestamp <= now }
                        .sorted { $0.timestamp > $1.timestamp }
                }
                self.tableView.reloadData()
                self.hideRefreshIndicator()
            }
        }
    }

    /// Fetch treatments dynamically for a specific calendar date (fallback if cache empty)
    private func fetchDynamicTreatments(for date: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        // Use system timezone so we cover the local day
        iso.timeZone = .current
        let params: [String: String] = [
            "find[created_at][$gte]": iso.string(from: start),
            "find[created_at][$lte]": iso.string(from: end)
        ]
        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: params) { result in
            DispatchQueue.main.async {
                if case .success(let raw) = result,
                   let entries = raw as? [[String: AnyObject]] {
                    let fetched = entries.compactMap { Treatment(dictionary: $0) }
                    self.treatments = fetched.sorted { $0.timestamp > $1.timestamp }
                }
                self.tableView.reloadData()
                // Ingen hideRefreshIndicator här – det sköts av loadTreatments(for:)
            }
        }
    }

    @objc private func dateChanged(_ sender: UIDatePicker) {
        selectedDate = sender.date
        loadTreatments(for: selectedDate)
    }
    
    @objc private func refreshTreatments(_ sender: UIRefreshControl) {
        loadTreatments()
        // End refreshing after data is loaded; you might also call this in the completion of loadTreatments()
        sender.endRefreshing()
    }
    
    // MARK: - MealAnalysisViewDelegate
    func mealAnalysisView(_ controller: MealAnalysisView,
                          didReturnWithStartDate startDate: Date,
                          didVisitEnteredBy: Bool) {
        let cal = Calendar.current
        let newDay = cal.startOfDay(for: startDate)
        let oldDay = cal.startOfDay(for: selectedDate)
        
        let dateChanged = !cal.isDate(oldDay, inSameDayAs: newDay)
        
        // 1) Alltid synka valt datum från MealAnalysisView → TreatmentsTableView
        selectedDate = newDay
        datePicker.setDate(selectedDate, animated: false)
        loadTreatments(for: selectedDate)
        
        // 2) Om användaren varit inne i EnteredByView, sätt filtret till "Manuell"
        if didVisitEnteredBy {
            let manualIndex = (0..<segmentedControl.numberOfSegments).first {
                segmentedControl.titleForSegment(at: $0) == "Manuell"
            } ?? 2
            
            segmentedControl.selectedSegmentIndex = manualIndex
            filterChanged()
        }
        
        // 3) Visa overlay endast om datumet faktiskt ändrades
        if dateChanged {
            showDateSyncOverlay(message: "Datumvalet från föregående vy följde med till denna vy")
        }
    }
    
    // MARK: - BG helpers for meal status

    /// Hittar BG-punkten som ligger närmast i tid till target, givet att bgPoints är sorterade på date.
    /// Om maxDelta anges, returnerar nil om närmaste punkt ligger längre bort än maxDelta.
    private func nearestBGPoint(around target: Date,
                                in points: [BGPoint],
                                maxDelta: TimeInterval? = nil) -> BGPoint? {
        guard !points.isEmpty else { return nil }
        var lo = 0
        var hi = points.count - 1
        var bestIndex = 0
        var bestDiff = abs(points[0].date.timeIntervalSince(target))

        while lo <= hi {
            let mid = (lo + hi) / 2
            let d = points[mid].date
            let diff = abs(d.timeIntervalSince(target))
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = mid
            }
            if d < target {
                lo = mid + 1
            } else if d > target {
                hi = mid - 1
            } else {
                break
            }
        }
        
        if let maxDelta = maxDelta, bestDiff > maxDelta {
            return nil
        }
        return points[bestIndex]
    }

    /// Låg / ok / hög-symbol för en Kh-måltid, baserat på BG ~3h efter.
    /// Om ingen BG finns inom ±30 min runt +3h visas "–".
    private func statusSymbolForCarbMeal(at mealDate: Date) -> String {
        guard !bgPoints.isEmpty else { return "–" }

        // Target time = 3h efter måltid
        let target = mealDate.addingTimeInterval(3 * 60 * 60)

        // Tillåt max ±30 minuter från target
        let maxDelta: TimeInterval = 30 * 60
        
        guard let point = nearestBGPoint(around: target, in: bgPoints, maxDelta: maxDelta) else {
            // Ingen BG tillräckligt nära target → kan inte utvärdera ännu
            return "⏳"
        }

        let endBG = point.mmol
        let endMgdl = endBG * 18.0182
        let lowMgdl = Double(UserDefaultsRepository.lowLine.value)
        let highMgdl = Double(UserDefaultsRepository.highLine.value)

        if endMgdl > highMgdl {
            return "🟣"
        } else if endMgdl < lowMgdl {
            return "🔴"
        } else {
            return "🟢"
        }
    }
    
    // MARK: - UITableViewDataSource Methods
    
    private func previewOverrideText(for text: String) -> String {
        if text.count > 19 {
            return String(text.prefix(19)) + "…"
        } else {
            return text
        }
    }
    
    private func previewCarbsText(for text: String) -> String {
        if text.count > 6 {
            return String(text.prefix(6)) + "…"
        } else {
            return text
        }
    }
    
    private func previewNoteText(for text: String) -> String {
        if text.count > 28 {
            return String(text.prefix(28)) + "…"
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
    private func symbolForEventType(_ eventType: String, foodType: String? = nil, fullNote: String? = nil) -> (name: String, color: UIColor) {
        // Identifiera Dextro via foodType som innehåller 🍬
        let isDextro = (foodType ?? "").contains("🍬")
        
        if eventType == "Carb Correction" {
            // Dextro / lågbehandling som registrerats som Carb Correction men har 🍬 i foodType
            if isDextro {
                return ("circle.fill", .white)
            }
            // Om foodType är tomt → Fett & Protein (brun), annars vanlig Kh (orange)
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
        case "Dextro":
            // Dextro / lågbehandling – egen färg
            return ("circle.fill", .white)
        case "Kolhydrater", "Måltid":
            // Om foodType råkar innehålla 🍬 här också, använd samma Dextro-färg.
            if isDextro {
                return ("circle.fill", .white)
            } else {
                return ("circle.fill", .systemOrange.withAlphaComponent(0.8))
            }
        case "BG Check":
            return ("circle.fill", .systemRed.withAlphaComponent(1.0))
        case "Exercise":
            return ("circle.fill", .systemPurple.withAlphaComponent(0.7))
        case "Note", "Announcement":
            // Use the full note text from rawData to determine the symbol.
            if let noteText = fullNote, noteText.contains("Justerad") || noteText.contains("ändrades") {
                return ("gearshape.circle.fill", .label.withAlphaComponent(0.5))
            } else if let noteText = fullNote, noteText.contains("PumpSuspend") {
                return ("pause.circle.fill", .systemTeal.withAlphaComponent(0.75))
            } else if let noteText = fullNote, noteText.contains("PumpResume") {
                return ("play.circle.fill", .systemTeal.withAlphaComponent(0.75))
            } else if let noteText = fullNote, noteText.contains("Trio startades om") {
                return ("repeat.circle.fill", .label.withAlphaComponent(0.5))
            } else {
                return ("circle.fill", .label.withAlphaComponent(0.5))
            }
        case "Site Change", "Insulin Change", "Sensor Start", "Sensor Change", "Sensorbyte", "Sensorstart":
            return ("repeat.circle.fill", .systemTeal.withAlphaComponent(0.75))
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
        // Ensure cell is truly transparent (iOS 14+ uses backgroundConfiguration)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.backgroundView = nil
        cell.selectedBackgroundView = nil
        
        let treatment = filteredTreatments[indexPath.row]
        // Check if this override is pending upload
        var isPendingUpload = false
        if treatment.eventType == "Exercise" {
            let pending = NightscoutUtils.loadPendingUploadDocuments()
            if let notes = treatment.overrideNotes,
               pending.contains(where: { ($0["notes"] as? String) == notes }) {
                isPendingUpload = true
            }
        }
        
        // Determine display event type with special handling for Carb Correction.
        let displayEventType: String = {
            if treatment.eventType == "Carb Correction" {
                if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                    return "Kh"
                } else {
                    return "Fett & Protein"
                }
            } else if treatment.eventType == "Site Change" {
                return "Poddbyte"
            } else if treatment.eventType == "Insulin Change" {
                return "Nytt insulin"
            } else if treatment.eventType == "Sensor Start" {
                return "Sensorbyte"
            } else {
                return treatment.eventType
            }
        }()
        
        // Statussymbol för måltider (Kh) baserat på BG ca 3h efter
        let mealStatusSymbol: String
        if displayEventType == "Kh" {
            mealStatusSymbol = statusSymbolForCarbMeal(at: treatment.timestamp)
        } else {
            mealStatusSymbol = ""
        }
        
        // Handle different treatment types.
        if treatment.eventType == "BG Check" {
            if let glucose = treatment.rawData["glucose"] as? Double,
               let units = treatment.rawData["units"] as? String {
                let mmol = units.lowercased().contains("mmol") ? glucose : glucose / 18.0
                cell.textLabel?.text = "Fingerstick • \(String(format: "%.1f", mmol)) mmol/L"
            } else {
                cell.textLabel?.text = displayEventType
            }
            cell.accessoryType = .none
            
        } else if treatment.eventType == "Temporary Override" ||
                    treatment.eventType == "Exercise" ||
                    treatment.eventType == "Override" {
            var baseText: String
            if let notes = treatment.overrideNotes {
                let preview = previewOverrideText(for: notes)
                if let duration = treatment.overrideDuration {
                    baseText = duration > 1439 ? "\(preview) • Tillsvidare" : "\(preview) • \(Int(duration)) m"
                } else {
                    baseText = preview
                }
            } else {
                baseText = displayEventType
            }

            if isPendingUpload {
                // Orange cloud/arrow symbol for pending upload
                let symbol = "🔂 "
                cell.textLabel?.text = symbol + baseText
            } else {
                cell.textLabel?.text = baseText
            }

            cell.accessoryType = .none
            
        } else if treatment.eventType == "Carb Correction" {
            // For Carb Correction, we display the amount and a processed foodType (if available).
            let mainText = treatment.amount != nil ? "\(displayEventType) • \(treatment.amount!)" : displayEventType
            if let foodType = treatment.rawData["foodType"] as? String, !foodType.isEmpty {
                let cleanedFoodType = foodType.replacingOccurrences(of: "\u{FE0F}", with: "")
                let preview = previewCarbsText(for: cleanedFoodType)
                cell.textLabel?.text = mainText + " • " + preview
                cell.textLabel?.font = .systemFont(ofSize: 17)
                cell.textLabel?.numberOfLines = 0
            } else {
                cell.textLabel?.text = mainText
            }
            cell.accessoryType = .none
            
        } else if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let note = treatment.rawData["notes"] as? String {
                // Create regex patterns for the replacements.
                let resumePattern = "PumpResume"
                let suspendPattern = "PumpSuspend"
                var modifiedNote = note

                // Replace "PumpResume" with "Pump startades".
                if let resumeRegex = try? NSRegularExpression(pattern: resumePattern, options: []) {
                    let range = NSRange(location: 0, length: modifiedNote.utf16.count)
                    modifiedNote = resumeRegex.stringByReplacingMatches(in: modifiedNote, options: [], range: range, withTemplate: "Pump startades")
                }
                // Replace "PumpSuspend" with "Pump pausades".
                if let suspendRegex = try? NSRegularExpression(pattern: suspendPattern, options: []) {
                    let range = NSRange(location: 0, length: modifiedNote.utf16.count)
                    modifiedNote = suspendRegex.stringByReplacingMatches(in: modifiedNote, options: [], range: range, withTemplate: "Pump pausades")
                }

                let preview = previewNoteText(for: modifiedNote)
                cell.textLabel?.text = preview
            } else {
                cell.textLabel?.text = displayEventType
            }
            
        } else if treatment.eventType == "Temp Basal" {
            if let duration = treatment.tempBasalDuration, let amount = treatment.amount {
                cell.textLabel?.text = "\(treatment.eventType) • \(amount) • \(Int(duration)) m"
            } else {
                cell.textLabel?.text = treatment.eventType
            }
            cell.accessoryType = .none
            
        } else {
            // For all other treatments.
            if treatment.eventType == "Bolus" {
                let mainText = treatment.amount != nil ? "\(displayEventType) • \(treatment.amount!)" : displayEventType
                cell.textLabel?.text = mainText
                cell.accessoryType = .none
            } else {
                // Default display for any other event.
                if let amount = treatment.amount {
                    cell.textLabel?.text = "\(displayEventType) • \(amount)"
                } else {
                    cell.textLabel?.text = displayEventType
                }
                cell.accessoryType = .none
            }
        }
        
        // Format the timestamp as HH:mm och visa den i en separat trailing-view
        // tillsammans med status-symbolen så att symbolerna kan alignas lodrätt.
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: treatment.timestamp)

        // Använd monospaced digits för att alla tider ska ta samma horisontella utrymme.
        let baseFontSize = cell.detailTextLabel?.font.pointSize
            ?? UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: baseFontSize, weight: .regular)
        let statusFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        // Mått för den lilla "kolumnen" med status-emoji + tid.
        let timeWidth: CGFloat = 50      // räcker för "00:00"
        let symbolWidth: CGFloat = 13    // lagom för en emoji
        let spacing: CGFloat = 2
        let height: CGFloat = timeFont.lineHeight

        let containerWidth = symbolWidth + spacing + timeWidth
        let containerHeight = height
        let trailingTag = 9991

        // Ta bort eventuell tidigare trailing-view (återanvända celler)
        if let old = cell.contentView.viewWithTag(trailingTag) {
            old.removeFromSuperview()
        }

        let container = UIView(frame: .zero)
        container.tag = trailingTag
        container.backgroundColor = .clear

        let statusLabel = UILabel(frame: CGRect(x: 0, y: 0, width: symbolWidth, height: containerHeight))
        statusLabel.text = mealStatusSymbol
        statusLabel.font = statusFont
        statusLabel.textAlignment = .right
        statusLabel.textColor = .label
        statusLabel.backgroundColor = .clear

        let timeLabel = UILabel(frame: CGRect(x: symbolWidth + spacing, y: 0, width: timeWidth, height: containerHeight))
        timeLabel.text = timeString
        timeLabel.font = timeFont
        timeLabel.textAlignment = .right
        timeLabel.textColor = .label
        timeLabel.backgroundColor = .clear

        container.addSubview(statusLabel)
        container.addSubview(timeLabel)

        // Positionera containern längst till höger i cellens contentView
        let contentBounds = cell.contentView.bounds
        let originX = contentBounds.width - containerWidth - tableView.separatorInset.right
        let originY = (contentBounds.height - containerHeight) / 2.0
        container.frame = CGRect(x: originX, y: originY, width: containerWidth, height: containerHeight)
        container.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]

        cell.contentView.addSubview(container)
        cell.detailTextLabel?.text = nil
        
        // Determine symbol and color.
        let symbolInfo: (name: String, color: UIColor) = {
            if treatment.eventType == "Carb Correction" {
                let foodType = treatment.rawData["foodType"] as? String
                return symbolForEventType(treatment.eventType, foodType: foodType)
            } else if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
                let fullNote = treatment.rawData["notes"] as? String
                return symbolForEventType(treatment.eventType, fullNote: fullNote)
            } else {
                return symbolForEventType(treatment.eventType)
            }
        }()
        if let image = UIImage(systemName: symbolInfo.name) {
            cell.imageView?.image = image
            cell.imageView?.tintColor = symbolInfo.color
        }
        
        cell.selectionStyle = .default
        // Subtle selection highlight that still shows the gradient
        let selected = UIView()
        selected.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        selected.layer.cornerRadius = 10
        selected.layer.masksToBounds = true
        cell.selectedBackgroundView = selected
        
        // Check for duplicates: only count duplicates that have the same timestamp and event type (excluding "Note").
        let duplicateCount = filteredTreatments.filter {
            $0.timestamp == treatment.timestamp &&
            $0.eventType == treatment.eventType &&
            $0.eventType != "Note"
        }.count
        
        if treatment.eventType == "Exercise", let duration = treatment.overrideDuration {
            let exerciseEndTime = treatment.timestamp.addingTimeInterval(duration * 60)
            if Date() < exerciseEndTime {
                cell.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.3)
                cell.contentView.backgroundColor = cell.backgroundColor
            } else {
                cell.backgroundColor = (duplicateCount > 1)
                    ? UIColor.systemRed.withAlphaComponent(0.3)
                    : UIColor.clear
                cell.contentView.backgroundColor = cell.backgroundColor
            }
        } else if treatment.eventType == "Temp Basal" {
            let cal = Calendar.current

            // Only highlight the newest Temp Basal when we're viewing "today".
            if cal.isDate(selectedDate, inSameDayAs: Date()) {
                // Find the newest Temp Basal that occurred today (rolling window may include yesterday).
                let newestTempBasalToday = treatments
                    .filter { $0.eventType == "Temp Basal" && cal.isDate($0.timestamp, inSameDayAs: Date()) }
                    .max(by: { $0.timestamp < $1.timestamp })

                if let newest = newestTempBasalToday,
                   treatment.timestamp == newest.timestamp {
                    cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
                    cell.contentView.backgroundColor = cell.backgroundColor
                } else {
                    cell.backgroundColor = (duplicateCount > 1)
                        ? UIColor.systemRed.withAlphaComponent(0.3)
                        : UIColor.clear
                    cell.contentView.backgroundColor = cell.backgroundColor
                }
            } else {
                // Not viewing today: never apply the blue "newest" highlight.
                cell.backgroundColor = (duplicateCount > 1)
                    ? UIColor.systemRed.withAlphaComponent(0.3)
                    : UIColor.clear
                cell.contentView.backgroundColor = cell.backgroundColor
            }
        } else {
            cell.backgroundColor = (duplicateCount > 1 && treatment.eventType != "Note")
                ? UIColor.systemRed.withAlphaComponent(0.3)
                : UIColor.clear
            cell.contentView.backgroundColor = cell.backgroundColor
        }

        
        return cell
    }
    
    // MARK: - Swipe to Delete (Editing Style)
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let treatment = filteredTreatments[indexPath.row]
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "HH:mm"
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
                                self.removeTreatmentFromCache(treatment)
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
                            LogManager.shared.log(category: .treatments, message: "Failed to delete treatment: \(error.localizedDescription)", isDebug: true)
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
                        displayEventName = "Fett & Protein"
                    }
                } else if treatment.eventType == "Note" {
                    displayEventName = "Notering"
                } else if treatment.eventType == "Exercise" {
                    displayEventName = "Override"
                } else if treatment.eventType == "Site Change" {
                    displayEventName = "Poddbyte"
                } else {
                    displayEventName = treatment.eventType
                }
                
                let message = "\nVill du verkligen radera:\n \(displayEventName) • \(timeString)?\n\n(OBS! Detta raderar INTE något i Trio)"
                let alert = UIAlertController(title: "Radera i Nightscout?", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))
                alert.addAction(UIAlertAction(title: "Radera", style: .destructive, handler: { _ in
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
                                self.removeTreatmentFromCache(treatment)
                                self.tableView.reloadData()
                                self.updateDuplicateIndicator()
                            }
                        case .failure(let error):
                            DispatchQueue.main.async {
                                let failureAlert = UIAlertController(
                                    title: "Kunde inte radera!",
                                    message: "\nKontrollera att du har skrivåtkomst i din Nightscout token",
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
        
        // Edit actions for updating duration on Exercise (Override) treatments
        // and editing note text for Note treatments, and editing glucose for BG Check.
        var actions: [UIContextualAction] = []

        if treatment.eventType == "Exercise" {
            let editAction = UIContextualAction(style: .normal, title: nil) { (action, view, completionHandler) in
                // Current duration in minutes (integer)
                let currentDuration = Int(treatment.overrideDuration ?? 0)

                let alert = UIAlertController(
                    title: "Ändra override-varaktighet i Nightscout",
                    message: "\nAnge ny längd i minuter\n\n(OBS! Detta ändrar INTE något i Trio)",
                    preferredStyle: .alert
                )

                alert.addTextField { textField in
                    textField.keyboardType = .numberPad
                    if currentDuration > 0 {
                        textField.text = String(currentDuration)
                    }
                }

                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))

                alert.addAction(UIAlertAction(title: "Spara ändring", style: .default, handler: { _ in
                    guard let text = alert.textFields?.first?.text,
                          let newDurationInt = Int(text),
                          newDurationInt > 0 else {
                        completionHandler(false)
                        return
                    }

                    guard let treatmentId = treatment.documentId else {
                        self.showAlert(title: "Fel", message: "Saknar dokument-ID för behandlingen") { }
                        completionHandler(false)
                        return
                    }

                    // 1) Hämta aktuellt Nightscout-dokument
                    NightscoutUtils.fetchTreatmentById(treatmentId) { result in
                        switch result {
                        case .failure(let error):
                            self.showAlert(title: "Fel", message: error.localizedDescription) { }
                            completionHandler(false)
                        case .success(var doc):
                            // Ta bort _id så att Nightscout/MongoDB själv får skapa ett nytt ObjectId
                            doc.removeValue(forKey: "_id")

                            // Uppdatera duration i dokumentet
                            doc["duration"] = newDurationInt

                            // 2) Radera befintlig post
                            NightscoutUtils.executeDeleteRequest(treatmentId: treatmentId) { deleteResult in
                                switch deleteResult {
                                case .failure(let error):
                                    self.showAlert(title: "Kunde inte radera", message: error.localizedDescription) { }
                                    completionHandler(false)
                                case .success(_):
                                    // 3) Posta om samma treatment med uppdaterad duration (utan _id)
                                    Task {
                                        do {
                                            // Försök posta om overriden och få tillbaka det skapade dokumentet (med nytt _id).
                                            let createdDoc = try await NightscoutUtils.executePostRequestRaw(eventType: .treatments, body: doc)

                                            DispatchQueue.main.async {
                                                // Ta bort den gamla raden lokalt; den nya raden kommer ha ett nytt _id
                                                if let index = self.treatments.firstIndex(where: { $0.documentId == treatment.documentId }) {
                                                    let removed = self.treatments.remove(at: index)
                                                    self.removeTreatmentFromCache(removed)

                                                    // Om Nightscout svarade med det nya dokumentet, lägg in det direkt i listan
                                                    // och uppdatera cache-filen för rätt dag.
                                                    if let createdDoc = createdDoc,
                                                       let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                        self.treatments.insert(newTreatment, at: index)
                                                        NightscoutCache.upsertTreatment(from: createdDoc)
                                                    }
                                                } else {
                                                    // Hittade inte den gamla raden, försök ändå lägga in den nya överst.
                                                    if let createdDoc = createdDoc,
                                                       let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                        self.treatments.insert(newTreatment, at: 0)
                                                        NightscoutCache.upsertTreatment(from: createdDoc)
                                                    }
                                                }

                                                self.tableView.reloadData()
                                                self.updateDuplicateIndicator()
                                                completionHandler(true)
                                            }
                                        } catch {
                                            // Om uppladdningen misslyckas, lägg dokumentet i pending-kön för retry
                                            NightscoutUtils.addPendingUploadDocument(doc)

                                            DispatchQueue.main.async {
                                                self.showAlert(
                                                    title: "Kunde inte spara",
                                                    message: "\nOverride kunde inte laddas upp just nu. Den kommer att laddas upp automatiskt nästa gång Behandlingslogg öppnas."
                                                ) { }
                                                completionHandler(false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }))

                self.present(alert, animated: true, completion: nil)
            }

            editAction.image = UIImage(systemName: "pencil")
            editAction.backgroundColor = .systemBlue

            actions = [deleteAction, editAction]

        } else if treatment.eventType == "Note" {
            let editNoteAction = UIContextualAction(style: .normal, title: nil) { (action, view, completionHandler) in
                // Current notes text
                let currentNotes = (treatment.rawData["notes"] as? String) ?? ""

                let alert = UIAlertController(
                    title: "Ändra noteringstext i Nightscout",
                    message: "\nRedigera texten nedan\n\n(OBS! Detta ändrar INTE något i Trio)",
                    preferredStyle: .alert
                )

                alert.addTextField { textField in
                    textField.keyboardType = .default
                    textField.autocapitalizationType = .sentences
                    textField.text = currentNotes
                }

                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))

                alert.addAction(UIAlertAction(title: "Spara ändring", style: .default, handler: { _ in
                    guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else {
                        completionHandler(false)
                        return
                    }

                    guard let treatmentId = treatment.documentId else {
                        self.showAlert(title: "Fel", message: "Saknar dokument-ID för behandlingen") { }
                        completionHandler(false)
                        return
                    }

                    // 1) Hämta aktuellt Nightscout-dokument
                    NightscoutUtils.fetchTreatmentById(treatmentId) { result in
                        switch result {
                        case .failure(let error):
                            self.showAlert(title: "Fel", message: error.localizedDescription) { }
                            completionHandler(false)
                        case .success(var doc):
                            // Ta bort _id så att Nightscout/MongoDB själv får skapa ett nytt ObjectId
                            doc.removeValue(forKey: "_id")

                            // Uppdatera notes i dokumentet
                            doc["notes"] = text

                            // 2) Radera befintlig post
                            NightscoutUtils.executeDeleteRequest(treatmentId: treatmentId) { deleteResult in
                                switch deleteResult {
                                case .failure(let error):
                                    self.showAlert(title: "Kunde inte radera", message: error.localizedDescription) { }
                                    completionHandler(false)
                                case .success(_):
                                    // 3) Posta om samma treatment med uppdaterad notes (utan _id)
                                    Task {
                                        do {
                                            let createdDoc = try await NightscoutUtils.executePostRequestRaw(eventType: .treatments, body: doc)

                                            DispatchQueue.main.async {
                                                // Ta bort den gamla raden lokalt
                                                if let index = self.treatments.firstIndex(where: { $0.documentId == treatment.documentId }) {
                                                    let removed = self.treatments.remove(at: index)
                                                    self.removeTreatmentFromCache(removed)

                                                // Lägg in den nya raden direkt om vi fick tillbaka dokumentet
                                                // och uppdatera cache-filen för rätt dag.
                                                if let createdDoc = createdDoc,
                                                   let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                    self.treatments.insert(newTreatment, at: index)
                                                    NightscoutCache.upsertTreatment(from: createdDoc)
                                                }
                                                } else {
                                                // Om vi inte hittade den, lägg den nya överst som fallback
                                                if let createdDoc = createdDoc,
                                                   let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                    self.treatments.insert(newTreatment, at: 0)
                                                    NightscoutCache.upsertTreatment(from: createdDoc)
                                                }
                                                }

                                                self.tableView.reloadData()
                                                self.updateDuplicateIndicator()
                                                completionHandler(true)
                                            }
                                        } catch {
                                            // Om uppladdningen misslyckas, lägg dokumentet i pending-kön för retry
                                            NightscoutUtils.addPendingUploadDocument(doc)

                                            DispatchQueue.main.async {
                                                self.showAlert(
                                                    title: "Kunde inte spara",
                                                    message: "\nNoteringen kunde inte laddas upp just nu. Den kommer att laddas upp automatiskt nästa gång Behandlingslogg öppnas."
                                                ) { }
                                                completionHandler(false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }))

                self.present(alert, animated: true, completion: nil)
            }

            editNoteAction.image = UIImage(systemName: "pencil")
            editNoteAction.backgroundColor = .systemBlue

            actions = [deleteAction, editNoteAction]

        } else if treatment.eventType == "BG Check" {
            let editBGAction = UIContextualAction(style: .normal, title: nil) { (action, view, completionHandler) in
                // Current glucose value
                let currentGlucose = (treatment.rawData["glucose"] as? Double) ?? 0.0

                let alert = UIAlertController(
                    title: "Ändra fingerstick-värde i Nightscout",
                    message: "\nAnge nytt blodsockervärde (mmol/L)\n\n(OBS! Detta ändrar INTE något i Trio)",
                    preferredStyle: .alert
                )

                alert.addTextField { textField in
                    textField.keyboardType = .decimalPad
                    if currentGlucose > 0 {
                        textField.text = String(format: "%.1f", currentGlucose)
                    }
                }

                alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel, handler: { _ in
                    completionHandler(false)
                }))

                alert.addAction(UIAlertAction(title: "Spara ändring", style: .default, handler: { _ in
                    guard let text = alert.textFields?.first?.text?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else {
                        completionHandler(false)
                        return
                    }

                    // Tillåt både komma och punkt som decimalavskiljare
                    let normalized = text.replacingOccurrences(of: ",", with: ".")
                    guard let newGlucose = Double(normalized), newGlucose > 0 else {
                        completionHandler(false)
                        return
                    }

                    guard let treatmentId = treatment.documentId else {
                        self.showAlert(title: "Fel", message: "Saknar dokument-ID för behandlingen") { }
                        completionHandler(false)
                        return
                    }

                    // 1) Hämta aktuellt Nightscout-dokument
                    NightscoutUtils.fetchTreatmentById(treatmentId) { result in
                        switch result {
                        case .failure(let error):
                            self.showAlert(title: "Fel", message: error.localizedDescription) { }
                            completionHandler(false)
                        case .success(var doc):
                            // Ta bort _id så att Nightscout/MongoDB själv får skapa ett nytt ObjectId
                            doc.removeValue(forKey: "_id")

                            // Uppdatera glucose i dokumentet (i mmol/L)
                            doc["glucose"] = newGlucose

                            // 2) Radera befintlig post
                            NightscoutUtils.executeDeleteRequest(treatmentId: treatmentId) { deleteResult in
                                switch deleteResult {
                                case .failure(let error):
                                    self.showAlert(title: "Kunde inte radera", message: error.localizedDescription) { }
                                    completionHandler(false)
                                case .success(_):
                                    // 3) Posta om samma treatment med uppdaterat fingerstickvärde (utan _id)
                                    Task {
                                        do {
                                            let createdDoc = try await NightscoutUtils.executePostRequestRaw(eventType: .treatments, body: doc)

                                            DispatchQueue.main.async {
                                                // Ta bort den gamla raden lokalt
                                                if let index = self.treatments.firstIndex(where: { $0.documentId == treatment.documentId }) {
                                                    let removed = self.treatments.remove(at: index)
                                                    self.removeTreatmentFromCache(removed)

                                                // Lägg in den nya raden direkt om vi fick tillbaka dokumentet
                                                // och uppdatera cache-filen för rätt dag.
                                                if let createdDoc = createdDoc,
                                                   let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                    self.treatments.insert(newTreatment, at: index)
                                                    NightscoutCache.upsertTreatment(from: createdDoc)
                                                }
                                                } else {
                                                // Om vi inte hittade den, lägg den nya överst som fallback
                                                if let createdDoc = createdDoc,
                                                   let newTreatment = Treatment(dictionary: createdDoc as [String : AnyObject]) {
                                                    self.treatments.insert(newTreatment, at: 0)
                                                    NightscoutCache.upsertTreatment(from: createdDoc)
                                                }
                                                }

                                                self.tableView.reloadData()
                                                self.updateDuplicateIndicator()
                                                completionHandler(true)
                                            }
                                        } catch {
                                            // Om uppladdningen misslyckas, lägg dokumentet i pending-kön för retry
                                            NightscoutUtils.addPendingUploadDocument(doc)

                                            DispatchQueue.main.async {
                                                self.showAlert(
                                                    title: "Kunde inte spara",
                                                    message: "\nFingerstick-värdet kunde inte laddas upp just nu. Det kommer att laddas upp automatiskt nästa gång Behandlingslogg öppnas."
                                                ) { }
                                                completionHandler(false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }))

                self.present(alert, animated: true, completion: nil)
            }

            editBGAction.image = UIImage(systemName: "pencil")
            editBGAction.backgroundColor = .systemBlue

            actions = [deleteAction, editBGAction]

        } else {
            actions = [deleteAction]
        }

        // Set the trashcan SF Symbol and customize appearance.
        deleteAction.image = UIImage(systemName: "trash")
        deleteAction.backgroundColor = .red

        let configuration = UISwipeActionsConfiguration(actions: actions)
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
            dateFormatter.locale = Locale(identifier: "sv_SE")
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
                LogManager.shared.log(category: .treatments, message: "Failed to encode URL string", isDebug: true)
                return
            }
            // Define callback URLs.
            let successCallback = "loop://completed"
            let errorCallback = "loop://error"
            let cancelCallback = "loop://cancel"
            
            guard let successEncoded = successCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let errorEncoded = errorCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let cancelEncoded = cancelCallback.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                LogManager.shared.log(category: .treatments, message: "Failed to encode callback URLs", isDebug: true)
                return
            }
            
            let urlString = "shortcuts://x-callback-url/run-shortcut?name=Remote%20Delete&input=text&text=\(encodedString)&x-success=\(successEncoded)&x-error=\(errorEncoded)&x-cancel=\(cancelEncoded)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            LogManager.shared.log(category: .treatments, message: "Waiting for shortcut completion...", isDebug: true)
        } else {
            // For SMS API, first show a confirmation alert with authentication.
            showRemoteDeleteConfirmationAlert(combinedString: combinedString)
        }
    }

    /// Presents a confirmation alert for SMS deletion. If the user selects "Ja", we authenticate first.
    private func showRemoteDeleteConfirmationAlert(combinedString: String) {
        let confirmationAlert = UIAlertController(
            title: "Bekräfta radering",
            message: "\nÄr du säker på att du vill radera måltiden i Trio?",
            preferredStyle: .alert)
        
        confirmationAlert.addAction(UIAlertAction(title: "Radera", style: .destructive, handler: { _ in
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
                    self.showAlert(title: "Lyckades!", message: "\nMeddelandet levererades") { }
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
                            LogManager.shared.log(category: .treatments, message: "Authentication failed: \(authenticationError?.localizedDescription ?? "unknown error")", isDebug: true)
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
                    LogManager.shared.log(category: .treatments, message: "Authentication failed: \(error?.localizedDescription ?? "unknown error")", isDebug: true)
                    self.handleAlertDismissal()
                }
            }
        }
    }


    // MARK: - Shortcut Callback Handlers (without dismissing the view)

    @objc private func handleShortcutSuccess() {
        LogManager.shared.log(category: .treatments, message: "Shortcut succeeded", isDebug: true)
        AudioServicesPlaySystemSound(SystemSoundID(1322))
        showAlert(title: NSLocalizedString("Lyckades", comment: "Lyckades"),
                  message: NSLocalizedString("\nMeddelandet levererades", comment: "Meddelandet levererades"),
                  completion: { /* No dismissal here */ })
    }

    @objc private func handleShortcutError() {
        LogManager.shared.log(category: .treatments, message: "Shortcut failed, showing error alert...", isDebug: true)
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Misslyckades", comment: "Misslyckades"),
                  message: NSLocalizedString("\nEtt fel uppstod när genvägen skulle köras. Du kan försöka igen.", comment: "Ett fel uppstod när genvägen skulle köras. Du kan försöka igen."),
                  completion: { /* Re-enable send button if needed */ })
    }

    @objc private func handleShortcutCancel() {
        LogManager.shared.log(category: .treatments, message: "Shortcut was cancelled, showing cancellation alert...", isDebug: true)
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Avbröts", comment: "Avbröts"),
                  message: NSLocalizedString("\nGenvägen avbröts innan den körts färdigt. Du kan försöka igen.", comment: "Genvägen avbröts innan den körts färdigt. Du kan försöka igen."),
                  completion: { /* Re-enable send button if needed */ })
    }

    @objc private func handleShortcutPasscode() {
        LogManager.shared.log(category: .treatments, message: "Shortcut was cancelled due to wrong passcode, showing passcode alert...", isDebug: true)
        AudioServicesPlaySystemSound(SystemSoundID(1053))
        showAlert(title: NSLocalizedString("Fel lösenkod", comment: "Fel lösenkod"),
                  message: NSLocalizedString("\nGenvägen avbröts pga fel lösenkod. Du kan försöka igen.", comment: "Genvägen avbröts pga fel lösenkod. Du kan försöka igen."),
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
        // For example, re-enable any disabled buttons; here we simply log.
        LogManager.shared.log(category: .treatments, message: "Alert dismissed, re-enabling controls if needed.", isDebug: true)
    }

    
    // MARK: - UITableViewDelegate Methods
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        
        let treatment = filteredTreatments[indexPath.row]
        
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "sv_SE")
        timeFormatter.dateFormat = "dd MMM HH:mm:ss"
        let timeString = timeFormatter.string(from: treatment.timestamp)

        // Nightscout meta: who created the treatment
        let enteredByValue: String? = {
            if let v = treatment.rawData["enteredBy"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
            // Some NS setups / middleware may use different casing
            if let v = treatment.rawData["entered_by"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
            if let v = treatment.rawData["EnteredBy"] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
            return nil
        }()

        func withEnteredBy(_ base: String) -> String {
            guard let enteredBy = enteredByValue else { return base }
            return base + "\n\nInlagt av: \(enteredBy)"
        }

        func presentAlert(title: String, message: String) {
            //let alert = UIAlertController(title: title, message: withEnteredBy(message), preferredStyle: .alert)
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                tableView.deselectRow(at: indexPath, animated: true)
            })
            present(alert, animated: true)
        }
        
        if treatment.eventType == "SMB" || treatment.eventType == "Temp Basal" {
            let adjustedTimestamp = treatment.timestamp.addingTimeInterval(30)
            NightscoutUtils.fetchDeviceStatusReasonBeforeTimestamp(timestamp: adjustedTimestamp) { result in
                switch result {
                case .success(let reason):
                    let formattedReason = self.formatReason(reason)
                    presentAlert(title: "Trio behandlingsbeslut", message: formattedReason)
                case .failure(let error):
                    presentAlert(title: "Fel", message: error.localizedDescription)
                }
            }
        }
        
        if treatment.eventType == "Note" || treatment.eventType == "Announcement" {
            if let fullNote = treatment.rawData["notes"] as? String {
                var modifiedNote = fullNote
                modifiedNote = modifiedNote.replacingOccurrences(of: "PumpResume", with: "Pump startades")
                modifiedNote = modifiedNote.replacingOccurrences(of: "PumpSuspend", with: "Pump pausades")
                var message = modifiedNote
                if let enteredBy = treatment.rawData["enteredBy"] as? String {
                    message += "\nInlagt av: \(enteredBy)"
                }
                presentAlert(title: "\(timeString)\n\nNotering", message: message)
                
            }
        }
        
        if ["Sensor Start", "Sensor Change", "Sensorbyte", "Sensorstart"].contains(treatment.eventType) {
            let title = "\(timeString)\n\nSensorbyte"
            var message = treatment.sensorStartNotes ?? "Inga anteckningar"
            if let enteredBy = treatment.rawData["enteredBy"] as? String {
                message += "\nInlagt av: \(enteredBy)"
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Analysera Sensorbyte", style: .default, handler: { _ in
                let events = self.buildEventsArray()
                let analysisStart = treatment.timestamp.addingTimeInterval(-30) // minus 30 s
                let analysisEnd = treatment.timestamp.addingTimeInterval(21600) // end 360 min after start
                let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: analysisEnd, modalWithTimestamp: true, modalTitleString: "Analys sensorbyte")
                let nav = UINavigationController(rootViewController: analysisVC)
                nav.modalPresentationStyle = .formSheet
                self.present(nav, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                tableView.deselectRow(at: indexPath, animated: true)
            }))
            self.present(alert, animated: true)
        }
        
        if treatment.eventType == "Site Change" {
            let title = "\(timeString)\n\nPoddbyte"
            var message = ""
            if let enteredBy = treatment.rawData["enteredBy"] as? String {
                message = "Inlagt av: \(enteredBy)"
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Analysera Poddbyte", style: .default, handler: { _ in
                let events = self.buildEventsArray()
                let analysisStart = treatment.timestamp.addingTimeInterval(-10800) // minus 3h
                let analysisEnd = treatment.timestamp.addingTimeInterval(10800) // end 3h after start
                let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: analysisEnd, modalWithTimestamp: true, modalTitleString: "Analys podd")
                let nav = UINavigationController(rootViewController: analysisVC)
                nav.modalPresentationStyle = .formSheet
                self.present(nav, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                tableView.deselectRow(at: indexPath, animated: true)
            }))
            self.present(alert, animated: true)
        }
        
        if treatment.eventType == "BG Check" {
            if let glucose = treatment.rawData["glucose"] as? Double,
               let units = treatment.rawData["units"] as? String {
                let mmol = units.lowercased().contains("mmol") ? glucose : glucose / 18.0
                let title = "\(timeString)\n\nFingerstick"
                var message = "Blodsocker: \(glucose) mmol/L"
                if let enteredBy = treatment.rawData["enteredBy"] as? String {
                    message += "\nInlagt av: \(enteredBy)"
                }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Analys stick", style: .default, handler: { _ in
                    let events = self.buildEventsArray()
                    let analysisStart = treatment.timestamp.addingTimeInterval(-1200) // minus 20 min
                    let analysisEnd = treatment.timestamp.addingTimeInterval(10800) // end 180 min after start - använder nil tillsvidare
                    let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: nil, modalWithTimestamp: true, modalTitleString: "Analys stick")
                    let nav = UINavigationController(rootViewController: analysisVC)
                    nav.modalPresentationStyle = .formSheet
                    self.present(nav, animated: true)
                }))
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    tableView.deselectRow(at: indexPath, animated: true)
                }))
                self.present(alert, animated: true)
            }
        }
        
        if ["Temporary Override", "Exercise", "Override"].contains(treatment.eventType) {
            if let fullOverride = treatment.overrideNotes {
                let title = "\(timeString)\n\nOverride"
                var message = fullOverride
                if let duration = treatment.overrideDuration {
                    // Show “Tillsvidare” if duration > 1439 minutes
                    if duration > 1439 {
                        message += "\nVaraktighet: Tillsvidare"
                    } else {
                        message += "\nVaraktighet: \(Int(duration)) min"
                    }
                    let expirationTime = treatment.timestamp.addingTimeInterval(duration * 60)
                    message += "\nAktiv till kl: \(timeFormatter.string(from: expirationTime))"
                }
                if let enteredBy = treatment.rawData["enteredBy"] as? String {
                    message += "\nInlagt av: \(enteredBy)"
                }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Analys override", style: .default, handler: { _ in
                    let events = self.buildEventsArray()
                    let analysisStart = treatment.timestamp.addingTimeInterval(-30) // minus 30 s
                    let analysisEnd = treatment.timestamp.addingTimeInterval(10800) // end 180 min after start - använder nil tillsvidare
                    let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: nil, modalWithTimestamp: true, modalTitleString: "Analys override")
                    let nav = UINavigationController(rootViewController: analysisVC)
                    nav.modalPresentationStyle = .formSheet
                    self.present(nav, animated: true)
                }))
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    tableView.deselectRow(at: indexPath, animated: true)
                }))
                self.present(alert, animated: true)
            }
        }

        if treatment.eventType == "Carb Correction" {
            let foodTypeValue = treatment.rawData["foodType"] as? String ?? ""
            let isDextro = foodTypeValue.contains("🍬")
            let title: String
            if isDextro {
                title = "\(timeString)\n\nDextro"
            } else {
                title = foodTypeValue.isEmpty
                    ? "\(timeString)\n\nFett & Protein"
                    : "\(timeString)\n\nMåltid"
            }
            var message: String
            if isDextro {
                message = foodTypeValue
            } else {
                message = foodTypeValue.isEmpty
                    ? "Kolhydratsekvivalenter: "
                    : foodTypeValue
            }
            let carbsValue: Double = treatment.rawData["carbs"] as? Double ?? 0.0
            message += foodTypeValue.isEmpty ? "\(formatValue(carbsValue)) g" : "\nKolhydrater: \(formatValue(carbsValue)) g"
            if let fatValue = treatment.rawData["fat"] as? Double, fatValue != 0 {
                message += "\nFett: \(formatValue(fatValue)) g"
            }
            if let proteinValue = treatment.rawData["protein"] as? Double, proteinValue != 0 {
                message += "\nProtein: \(formatValue(proteinValue)) g"
            }
            if let enteredBy = treatment.rawData["enteredBy"] as? String {
                message += "\nInlagt av: \(enteredBy)"
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: isDextro ? "Analys dextro" : "Analys måltid", style: .default, handler: { _ in
                let events = self.buildEventsArray()
                let analysisStart = treatment.timestamp.addingTimeInterval(-30) // minus 30 s
                let analysisEnd = treatment.timestamp.addingTimeInterval(10800) // end 180 min after start - använder nil tillsvidare
                let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: nil, modalWithTimestamp: true, modalTitleString: isDextro ? "Analys dextro" : "Analys måltid")
                let nav = UINavigationController(rootViewController: analysisVC)
                nav.modalPresentationStyle = .formSheet
                self.present(nav, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "Samma tid dagen innan", style: .default, handler: { _ in
                let events = self.buildEventsArray()
                let oneWeekBackStartIntervall = -(24 * 60 * 60 + 60 * 30) //igår + 30min tillbaka
                let oneWeekBackEndIntervall = oneWeekBackStartIntervall + 12600 //180+30 min efter start igår - använder nil tillsvidare
                let analysisStart = treatment.timestamp.addingTimeInterval(Double(oneWeekBackStartIntervall))
                let analysisEnd = treatment.timestamp.addingTimeInterval(Double(oneWeekBackEndIntervall))
                let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: nil, modalWithTimestamp: true, modalTitleString: "Analys tid")
                let nav = UINavigationController(rootViewController: analysisVC)
                nav.modalPresentationStyle = .formSheet
                self.present(nav, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "Samma tid veckan innan", style: .default, handler: { _ in
                let events = self.buildEventsArray()
                let oneWeekBackStartIntervall = -(7 * 24 * 60 * 60 + 60 * 30) //1 vecka och en 30min tillbaka
                let oneWeekBackEndIntervall = oneWeekBackStartIntervall + 12600 //180+30 min efter start en vecka tillbaka - använder nil tillsvidare
                let analysisStart = treatment.timestamp.addingTimeInterval(Double(oneWeekBackStartIntervall))
                let analysisEnd = treatment.timestamp.addingTimeInterval(Double(oneWeekBackEndIntervall))
                let analysisVC = MealAnalysisView(events: events, initialStart: analysisStart, initialEnd: nil, modalWithTimestamp: true, modalTitleString: "Analys tid")
                let nav = UINavigationController(rootViewController: analysisVC)
                nav.modalPresentationStyle = .formSheet
                self.present(nav, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                tableView.deselectRow(at: indexPath, animated: true)
            }))
            self.present(alert, animated: true)
        }

        if treatment.eventType == "Bolus" {
            let bolusValue = treatment.amount ?? "0.0"
            var message = "Insulin: \(bolusValue)"
            if let enteredBy = treatment.rawData["enteredBy"] as? String {
                message += "\nInlagt av: \(enteredBy)"
            }
            presentAlert(title: "\(timeString)\n\nBolus", message: message)
        }
    }

    
    func deselectRowAfterAlert(_ tableView: UITableView, indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
                replacement += "\n👉  OREF SLUTSATS:\n•"
                formatted = (formatted as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }
        
        // Step 2: Replace all commas with a line break bullet.
        formatted = formatted.replacingOccurrences(of: ",", with: "\n•")
        
        // Step 3: Specific replacements.
        formatted = formatted.replacingOccurrences(of: "BG: 5.5", with: "Glukos: 5.5 🦄")
        formatted = formatted.replacingOccurrences(of: "BG:", with: "Glukos:")
        formatted = formatted.replacingOccurrences(of: "SMB INAKTIVERADE!", with: "SMB Inaktiverade 🚫")
        formatted = formatted.replacingOccurrences(of: "Mikrobolus:", with: "🔹 Mikrobolus:")
        formatted = formatted.replacingOccurrences(of: ". ;", with: "\n• ")
        formatted = formatted.replacingOccurrences(of: "E. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "U. ", with: "E\n")
        formatted = formatted.replacingOccurrences(of: "E/h. ", with: "E/h\n")
        formatted = formatted.replacingOccurrences(of: "temp.", with: "temp.\n")
        formatted = formatted.replacingOccurrences(of: ". ", with: "")
        formatted = formatted.replacingOccurrences(of: "; ", with: "\n• ")
        
        // Replace TDD: <number> U with bold TDD (using regex)
        if let regexTDD = try? NSRegularExpression(pattern: "TDD:\\s(\\d+(?:\\.\\d{1,2})?)\\sU", options: []) {
            let range = NSRange(location: 0, length: formatted.utf16.count)
            formatted = regexTDD.stringByReplacingMatches(in: formatted, options: [], range: range, withTemplate: "TDD: $1E")
        }
        
        // New step: Replace HTML encoded less-than and greater-than signs
        formatted = formatted.replacingOccurrences(of: "&lt;", with: "<")
        formatted = formatted.replacingOccurrences(of: "&gt;", with: ">")
        
        return formatted
    }
    
    /// Remove a treatment that has just been deleted in Nightscout from the
    /// local NightscoutCache so duplicates don’t re-appear after an app restart.
    private func removeTreatmentFromCache(_ treatment: Treatment) {
        let dayStart = Calendar.current.startOfDay(for: treatment.timestamp)

        // Load the cached payload for that calendar day (if any).
        guard var payload = try? NightscoutCache.readDay(dayStart) else { return }

        // Prefer to match by Nightscout `_id`; fall back to timestamp + eventType.
        if let id = treatment.documentId {
            payload.treatments.removeAll { $0._id == id }
        } else {
            payload.treatments.removeAll {
                $0.created_at == treatment.timestamp && $0.eventType == treatment.eventType
            }
        }

        // Save the pruned day payload back to disk.
        try? NightscoutCache.writeDay(date: dayStart,
                                      sgv: payload.sgv,
                                      treatments: payload.treatments)
    }

    // MARK: - Rolling Window Freshness Refresh for Today

    /// Lightweight refresh for “today”: fetch rolling window from Nightscout,
    /// update the table, and overwrite the treatments portion of NightscoutCache
    /// for the affected days so MainVC can update immediately and deletions/edits
    /// are reflected (not just additions).
    private func refreshRollingTreatmentsForToday() {
        let now = Date()
        let hours = 24 * max(1, UserDefaultsRepository.downloadDays.value)
        let since = now.addingTimeInterval(-Double(hours) * 60 * 60)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)

        let params: [String: String] = [
            "find[created_at][$gte]": iso.string(from: since),
            "find[created_at][$lte]": iso.string(from: now)
        ]

        NightscoutUtils.executeDynamicRequest(eventType: .treatments, parameters: params) { result in
            DispatchQueue.main.async {
                guard case .success(let raw) = result,
                      let entries = raw as? [[String: AnyObject]] else {
                    return
                }

                // Parse fetched treatments
                let fetched = entries.compactMap { Treatment(dictionary: $0) }

                // Update table contents (even if empty)
                self.treatments = fetched.sorted { $0.timestamp > $1.timestamp }
                self.tableView.reloadData()
                self.updateDuplicateIndicator()

                // Overwrite cache treatments for all days in the rolling window
                self.overwriteTreatmentsCacheForRollingWindow(
                    start: since,
                    end: now,
                    fetchedTreatments: fetched
                )

                // Notify MainVC that cache has fresh treatment data
                NotificationCenter.default.post(
                    name: NSNotification.Name("TreatmentsCacheUpdated"),
                    object: nil
                )
            }
        }
    }

    /// Overwrite the *treatments* slice of the NightscoutCache for each calendar day
    /// covered by the rolling window. We preserve cached SGV data for each day.
    private func overwriteTreatmentsCacheForRollingWindow(start: Date, end: Date, fetchedTreatments: [Treatment]) {
        let cal = Calendar.current

        // Build the set of day-starts to rewrite (inclusive range)
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)

        var dayCursor = startDay
        while dayCursor <= endDay {
            // Treatments that belong to this local calendar day
            let dayStart = dayCursor
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }

            let dayTreatments = fetchedTreatments.filter { t in
                t.timestamp >= dayStart && t.timestamp < nextDay
            }

            // Preserve existing SGV data for this day if present
            let existingPayload = try? NightscoutCache.readDay(dayStart)
            let preservedSGV = existingPayload?.sgv ?? []

            // Convert Treatment -> CachedTreatment (NightscoutCache model)
            // by going through the same mapping used elsewhere: we rely on upsertTreatment
            // only for conversion convenience, but we overwrite the day file below.
            // We build cached treatments by re-reading the day after per-doc upserts.

            // First: upsert all treatments for this day so the cache has valid encoded objects
            // (this does NOT delete anything by itself).
            for t in dayTreatments {
                // If we have rawData for a treatment, prefer using that for upsert.
                // Otherwise, fall back to a minimal document.
                var doc: [String: AnyObject] = t.rawData
                if doc["_id"] == nil, let id = t.documentId as AnyObject? { doc["_id"] = id }
                if doc["eventType"] == nil { doc["eventType"] = t.eventType as AnyObject }
                if doc["created_at"] == nil {
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    doc["created_at"] = fmt.string(from: t.timestamp) as AnyObject
                }
                NightscoutCache.upsertTreatment(from: doc)
            }

            // Now rebuild the day file with ONLY the treatments for this day (deletions handled).
            // We read the day file (after upserts) and then filter to the IDs/timestamps we want.
            if var payload = try? NightscoutCache.readDay(dayStart) {
                // If the cache already had treatments, replace them. If not, start from empty.
                payload.treatments.removeAll()

                // Read back the upserted day and keep only treatments in this day’s range.
                // (NightscoutCache stores per-day already, so just take its treatments list.)
                // If readDay succeeded, payload.treatments currently corresponds to that day.
                // However we cleared it above, so we need to re-read fresh.
                if let freshPayload = try? NightscoutCache.readDay(dayStart) {
                    // Filter to this exact day window to be safe
                    let filtered = freshPayload.treatments.filter { ct in
                        ct.created_at >= dayStart && ct.created_at < nextDay
                    }
                    payload.treatments = filtered
                }

                // Finally write the day back, preserving SGV
                try? NightscoutCache.writeDay(date: dayStart, sgv: preservedSGV, treatments: payload.treatments)
            } else {
                // No existing payload file – just write a new one with preserved SGV (empty)
                // and treatments derived from dayTreatments by reading the cache day after upserts.
                if let freshPayload = try? NightscoutCache.readDay(dayStart) {
                    let filtered = freshPayload.treatments.filter { ct in
                        ct.created_at >= dayStart && ct.created_at < nextDay
                    }
                    try? NightscoutCache.writeDay(date: dayStart, sgv: preservedSGV, treatments: filtered)
                } else {
                    try? NightscoutCache.writeDay(date: dayStart, sgv: preservedSGV, treatments: [])
                }
            }

            dayCursor = nextDay
        }
    }
}
