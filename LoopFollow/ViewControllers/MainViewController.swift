//
//  FirstViewController.swift
//  LoopFollow
//
//  Created by Jon Fawcett on 6/1/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import Charts
import EventKit
import ShareClient
import UserNotifications
import AVFAudio
import CoreBluetooth
import SwiftUI

func IsNightscoutEnabled() -> Bool {
    return !ObservableUserDefaults.shared.url.value.isEmpty
}

class MainViewController: UIViewController, UITableViewDataSource, ChartViewDelegate, UNUserNotificationCenterDelegate, UIScrollViewDelegate {
    
    @IBOutlet weak var BGText: UILabel!
    @IBOutlet weak var DeltaText: UILabel!
    @IBOutlet weak var DirectionText: UILabel!
    @IBOutlet weak var BGChart: LineChartView!
    @IBOutlet weak var BGChartFull: LineChartView!
    @IBOutlet weak var MinAgoText: UILabel!
    @IBOutlet weak var infoTable: UITableView!
    @IBOutlet weak var Console: UITableViewCell!
    @IBOutlet weak var DragBar: UIImageView!
    @IBOutlet weak var PredictionLabel: UILabel!
    @IBOutlet weak var LoopStatusLabel: UILabel!
    @IBOutlet weak var statsPieChart: PieChartView!
    @IBOutlet weak var statsLowPercent: UILabel!
    @IBOutlet weak var statsInRangePercent: UILabel!
    @IBOutlet weak var statsHighPercent: UILabel!
    @IBOutlet weak var statsAvgBG: UILabel!
    @IBOutlet weak var statsEstA1C: UILabel!
    @IBOutlet weak var statsStdDev: UILabel!
    @IBOutlet weak var serverText: UILabel!
    @IBOutlet weak var statsView: UIView!
    @IBOutlet weak var smallGraphHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var highStack: UIStackView!
    @IBOutlet weak var historyStack: UIStackView!
    @IBOutlet weak var statsStack: UIStackView!
    var refreshScrollView: UIScrollView!
    var refreshControl: UIRefreshControl!

    let speechSynthesizer = AVSpeechSynthesizer()

    var appStateController: AppStateController?

    // Variables for BG Charts
    public var numPoints: Int = 13
    public var linePlotData: [Double] = []
    public var linePlotDataTime: [Double] = []
    var firstGraphLoad: Bool = true
    var firstBasalGraphLoad: Bool = true
    var minAgoBG: Double = 0.0
    var currentOverride = 1.0
    
    // Vars for NS Pull
    var mmol = false as Bool
    var apnsKey = UserDefaultsRepository.token.value as String
    var defaults : UserDefaults?
    let consoleLogging = true
    var timeofLastBGUpdate = 0 as TimeInterval
    var currentSage : sageData?
    var currentCage : cageData?
    var currentIage : iageData?

    var backgroundTask = BackgroundTask()
    
    // Refresh NS Data
    var timer = Timer()
    // check every 30 Seconds whether new bgvalues should be retrieved
    let timeInterval: TimeInterval = 30.0
    
    // Check Alarms Timer
    // Don't check within 1 minute of alarm triggering to give the snoozer time to save data
    var checkAlarmTimer = Timer()
    var checkAlarmInterval: TimeInterval = 60.0
    var graphNowTimer = Timer()

    var lastCalendarWriteAttemptTime: TimeInterval = 0

    // Info Table Setup
    var infoManager: InfoManager!
    var profileManager = ProfileManager.shared

    var bgData: [ShareGlucoseData] = []
    var basalProfile: [basalProfileStruct] = []
    var basalData: [basalGraphStruct] = []
    var basalScheduleData: [basalGraphStruct] = []
    var bolusData: [bolusGraphStruct] = []
    var smbData: [bolusGraphStruct] = []
    var carbData: [carbGraphStruct] = []
    var overrideGraphData: [DataStructs.overrideStruct] = []
    var tempTargetGraphData: [DataStructs.tempTargetStruct] = []
    var predictionData: [ShareGlucoseData] = []
    var bgCheckData: [ShareGlucoseData] = []
    var suspendGraphData: [DataStructs.timestampOnlyStruct] = []
    var resumeGraphData: [DataStructs.timestampOnlyStruct] = []
    //var sensorStartGraphData: [DataStructs.timestampOnlyStruct] = []
    var sensorStartGraphData: [DataStructs.sensorStartStruct] = []
    var pumpChangeGraphData: [DataStructs.timestampOnlyStruct] = []
    var noteGraphData: [DataStructs.noteStruct] = []
    var chartData = LineChartData()
    var newBGPulled = false
    var lastCalDate: Double = 0
    var latestDirectionString = ""
    var latestEvBG = ""
    var latestMinAgoString = ""
    var latestDeltaString = ""
    var latestLoopStatusString = ""
    var latestLoopTime: Double = 0
    var latestCOB: CarbMetric?
    var latestBasal = ""
    var latestCarbReq = ""
    var latestSens = ""
    var latestPumpVolume: Double = 50.0
    var latestIOB: InsulinMetric?
    var lastOverrideStartTime: TimeInterval = 0
    var lastOverrideEndTime: TimeInterval = 0
    
    var topBG: Float = UserDefaultsRepository.minBGScale.value
    var topPredictionBG: Float = UserDefaultsRepository.minBGScale.value

    var lastOverrideAlarm: TimeInterval = 0

    var lastTempTargetAlarm: TimeInterval = 0
    var lastTempTargetStartTime: TimeInterval = 0
    var lastTempTargetEndTime: TimeInterval = 0
    
    // Stats-specific data storage (can hold up to 30 days)
    var statsBGData: [ShareGlucoseData] = []
    var statsBGCheckData: [TimeInterval] = []
    var statsBolusData: [bolusGraphStruct] = []
    var statsSMBData: [bolusGraphStruct] = []
    var statsCarbData: [carbGraphStruct] = []
    var statsBasalData: [basalGraphStruct] = []
    var statsCacheLastUpdated: Date?

    // share
    var bgDataShare: [ShareGlucoseData] = []
    var dexShare: ShareClient?;
    
    // calendar setup
    let store = EKEventStore()
    
    var snoozeTabItem: UITabBarItem = UITabBarItem()
    
    // Stores the time of the last speech announcement to prevent repeated announcements.
    // This is a temporary safeguard until the issue with multiple calls to speakBG is fixed.
    var lastSpeechTime: Date?

    var autoScrollPauseUntil: Date? = nil
    
    var IsNotLooping = false

    let contactImageUpdater = ContactImageUpdater()

    override func viewDidLoad() {
        super.viewDidLoad()

        //Migration of UserDefaultsRepository -> Storage handling
        if !UserDefaultsRepository.backgroundRefresh.value {
            Storage.shared.backgroundRefreshType.value = .none
            UserDefaultsRepository.backgroundRefresh.value = true
        }
        
        // Ensure alertNotLooping has a minimum value of 16.
        if UserDefaultsRepository.alertNotLooping.value < 16 {
            UserDefaultsRepository.alertNotLooping.value = 16
        }
        
        // Synchronize info types to ensure arrays are the correct size
        UserDefaultsRepository.synchronizeInfoTypes()
        
        infoTable.rowHeight = 20
        infoTable.dataSource = self
        infoTable.tableFooterView = UIView(frame: .zero)
        infoTable.bounces = false
        //infoTable.addBorder(toSide: .Left, withColor: UIColor.darkGray.cgColor, andThickness: 2)
        
        self.infoManager = InfoManager(tableView: infoTable)

        smallGraphHeightConstraint.constant = CGFloat(UserDefaultsRepository.smallGraphHeight.value)
        self.view.layoutIfNeeded()

        let shareUserName = UserDefaultsRepository.shareUserName.value
        let sharePassword = UserDefaultsRepository.sharePassword.value
        let shareServer = UserDefaultsRepository.shareServer.value == "US" ?KnownShareServers.US.rawValue : KnownShareServers.NON_US.rawValue
        dexShare = ShareClient(username: shareUserName, password: sharePassword, shareServer: shareServer )
        
        // setup show/hide small graph and stats
        BGChartFull.isHidden = !UserDefaultsRepository.showSmallGraph.value
        statsView.isHidden = !UserDefaultsRepository.showStats.value
        
        BGChart.delegate = self
        BGChartFull.delegate = self
        
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
            self.tabBarController?.overrideUserInterfaceStyle = .dark
        }

        // Load the snoozer tab
        guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
        snoozer.loadViewIfNeeded()

        // Trigger foreground and background functions
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appCameToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        // Setup the Graph
        if firstGraphLoad {
            createGraph()
            createSmallBGGraph()
        }
        
        // setup display for NS vs Dex
        showHideNSDetails()
        
        scheduleAllTasks()

        // Set up refreshScrollView for BGText
        refreshScrollView = UIScrollView()
        refreshScrollView.translatesAutoresizingMaskIntoConstraints = false
        refreshScrollView.alwaysBounceVertical = true
        view.addSubview(refreshScrollView)
        
        NSLayoutConstraint.activate([
            refreshScrollView.leadingAnchor.constraint(equalTo: BGText.leadingAnchor),
            refreshScrollView.trailingAnchor.constraint(equalTo: BGText.trailingAnchor),
            refreshScrollView.topAnchor.constraint(equalTo: BGText.topAnchor),
            refreshScrollView.bottomAnchor.constraint(equalTo: BGText.bottomAnchor)
        ])
        
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        refreshScrollView.addSubview(refreshControl)
        
        // Add this line to prevent scrolling in other directions
        refreshScrollView.alwaysBounceVertical = true
        
        refreshScrollView.delegate = self
        // Tap on BGText area to trigger an ad hoc Dexcom Share fetch
        let bgTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBGTapOnBGText(_:)))
        bgTapGesture.numberOfTapsRequired = 2
        bgTapGesture.numberOfTouchesRequired = 1
        bgTapGesture.cancelsTouchesInView = false // don't interfere with pull-to-refresh
        refreshScrollView.addGestureRecognizer(bgTapGesture)

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("refresh"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTreatmentsCacheRefreshRequest(_:)), name: NSNotification.Name("RefreshTreatmentsCacheForDay"), object: nil)
        
        // Check UserDefaults and change text color if needed
            if UserDefaultsRepository.colorBGText.value {
                for view in highStack.arrangedSubviews {
                    if let label = view as? UILabel {
                        label.textColor = .systemPurple
                    }
                }
            }
        
        statsStack.isUserInteractionEnabled = true
        let tapGestureStats = UITapGestureRecognizer(target: self, action: #selector(showStatsFromStack))
        statsStack.addGestureRecognizer(tapGestureStats)
        
        // 1. Enable interaction on the stack
        historyStack.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showHistoryFromStack))
        historyStack.addGestureRecognizer(tapGesture)

        // 2. Create the circle view
        let circleView = UIView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .systemGray6
        circleView.layer.cornerRadius = 32.5 // half of 65 -> a perfect circle
        circleView.layer.masksToBounds = true

        // Add a thin, 1-point border around the circle
        circleView.layer.borderWidth = 0.5
        circleView.layer.borderColor = UIColor.systemGray.cgColor

        // 3. Insert it behind existing subviews at index 0
        historyStack.insertSubview(circleView, at: 0)

        // 4. Constrain it to be 65×65 and center it in the stack
        NSLayoutConstraint.activate([
            circleView.widthAnchor.constraint(equalToConstant: 65),
            circleView.heightAnchor.constraint(equalToConstant: 65),
            circleView.centerXAnchor.constraint(equalTo: historyStack.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: historyStack.centerYAnchor)
        ])
        
        //setupSwipeUpToStatus()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("refresh"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("RefreshTreatmentsCacheForDay"), object: nil)
    }
    
    // Clean all timers and start new ones when refreshing
    @objc private func handleTreatmentsCacheRefreshRequest(_ notification: Notification) {
        guard UserDefaultsRepository.downloadTreatments.value,
              IsNightscoutEnabled() else { return }

        guard let day = notification.userInfo?["day"] as? Date else { return }

        // Use the existing cache helper to fetch and update treatments cache for this day only
        WebLoadNSTreatmentsCache(forDay: day) {
            // No-op completion; TreatmentsTableView listens for the
            // "TreatmentsCacheUpdated" notification to reload its UI.
        }
    }
    @objc func refresh() {
        LogManager.shared.log(category: .general, message: "Refreshing")

        // Clear prediction for both Loop or OpenAPS

        // Check if Loop prediction data exists and clear it if necessary
        if !predictionData.isEmpty {
            predictionData.removeAll()
            updatePredictionGraph()
        }

        // Check if OpenAPS prediction data exists and clear it if necessary
        let openAPSDataIndices = [12, 13, 14, 15]
        for dataIndex in openAPSDataIndices {
            let mainChart = BGChart.lineData!.dataSets[dataIndex] as! LineChartDataSet
            let smallChart = BGChartFull.lineData!.dataSets[dataIndex] as! LineChartDataSet
            if !mainChart.entries.isEmpty || !smallChart.entries.isEmpty {
                updatePredictionGraphGeneric(
                    dataIndex: dataIndex,
                    predictionData: [],
                    chartLabel: "",
                    color: UIColor.systemGray
                )
            }
        }

        MinAgoText.text = "Refreshing"
        latestMinAgoString = "Refreshing"
        scheduleAllTasks()

        currentCage = nil
        currentSage = nil
        currentIage = nil
        lastSpeechTime = nil
        refreshControl.endRefreshing()
    }
    
    // Scroll down BGText when refreshing
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == refreshScrollView {
            let yOffset = scrollView.contentOffset.y
            if yOffset < 0 {
                BGText.transform = CGAffineTransform(translationX: 0, y: -yOffset)
            } else {
                BGText.transform = CGAffineTransform.identity
            }
        }
    }

    @objc private func handleBGTapOnBGText(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Recreate ShareClient with latest settings from UserDefaults
        let shareUserName = UserDefaultsRepository.shareUserName.value
        let sharePassword = UserDefaultsRepository.sharePassword.value
        let shareServerRaw = UserDefaultsRepository.shareServer.value == "US"
            ? KnownShareServers.US.rawValue
            : KnownShareServers.NON_US.rawValue
        dexShare = ShareClient(username: shareUserName,
                               password: sharePassword,
                               shareServer: shareServerRaw)

        LogManager.shared.log(
            category: .temporaryDebug,
            message: "[DexAdhoc] Using userLen=\(shareUserName.count), pwLen=\(sharePassword.count), server=\(shareServerRaw)",
            isDebug: true
        )

        // Ensure we have a ShareClient to use
        guard let dexShare = dexShare else {
            LogManager.shared.log(category: .temporaryDebug, message: "[DexAdhoc] No ShareClient configured", isDebug: true)
            showDexcomAdhocErrorAlert(message: "Dexcom Share är inte konfigurerat.")
            return
        }

        LogManager.shared.log(
            category: .temporaryDebug,
            message: "[DexAdhoc] Fetching latest Dexcom Share value (adhoc)",
            isDebug: true
        )

        dexShare.fetchData(1) { [weak self] error, result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    LogManager.shared.log(category: .temporaryDebug, message: "[DexAdhoc] Error fetching Dexcom data: \(error)", isDebug: true)
                    self.showDexcomAdhocErrorAlert(message: "Kunde inte hämta värde från Dexcom Share.")
                    return
                }

                guard let first = result?.first else {
                    LogManager.shared.log(category: .temporaryDebug, message: "[DexAdhoc] No glucose values returned", isDebug: true)
                    self.showDexcomAdhocErrorAlert(message: "Inga värden returnerades från Dexcom Share.")
                    return
                }

                let date = Date(timeIntervalSince1970: first.date)

                // Convert SGV to display units (mmol/L) using existing Localizer
                let bgString = Localizer.toDisplayUnits(String(first.sgv)).replacingOccurrences(of: ",", with: ".")

                // Map Dexcom direction string to our arrow symbol
                let directionSymbol = self.bgDirectionGraphic(first.direction ?? "")

                self.showDexcomAdhocPopup(
                    bgString: bgString,
                    timestamp: date,
                    directionSymbol: directionSymbol
                )
            }
        }
    }

    private func showDexcomAdhocPopup(bgString: String, timestamp: Date, directionSymbol: String?) {
        // Remove any existing popup
        let popupTag = 424242
        if let existing = view.viewWithTag(popupTag) {
            existing.removeFromSuperview()
        }

        let container = UIView()
        container.tag = popupTag
        container.translatesAutoresizingMaskIntoConstraints = false

        // Dexcom-grön bakgrund
        container.backgroundColor = UIColor(
            red: 76.0/255.0,
            green: 179.0/255.0,
            blue: 72.0/255.0,
            alpha: 1.0
        )

        container.layer.cornerRadius = 16
        container.layer.masksToBounds = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.25
        container.layer.shadowRadius = 8
        container.layer.shadowOffset = CGSize(width: 0, height: 4)

        // 4 px kantlinje, label-färgad
        container.layer.borderWidth = 4
        container.layer.borderColor = UIColor.white.cgColor

        // Title label
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.text = "Dexcom Follow"

        let bgLabel = UILabel()
        bgLabel.translatesAutoresizingMaskIntoConstraints = false
        bgLabel.font = UIFont.systemFont(ofSize: 60, weight: .heavy)
        bgLabel.textAlignment = .center
        bgLabel.textColor = .white
        bgLabel.text = bgString

        let directionLabel = UILabel()
        directionLabel.translatesAutoresizingMaskIntoConstraints = false
        directionLabel.font = UIFont.systemFont(ofSize: 50, weight: .heavy)
        directionLabel.textAlignment = .center
        directionLabel.textColor = .white
        directionLabel.text = directionSymbol ?? "-"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let timeLabel = UILabel()
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        let timeString = formatter.string(from: timestamp)

        // Build attributed string with image + spacing + text
        let attachment = NSTextAttachment()
        attachment.image = UIImage(named: "dexcomFollow")
        attachment.bounds = CGRect(
            x: 0,
            y: (timeLabel.font.capHeight - 15) / 2,
            width: 15,
            height: 15
        )

        let imageString = NSAttributedString(attachment: attachment)
        let spacer = NSAttributedString(string: "  ") // ~6–7p
        let textString = NSAttributedString(
            string: timeString,
            attributes: [
                .font: timeLabel.font!,
                .foregroundColor: timeLabel.textColor!
            ]
        )

        let combined = NSMutableAttributedString()
        combined.append(imageString)
        combined.append(spacer)
        combined.append(textString)
        timeLabel.attributedText = combined

        container.addSubview(titleLabel)
        container.addSubview(bgLabel)
        container.addSubview(directionLabel)
        container.addSubview(timeLabel)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            // Position popup centered on BGText
            container.centerXAnchor.constraint(equalTo: BGText.centerXAnchor, constant: 6),
            container.topAnchor.constraint(equalTo: BGText.topAnchor),
            container.widthAnchor.constraint(equalToConstant: 150),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 225),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            bgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            bgLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            bgLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            directionLabel.topAnchor.constraint(equalTo: bgLabel.bottomAnchor, constant: 0),
            directionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            directionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: directionLabel.bottomAnchor, constant: 10),
            timeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        container.alpha = 0
        UIView.animate(withDuration: 0.2) {
            container.alpha = 1
        }

        // Auto-hide after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak container] in
            UIView.animate(withDuration: 0.25, animations: {
                container?.alpha = 0
            }, completion: { _ in
                container?.removeFromSuperview()
            })
        }
    }

    private func showDexcomAdhocErrorAlert(message: String) {
        let alert = UIAlertController(title: "Dexcom Share", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    /*
    private func setupSwipeUpToStatus() {
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUpToStatsView(_:)))
        swipeUp.direction = .up
        swipeUp.numberOfTouchesRequired = 1
        swipeUp.cancelsTouchesInView = false // don't steal taps from buttons/steppers
        view.addGestureRecognizer(swipeUp)
    }

    @objc private func handleSwipeUpToStatsView(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // Require swipe to start in the lower quarter to minimize accidental triggers
        let startPoint = gesture.location(in: view)
        let lowerThreshold = view.bounds.height * 0.75
        guard startPoint.y >= lowerThreshold else { return }

        // Avoid double-presenting
        guard presentedViewController == nil else { return }

        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Build AggregatedStatsView with this MainViewController as context
        let viewModel = AggregatedStatsViewModel(mainViewController: self)
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
    */

    
    override func viewWillAppear(_ animated: Bool) {
        // set screen lock
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value;
        
        // check the app state
        // TODO: move to a function ?
        if let appState = self.appStateController {
            
            if appState.chartSettingsChanged {
                
                // can look at settings flags to be more fine tuned
                self.updateBGGraphSettings()
                
                if ChartSettingsChangeEnum.smallGraphHeight.rawValue != 0 {
                    smallGraphHeightConstraint.constant = CGFloat(UserDefaultsRepository.smallGraphHeight.value)
                    self.view.layoutIfNeeded()
                }
                
                // reset the app state
                appState.chartSettingsChanged = false
                appState.chartSettingsChanges = 0
            }
            if appState.generalSettingsChanged {
                
                // settings for appBadge changed
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.appBadgeChange.rawValue != 0 {
                    
                }
                
                // settings for textcolor changed
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.colorBGTextChange.rawValue != 0 {
                    self.setBGTextColor()
                }
                
                // settings for showStats changed
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.showStatsChange.rawValue != 0 {
                    statsView.isHidden = !UserDefaultsRepository.showStats.value
                }
                
                // settings for useIFCC changed
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.useIFCCChange.rawValue != 0 {
                    updateStats()
                }
                
                // settings for showSmallGraph changed
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.showSmallGraphChange.rawValue != 0 {
                    BGChartFull.isHidden = !UserDefaultsRepository.showSmallGraph.value
                }
                
                if appState.generalSettingsChanges & GeneralSettingsChangeEnum.showDisplayNameChange.rawValue != 0 {
                    self.updateServerText()
                }
                
                // reset the app state
                appState.generalSettingsChanged = false
                appState.generalSettingsChanges = 0
            }
            if appState.infoDataSettingsChanged {
                self.infoTable.reloadData()
                
                // reset
                appState.infoDataSettingsChanged = false
            }
            
            // add more processing of the app state
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // Sektion 0: prio-rader (LabelCellPrio)
        // Sektion 1: normala rader (LabelCell)
        return 2
    }
    // Info Table Functions
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let infoManager = infoManager else {
            return 0
        }

        if section == 0 {
            // Prio-rader
            return infoManager.numberOfPriorityRows()
        } else {
            // Vanliga rader
            return infoManager.numberOfRows()
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let infoManager = infoManager else {
            // Borde inte hända, men ger en minimal fallback
            return UITableViewCell(style: .value1, reuseIdentifier: "FallbackCell")
        }

        // InfoManager bryr sig bara om row, inte section
        let rowIndexPath = IndexPath(row: indexPath.row, section: 0)

        if indexPath.section == 0 {
            // Prio-sektion → LabelCellPrio
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCellPrio", for: indexPath)

            if let values = infoManager.priorityDataForIndexPath(rowIndexPath) {
                cell.textLabel?.text = values.name
                cell.detailTextLabel?.text = values.value
            } else {
                cell.textLabel?.text = ""
                cell.detailTextLabel?.text = ""
            }

            if let type = infoManager.infoTypeForPriorityRow(rowIndexPath) {
                switch type {
                case .iob:
                    cell.textLabel?.textColor = .systemBlue
                    cell.detailTextLabel?.textColor = .systemBlue
                case .cob:
                    cell.textLabel?.textColor = .systemOrange
                    cell.detailTextLabel?.textColor = .systemOrange
                default:
                    cell.textLabel?.textColor = .label
                    cell.detailTextLabel?.textColor = .label
                }
            }

            // Se till att själva cellen är transparent
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear

            // Lägg till (eller återanvänd) en highlight-view bakom innehållet
            let highlightTag = 999
            let highlightView: UIView

            if let existing = cell.contentView.viewWithTag(highlightTag) {
                highlightView = existing
            } else {
                let view = UIView()
                view.tag = highlightTag
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.insertSubview(view, at: 0)

                NSLayoutConstraint.activate([
                    // inre bredd = samma som layoutmarginalerna (där dina “stödlinjer” är +6p)
                    view.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: -5),
                    view.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor, constant: 3),
                    view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
                ])

                highlightView = view
            }

            // Rounded corners only on the leading (left) side for the red highlight
            highlightView.layer.cornerRadius = 5
            highlightView.layer.masksToBounds = true

            highlightView.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.35)

            return cell
        } else {
            // Normal sektion → LabelCell
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath)

            if let values = infoManager.dataForIndexPath(rowIndexPath) {
                cell.textLabel?.text = values.name
                cell.detailTextLabel?.text = values.value
            } else {
                cell.textLabel?.text = ""
                cell.detailTextLabel?.text = ""
            }

            if let type = infoManager.infoTypeForRow(rowIndexPath) {
                switch type {
                case .iob:
                    cell.textLabel?.textColor = .systemBlue
                    cell.detailTextLabel?.textColor = .systemBlue
                case .cob:
                    cell.textLabel?.textColor = .systemOrange
                    cell.detailTextLabel?.textColor = .systemOrange
                default:
                    cell.textLabel?.textColor = .label
                    cell.detailTextLabel?.textColor = .secondaryLabel
                }
            }

            cell.backgroundColor = .clear

            return cell
        }
    }

    @objc func appMovedToBackground() {
        // Allow screen to turn off
        UIApplication.shared.isIdleTimerDisabled = false;
        
        // We want to always come back to the home screen
        tabBarController?.selectedIndex = 0
        
        if Storage.shared.backgroundRefreshType.value == .silentTune {
            backgroundTask.startBackgroundTask()
        }

        if Storage.shared.backgroundRefreshType.value != .none {
            BackgroundAlertManager.shared.startBackgroundAlert()
        }
    }
    
    @objc func appCameToForeground() {
        // reset screenlock state if needed
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value;
        
        if Storage.shared.backgroundRefreshType.value == .silentTune {
            backgroundTask.stopBackgroundTask()
        }
        
        if Storage.shared.backgroundRefreshType.value != .none {
            BackgroundAlertManager.shared.stopBackgroundAlert()
        }

        TaskScheduler.shared.checkTasksNow()
/* Revertat ändring i 2f66847 & 94ad3e9 pga sämre UX
        // Kick MinAgo immediately when returning to foreground
        minAgoTaskAction()
        TaskScheduler.shared.rescheduleTask(id: .minAgoUpdate,
                                            to: Date().addingTimeInterval(1))
*/
        
        checkAndNotifyVersionStatus()
        checkAppExpirationStatus()
    }
    
    func checkAndNotifyVersionStatus() {
        let versionManager = AppVersionManager()
        versionManager.checkForNewVersion { latestVersion, isNewer, isBlacklisted in
            let now = Date()
            
            // Check if the current version is blacklisted, or if there is a newer version available
            if isBlacklisted {
                let lastBlacklistShown = UserDefaultsRepository.lastBlacklistNotificationShown.value ?? Date.distantPast
                if now.timeIntervalSince(lastBlacklistShown) > 86400 { // 24 hours
                    self.versionAlert(message: "The current version has a critical issue and should be updated as soon as possible.")
                    UserDefaultsRepository.lastBlacklistNotificationShown.value = now
                    UserDefaultsRepository.lastVersionUpdateNotificationShown.value = now
                }
            } else if isNewer {
                let lastVersionUpdateShown = UserDefaultsRepository.lastVersionUpdateNotificationShown.value ?? Date.distantPast
                if now.timeIntervalSince(lastVersionUpdateShown) > 1209600 { // 2 weeks
                    self.versionAlert(message: "A new version is available: \(latestVersion ?? "Unknown"). It is recommended to update.")
                    UserDefaultsRepository.lastVersionUpdateNotificationShown.value = now
                }
            }
        }
    }
    
    func versionAlert(title: String = "Update Available", message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    func checkAppExpirationStatus() {
        let now = Date()
        let expirationDate = BuildDetails.default.calculateExpirationDate()
        let weekBeforeExpiration = Calendar.current.date(byAdding: .day, value: -7, to: expirationDate)!
        
        if now >= weekBeforeExpiration {
            let lastExpirationShown = UserDefaultsRepository.lastExpirationNotificationShown.value ?? Date.distantPast
            if now.timeIntervalSince(lastExpirationShown) > 86400 { // 24 hours
                expirationAlert()
                UserDefaultsRepository.lastExpirationNotificationShown.value = now
            }
        }
    }
    
    func expirationAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "App Expiration Warning", message: "This app will expire in less than a week. Please rebuild to continue using it.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    @objc override func viewDidAppear(_ animated: Bool) {
        showHideNSDetails()
    }
    
    func stringFromTimeInterval(interval: TimeInterval) -> String {
        let interval = Int(interval)
        let minutes = (interval / 60) % 60
        let hours = (interval / 3600)
        return String(format: "%02d:%02d", hours, minutes)
    }
    
    func showHideNSDetails() {
        var isHidden = false
        var isEnabled = true
        if !IsNightscoutEnabled() {
            isHidden = true
            isEnabled = false
        }
        
        LoopStatusLabel.isHidden = isHidden
        if IsNotLooping {
            //PredictionLabel.isHidden = true
        }
        else {
            PredictionLabel.isHidden = isHidden
        }
        infoTable.isHidden = isHidden
        
        if UserDefaultsRepository.hideInfoTable.value {
            infoTable.isHidden = true
        }
        
        if IsNightscoutEnabled() {
            isEnabled = true
        }
        
        guard let nightscoutTab = self.tabBarController?.tabBar.items![3] else { return }
        nightscoutTab.isEnabled = isEnabled
        
    }
    
    func updateBadge(val: Int) {
        if UserDefaultsRepository.appBadge.value {
            let latestBG = String(val)
            UIApplication.shared.applicationIconBadgeNumber = Int(Localizer.removePeriodAndCommaForBadge(Localizer.toDisplayUnits(latestBG))) ?? val
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
/*
    func setBGTextColor() {
        if bgData.count > 0 {
            guard let snoozer = self.tabBarController?.viewControllers?[2] as? SnoozeViewController else { return }
            let latestBG = bgData[bgData.count - 1].sgv
            var color: UIColor = .label // Default color
            if UserDefaultsRepository.colorBGText.value {
                if Float(latestBG) >= UserDefaultsRepository.highLine.value {
                    color = UIColor.systemPurple.withAlphaComponent(0.8) // Directly use systemPurple with alpha
                }
                
                if let loopRed = UIColor(named: "LoopRed") {
                    if Float(latestBG) <= UserDefaultsRepository.lowLine.value {
                        color = loopRed
                    }
                }
                
                if let loopGreen = UIColor(named: "LoopGreen") {
                    if Float(latestBG) > UserDefaultsRepository.lowLine.value && Float(latestBG) < UserDefaultsRepository.highLine.value {
                        color = loopGreen
                    }
                }
            }
            
            BGText.textColor = color
            snoozer.BGLabel.textColor = color
        }
    }
*/
    
    func setBGTextColor() {
        guard bgData.count > 0 else { return }
        guard let snoozer = self.tabBarController?.viewControllers?[2] as? SnoozeViewController else { return }
        
        let latestBG = bgData[bgData.count - 1].sgv

        if UserDefaultsRepository.colorBGText.value {
            let color = setBGColor(latestBG) // Use the reusable function
            BGText.textColor = color
            snoozer.BGLabel.textColor = color
        }
        // Otherwise, do nothing, keeping the default color set in the storyboard
    }
    
    func bgDirectionGraphic(_ value:String)->String
    {
        if value == nil { return "-" }
        let //graphics:[String:String]=["Flat":"\u{2192}","DoubleUp":"\u{21C8}","SingleUp":"\u{2191}","FortyFiveUp":"\u{2197}\u{FE0E}","FortyFiveDown":"\u{2198}\u{FE0E}","SingleDown":"\u{2193}","DoubleDown":"\u{21CA}","None":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-"]
    graphics:[String:String]=["Flat":"→","DoubleUp":"↑↑","SingleUp":"↑","FortyFiveUp":"↗","FortyFiveDown":"↘︎","SingleDown":"↓","DoubleDown":"↓↓","None":"-","NONE":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-", "": "-"]
        return graphics[value]!
    }
    
    func writeCalendar() {
        self.store.requestCalendarAccess { (granted, error) in
            if !granted {
                LogManager.shared.log(category: .calendar, message: "Failed to get calendar access: \(String(describing: error))")
                return
            }
            self.processCalendarUpdates()
        }
    }

    func processCalendarUpdates() {
        if UserDefaultsRepository.calendarIdentifier.value == "" { return }

        if self.bgData.count < 1 { return }

        // This lets us fire the method to write Min Ago entries only once a minute starting after 6 minutes but allows new readings through
        let now = dateTimeUtils.getNowTimeIntervalUTC()
        let newestBGDate = bgData[bgData.count - 1].date

        if lastCalDate == newestBGDate {
            if (now - lastCalendarWriteAttemptTime) < 60 || (now - newestBGDate) < 360 {
                return
            }
        }

        // Create Event info
        var deltaBG = 0 // protect index out of bounds
        if self.bgData.count > 1 {
            deltaBG = self.bgData[self.bgData.count - 1].sgv -  self.bgData[self.bgData.count - 2].sgv as Int
        }
        let deltaTime = (TimeInterval(Date().timeIntervalSince1970) - self.bgData[self.bgData.count - 1].date) / 60
        var deltaString = ""
        if deltaBG < 0 {
            deltaString = Localizer.toDisplayUnits(String(deltaBG))
        }
        else
        {
            deltaString = "+" + Localizer.toDisplayUnits(String(deltaBG))
        }
        let direction = self.bgDirectionGraphic(self.bgData[self.bgData.count - 1].direction ?? "")
        
        var eventStartDate = Date(timeIntervalSince1970: self.bgData[self.bgData.count - 1].date)
        var eventEndDate = eventStartDate.addingTimeInterval(60 * 10)
        var  eventTitle = UserDefaultsRepository.watchLine1.value
        var  eventLocation = UserDefaultsRepository.watchLine2.value
        //if (UserDefaultsRepository.watchLine2.value.count > 1) {
            //eventLocation += UserDefaultsRepository.watchLine2.value
        //<}
        // Replace commas in bgUnits result with periods
        let bgDisplayUnits = Localizer.toDisplayUnits(String(self.bgData[self.bgData.count - 1].sgv)).replacingOccurrences(of: ",", with: ".")
        eventTitle = eventTitle.replacingOccurrences(of: "%BG%", with: bgDisplayUnits)
        eventTitle = eventTitle.replacingOccurrences(of: "%DIRECTION%", with: direction)
        // Replace commas in deltaString with periods
        let deltaStringWithoutCommas = deltaString.replacingOccurrences(of: ",", with: ".")
        eventTitle = eventTitle.replacingOccurrences(of: "%DELTA%", with: deltaStringWithoutCommas)
        if self.currentOverride != 1.0 {
            let val = Int( self.currentOverride*100)
            // let overrideText = String(format:"%f1", self.currentOverride*100)
            let text = String(val) + "%"
            eventLocation = eventLocation.replacingOccurrences(of: "%OVERRIDE%", with: text)
        } else {
            eventLocation = eventLocation.replacingOccurrences(of: "%OVERRIDE%", with: "")
        }
        eventLocation = eventLocation.replacingOccurrences(of: "%LOOP%", with: self.latestLoopStatusString)
        var minAgo = ""
        if deltaTime > 9 {
            // write old BG reading and continue pushing out end date to show last entry
            minAgo = String(Int(deltaTime)) + " min"
            eventEndDate = eventStartDate.addingTimeInterval((60 * 10) + (deltaTime * 60))
        }
        let lastSGV = Double(self.bgData[self.bgData.count - 1].sgv) // Convert the last SGV to a Double
        let deltaBGValue = Double(deltaBG) // Convert deltaBG to a Double

        let fifteenMin = (lastSGV + deltaBGValue * 2) * 0.0555
        let fifteenMinString = String(format: "%.1f", fifteenMin) // Convert to string with one decimal place
            // Use the calculated 'fifteenMinString' as needed
        let fifteenMinValue = Double(fifteenMinString) ?? 0.0

        if fifteenMinValue < 3.9 {
            eventLocation = eventLocation.replacingOccurrences(of: "%15MIN%", with: "🆘 " + fifteenMinString)
        } else if fifteenMinValue > 7.8 {
            eventLocation = eventLocation.replacingOccurrences(of: "%15MIN%", with: "⚠️ " + fifteenMinString)
        } else {
            eventLocation = eventLocation.replacingOccurrences(of: "%15MIN%", with: "✅ " + fifteenMinString)
        }
        var basal = "~"
        if self.latestBasal != "" {
            basal = self.latestBasal
        }
        eventTitle = eventTitle.replacingOccurrences(of: "%MINAGO%", with: minAgo)
        eventLocation = eventLocation.replacingOccurrences(of: "%IOB%", with: latestIOB?.formattedValue() ?? "0")
        eventLocation = eventLocation.replacingOccurrences(of: "%COB%", with: latestCOB?.formattedValue() ?? "0")
        eventLocation = eventLocation.replacingOccurrences(of: "%BASAL%", with: basal)
        
        // Delete Events from last 2 hours and 2 hours in future
        var deleteStartDate = Date().addingTimeInterval(-60*60*2)
        var deleteEndDate = Date().addingTimeInterval(60*60*2)
        // guard solves for some ios upgrades removing the calendar
        guard let deleteCalendar = self.store.calendar(withIdentifier: UserDefaultsRepository.calendarIdentifier.value) as? EKCalendar else { return }
        var predicate2 = self.store.predicateForEvents(withStart: deleteStartDate, end: deleteEndDate, calendars: [deleteCalendar])
        var eVDelete = self.store.events(matching: predicate2) as [EKEvent]?
        if eVDelete != nil {
            for i in eVDelete! {
                do {
                    try self.store.remove(i, span: EKSpan.thisEvent, commit: true)
                } catch let error {
                    LogManager.shared.log(category: .calendar, message: "\(error)", isDebug: true)
                }
            }
        }
        
        // Write New Event
        var event = EKEvent(eventStore: self.store)
        event.title = eventTitle
        event.location = eventLocation
        event.startDate = eventStartDate
        event.endDate = eventEndDate
        event.calendar = self.store.calendar(withIdentifier: UserDefaultsRepository.calendarIdentifier.value)
        do {
            try self.store.save(event, span: .thisEvent, commit: true)
            self.lastCalendarWriteAttemptTime = now

            self.lastCalDate = self.bgData[self.bgData.count - 1].date
            //UserDefaultsRepository.savedEventID.value = event.eventIdentifier //save event id to access this particular event later
        } catch {
            LogManager.shared.log(category: .calendar, message: "Error storing to the calendar")
        }
    }
    
    
    func persistentNotification(bgTime: TimeInterval)
    {
        if UserDefaultsRepository.persistentNotification.value && bgTime > UserDefaultsRepository.persistentNotificationLastBGTime.value && bgData.count > 0 {
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            
            let iobString = latestIOB?.formattedValue() ?? "N/A"
            let cobString = latestCOB?.formattedValue() ?? "N/A"
            
            snoozer.sendNotification(
                self,
                bgVal: Localizer.toDisplayUnits(String(bgData[bgData.count - 1].sgv)),
                directionVal: latestDirectionString,
                deltaVal: latestDeltaString,
                minAgoVal: latestMinAgoString,
                alertLabelVal: "Latest BG",
                latestIOB: iobString,
                latestCOB: cobString
            )
        }
    }

    // General Notifications
    
    func sendGeneralNotification(_ sender: Any, title: String, subtitle: String, body: String, timer: TimeInterval) {
        
        UNUserNotificationCenter.current().delegate = self
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.categoryIdentifier = "noAction"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timer, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        
        
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
    }
    
    // User has scrolled the chart
    func chartTranslated(_ chartView: ChartViewBase, dX: CGFloat, dY: CGFloat) {
        let isViewingLatestData = abs(BGChart.highestVisibleX - BGChart.chartXMax) < 0.001
        if isViewingLatestData {
            autoScrollPauseUntil = nil // User is back at the latest data, allow auto-scrolling
        } else {
            autoScrollPauseUntil = Date().addingTimeInterval(5 * 60) // User is viewing historical data, pause auto-scrolling
        }
    }

    func calculateMaxBgGraphValue() -> Float {
        return max(topBG, topPredictionBG)
    }
    
    @objc func showHistoryFromStack() {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Instantiate your TreatmentsTableView.
        let treatmentsVC = TreatmentsTableView()
        
        // Wrap it in a UINavigationController for the navigation bar and Klar button.
        let navController = UINavigationController(rootViewController: treatmentsVC)
        navController.modalPresentationStyle = .formSheet
        
        if UserDefaultsRepository.forceDarkMode.value {
            navController.overrideUserInterfaceStyle = .dark
        }
        
        present(navController, animated: true, completion: nil)
    }
    
    @objc func showStatsFromStack() {
        // Light haptic for feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Build AggregatedStatsView with this MainViewController as context
        let viewModel = AggregatedStatsViewModel(mainViewController: self)
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
}
