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
    var refreshScrollView: UIScrollView!
    var refreshControl: UIRefreshControl!

    let speechSynthesizer = AVSpeechSynthesizer()
    
    @IBOutlet weak var Shortcut: UIButton!
    
    @IBAction func openURLButtonTapped(_ sender: UIButton) {
        if let url = URL(string: "shortcuts://run-shortcut?name=Loop%20Follow") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    // Data Table class
    class infoData {
        public var name: String
        public var value: String
        init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }
    
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
    var urlUser = UserDefaultsRepository.url.value as String
    var token = UserDefaultsRepository.token.value as String
    var defaults : UserDefaults?
    let consoleLogging = true
    var timeofLastBGUpdate = 0 as TimeInterval
    var nsVerifiedAlerted = false
    var currentSage : sageData?
    var currentCage : cageData?

    var backgroundTask = BackgroundTask()
    
    // Refresh NS Data
    var timer = Timer()
    // check every 30 Seconds whether new bgvalues should be retrieved
    let timeInterval: TimeInterval = 30.0
    
    // Min Ago Timer
    var minAgoTimer = Timer()
    var minAgoTimeInterval: TimeInterval = 1.0
    
    
    // Check Alarms Timer
    // Don't check within 1 minute of alarm triggering to give the snoozer time to save data
    var checkAlarmTimer = Timer()
    var checkAlarmInterval: TimeInterval = 60.0
    
    var calTimer = Timer()
    
    var bgTimer = Timer()
    var profileTimer = Timer()
    var deviceStatusTimer = Timer()
    var treatmentsTimer = Timer()
    var alarmTimer = Timer()
    var calendarTimer = Timer()
    var graphNowTimer = Timer()
    
    // Info Table Setup
    var tableData : [infoData] = []
    var derivedTableData: [infoData] = []
    
    var bgData: [ShareGlucoseData] = []
    var basalProfile: [basalProfileStruct] = []
    var basalData: [basalGraphStruct] = []
    var basalScheduleData: [basalGraphStruct] = []
    var bolusData: [bolusGraphStruct] = []
    var smbData: [smbGraphStruct] = []
    var carbData: [carbGraphStruct] = []
    var overrideGraphData: [DataStructs.overrideStruct] = []
    var predictionData: [ShareGlucoseData] = []
    var predictionDataCOB: [ShareGlucoseData] = []
    var predictionDataUAM: [ShareGlucoseData] = []
    var predictionDataIOB: [ShareGlucoseData] = []
    var predictionDataZT: [ShareGlucoseData] = []
    var bgCheckData: [ShareGlucoseData] = []
    var suspendGraphData: [DataStructs.timestampOnlyStruct] = []
    var resumeGraphData: [DataStructs.timestampOnlyStruct] = []
    var sensorStartGraphData: [DataStructs.timestampOnlyStruct] = []
    var pumpChangeGraphData: [DataStructs.timestampOnlyStruct] = []
    var noteGraphData: [DataStructs.noteStruct] = []
    var chartData = LineChartData()
    var newBGPulled = false
    var lastCalDate: Double = 0
    var latestDirectionString = ""
    var latestMinAgoString = ""
    var latestDeltaString = ""
    var latestLoopStatusString = ""
    var latestLoopTime: Double = 0
    var latestCOB = ""
    var latestInsulinReq = ""
    var latestCarbReq = ""
    var latestSens = ""
    var latestISF = ""
    var latestMinMax = ""
    var latestEvBG = ""
    var latestBasal = ""
    var basalNow = ""
    var latestPumpVolume: Double = 50.0
    var latestIOB = ""
    var lastOverrideStartTime: TimeInterval = 0
    var lastOverrideEndTime: TimeInterval = 0
    var topBG: Float = UserDefaultsRepository.minBGScale.value
    var topPredictionBG: Float = UserDefaultsRepository.minBGScale.value
    var lastOverrideAlarm: TimeInterval = 0
    
    // share
    var bgDataShare: [ShareGlucoseData] = []
    var dexShare: ShareClient?;
    var dexVerifiedAlerted = false
    
    // calendar setup
    let store = EKEventStore()
    
    var snoozeTabItem: UITabBarItem = UITabBarItem()
    
    // Stores the time of the last speech announcement to prevent repeated announcements.
    // This is a temporary safeguard until the issue with multiple calls to speakBG is fixed.
    var lastSpeechTime: Date?

    var autoScrollPauseUntil: Date? = nil
    
    var IsNotLooping = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // reset the infoTable names in case we add or delete items
        UserDefaultsRepository.infoNames.value.removeAll()
        UserDefaultsRepository.infoNames.value.append("IOB")
        UserDefaultsRepository.infoNames.value.append("COB")
        UserDefaultsRepository.infoNames.value.append("Basal")
        UserDefaultsRepository.infoNames.value.append("Override")
        UserDefaultsRepository.infoNames.value.append("Looptelefon")
        UserDefaultsRepository.infoNames.value.append("Reservoar")
        UserDefaultsRepository.infoNames.value.append("Sensorbyte om")
        UserDefaultsRepository.infoNames.value.append("Poddbyte om")
        UserDefaultsRepository.infoNames.value.append("Behov Insulin")
        UserDefaultsRepository.infoNames.value.append("Min-Max")
        UserDefaultsRepository.infoNames.value.append("Kh idag")
        UserDefaultsRepository.infoNames.value.append("Autosens")
        UserDefaultsRepository.infoNames.value.append("Profil")
        //Auggie
        UserDefaultsRepository.infoNames.value.append("Total daglig dos")
        UserDefaultsRepository.infoNames.value.append("ISF")
        UserDefaultsRepository.infoNames.value.append("CR")
        UserDefaultsRepository.infoNames.value.append("Målvärde")
        UserDefaultsRepository.infoNames.value.append("Behov Kh")
        UserDefaultsRepository.infoNames.value.append("Info uppdaterad")

        // Reset deprecated settings
        UserDefaultsRepository.debugLog.value = false;
        UserDefaultsRepository.alwaysDownloadAllBG.value = true;
        
        // table view
        //infoTable.layer.borderColor = UIColor.darkGray.cgColor
        //infoTable.layer.borderWidth = 1.0
        //infoTable.layer.cornerRadius = 6
        infoTable.rowHeight = 20
        infoTable.dataSource = self
        infoTable.tableFooterView = UIView(frame: .zero) // get rid of extra rows
        infoTable.bounces = false
        
        // initialize the tableData
        self.tableData = []
        for i in 0..<UserDefaultsRepository.infoNames.value.count {
            self.tableData.append(infoData(name:UserDefaultsRepository.infoNames.value[i], value:""))
        }
        createDerivedData()
        
        smallGraphHeightConstraint.constant = CGFloat(UserDefaultsRepository.smallGraphHeight.value)
        self.view.layoutIfNeeded()
      
        // TODO: need non-us server ?
        let shareUserName = UserDefaultsRepository.shareUserName.value
        let sharePassword = UserDefaultsRepository.sharePassword.value
        let shareServer = UserDefaultsRepository.shareServer.value == "US" ?KnownShareServers.US.rawValue : KnownShareServers.NON_US.rawValue
        dexShare = ShareClient(username: shareUserName, password: sharePassword, shareServer: shareServer )
        
        //print("Share: \(dexShare)")
        
        // setup show/hide small graph and stats
        BGChartFull.isHidden = !UserDefaultsRepository.showSmallGraph.value
        statsView.isHidden = !UserDefaultsRepository.showStats.value
        
        BGChart.delegate = self
        BGChartFull.delegate = self
        
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
            self.tabBarController?.overrideUserInterfaceStyle = .dark
        }
        // Disable the snoozer tab unless an alarm is active
        //let tabBarControllerItems = self.tabBarController?.tabBar.items
        //if let arrayOfTabBarItems = tabBarControllerItems as AnyObject as? NSArray{
        //    snoozeTabItem = arrayOfTabBarItems[2] as! UITabBarItem
        //}
        //snoozeTabItem.isEnabled = false;
        
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
        
        // Load Startup Data
        restartAllTimers()
        
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("refresh"), object: nil)
        
        // Check UserDefaults and change text color if needed
            if UserDefaultsRepository.colorBGText.value {
                for view in highStack.arrangedSubviews {
                    if let label = view as? UILabel {
                        label.textColor = .systemPurple
                    }
                }
            }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("refresh"), object: nil)
    }
    
    // Clean all timers and start new ones when refreshing
    @objc func refresh() {
        print("Refreshing")
        MinAgoText.text = "Refreshing"
        invalidateTimers()
        restartAllTimers()
        currentCage = nil
        currentSage = nil
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
                createDerivedData()
                self.infoTable.reloadData()
                
                // reset
                appState.infoDataSettingsChanged = false
            }
            
            // add more processing of the app state
        }
    }
    
    private func createDerivedData() {
        let currentCount = UserDefaultsRepository.infoSort.value.count
        if currentCount < self.tableData.count {
            for i in currentCount..<self.tableData.count {
                UserDefaultsRepository.infoSort.value.append(i)
            }
        }
        
        self.derivedTableData = []
        while UserDefaultsRepository.infoVisible.value.count < self.tableData.count {
            UserDefaultsRepository.infoVisible.value.append(false)
        }
        for i in 0..<self.tableData.count {
            if(UserDefaultsRepository.infoVisible.value[UserDefaultsRepository.infoSort.value[i]]) {
                self.derivedTableData.append(self.tableData[UserDefaultsRepository.infoSort.value[i]])
            }
        }
   }
   
    // Info Table Functions
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        //return tableData.count
        return derivedTableData.count
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LabelCell", for: indexPath)
        let values = derivedTableData[indexPath.row]
        cell.textLabel?.text = values.name
        cell.detailTextLabel?.text = values.value
        return cell
    }
    
    @objc func appMovedToBackground() {
        // Allow screen to turn off
        UIApplication.shared.isIdleTimerDisabled = false;
        
        // We want to always come back to the home screen
        tabBarController?.selectedIndex = 0
        
        // Cancel the current timer and start a fresh background timer using the settings value only if background task is enabled
        
        if UserDefaultsRepository.backgroundRefresh.value {
            BackgroundAlertManager.shared.startBackgroundAlert()
            backgroundTask.startBackgroundTask()
        }
        
    }

    @objc func appCameToForeground() {
        // reset screenlock state if needed
        UIApplication.shared.isIdleTimerDisabled = UserDefaultsRepository.screenlockSwitchState.value;
        
        // Cancel the background tasks, start a fresh timer
        if UserDefaultsRepository.backgroundRefresh.value {
            backgroundTask.stopBackgroundTask()
            BackgroundAlertManager.shared.stopBackgroundAlert()
        }
        
        restartAllTimers()

    }
    
    @objc override func viewDidAppear(_ animated: Bool) {
        showHideNSDetails()
    }
       
/*
    //update Min Ago Text. We need to call this separately because it updates between readings
    func updateMinAgo(){
        if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Update min ago text") }
        guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
        if bgData.count > 0 {
            let deltaTime = (TimeInterval(Date().timeIntervalSince1970)-bgData[bgData.count - 1].date) / 60
            minAgoBG = Double(TimeInterval(Date().timeIntervalSince1970)-bgData[bgData.count - 1].date)
            MinAgoText.text = String(Int(deltaTime)) + " m sedan"
            snoozer.MinAgoLabel.text = String(Int(deltaTime)) + " m sedan"
            latestMinAgoString = String(Int(deltaTime)) + " m sedan"
        } else {
            MinAgoText.text = ""
            snoozer.MinAgoLabel.text = ""
            latestMinAgoString = ""
        }
        
    }
  */  
    //Clear the info data before next pull. This ensures we aren't displaying old data if something fails.
    func clearLastInfoData(index: Int){
        tableData[index].value = ""
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
        if UserDefaultsRepository.url.value == "" {
            isHidden = true
            isEnabled = false
        }
        
        LoopStatusLabel.isHidden = isHidden
        PredictionLabel.isHidden = isHidden
        infoTable.isHidden = isHidden
        
        if UserDefaultsRepository.hideInfoTable.value {
            infoTable.isHidden = true
        }
        
        if UserDefaultsRepository.url.value != "" {
            isEnabled = true
        }
        
        guard let nightscoutTab = self.tabBarController?.tabBar.items![3] else { return }
        nightscoutTab.isEnabled = isEnabled
        
    }
    
    func updateBadge(val: Int) {
        if UserDefaultsRepository.appBadge.value {
            let latestBG = String(val)
            UIApplication.shared.applicationIconBadgeNumber = Int(bgUnits.removePeriodAndCommaForBadge(bgUnits.toDisplayUnits(latestBG))) ?? val
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    

    func setBGTextColor() {
        if bgData.count > 0 {
            guard let snoozer = self.tabBarController?.viewControllers?[2] as? SnoozeViewController else { return }
            let latestBG = bgData[bgData.count - 1].sgv
            var color: UIColor = .label // Default color
            
            //Daniel: When toggle is off -> show  ordinary red-green-yellow BGText color. When toggle on, show Auggies dynamic colors
            if !UserDefaultsRepository.colorBGText.value {
                if let loopYellow = UIColor(named: "LoopYellow") {
                    if Float(latestBG) >= UserDefaultsRepository.highLine.value {
                        color = loopYellow
                    }
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
            } else {
                
                // Auggies color-thing - Define the hue values for the key points
                let redHue: CGFloat = 0.0 / 360.0       // 0 degrees
                let greenHue: CGFloat = 120.0 / 360.0   // 120 degrees
                let purpleHue: CGFloat = 270.0 / 360.0  // 270 degrees
                
                // Define the bgLevel thresholds
                let minLevel = Int(UserDefaultsRepository.alertUrgentLowBG.value)
                let targetLevel = Int(UserDefaultsRepository.targetLine.value)
                let maxLevel = Int(UserDefaultsRepository.alertUrgentHighBG.value)
                // Calculate the hue based on the bgLevel
                var hue: CGFloat
                if latestBG <= minLevel {
                    hue = redHue
                } else if latestBG >= maxLevel {
                    hue = purpleHue
                } else if latestBG <= targetLevel {
                    // Interpolate between red and green
                    let ratio = CGFloat(latestBG - minLevel) / CGFloat(targetLevel - minLevel)
                    hue = redHue + ratio * (greenHue - redHue)
                } else {
                    // Interpolate between green and purple
                    let ratio = CGFloat(latestBG - targetLevel) / CGFloat(maxLevel - targetLevel)
                    hue = greenHue + ratio * (purpleHue - greenHue)
                }
                
                // Return the color with full saturation and brightness
                color = UIColor(hue: hue, saturation: 0.9, brightness: 0.9, alpha: 1.0)
            }
            
            BGText.textColor = color
            snoozer.BGLabel.textColor = color
        }
    }
    
    func bgDirectionGraphic(_ value:String)->String
    {
        if value == nil { return "-" }
        let //graphics:[String:String]=["Flat":"\u{2192}","DoubleUp":"\u{21C8}","SingleUp":"\u{2191}","FortyFiveUp":"\u{2197}\u{FE0E}","FortyFiveDown":"\u{2198}\u{FE0E}","SingleDown":"\u{2193}","DoubleDown":"\u{21CA}","None":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-"]
        graphics:[String:String]=["Flat":"→","DoubleUp":"↑↑","SingleUp":"↑","FortyFiveUp":"↗","FortyFiveDown":"↘︎","SingleDown":"↓","DoubleDown":"↓↓","None":"-","NONE":"-","NOT COMPUTABLE":"-","RATE OUT OF RANGE":"-", "": "-"]
        return graphics[value]!
    }

    func writeCalendar() {
        if UserDefaultsRepository.debugLog.value {
            self.writeDebugLog(value: "Write calendar start")
        }
        
        self.store.requestCalendarAccess { (granted, error) in
            if !granted {
                print("Failed to get calendar access: \(String(describing: error))")
                return
            }
            self.processCalendarUpdates()
        }
    }
    
    func processCalendarUpdates() {
        if UserDefaultsRepository.calendarIdentifier.value == "" { return }
        
        if self.bgData.count < 1 { return }
            
        // This lets us fire the method to write Min Ago entries only once a minute starting after 6 minutes but allows new readings through
        if self.lastCalDate == self.bgData[self.bgData.count - 1].date
            && (self.calTimer.isValid || (dateTimeUtils.getNowTimeIntervalUTC() - self.lastCalDate) < 360) {
            return
        }

            // Create Event info
        var deltaBG = 0 // protect index out of bounds
        if self.bgData.count > 1 {
            deltaBG = self.bgData[self.bgData.count - 1].sgv -  self.bgData[self.bgData.count - 2].sgv as Int
        }
            let deltaTime = (TimeInterval(Date().timeIntervalSince1970) - self.bgData[self.bgData.count - 1].date) / 60
            var deltaString = ""
            if deltaBG < 0 {
                deltaString = bgUnits.toDisplayUnits(String(deltaBG))
            }
            else
            {
                deltaString = "+" + bgUnits.toDisplayUnits(String(deltaBG))
            }
            let direction = self.bgDirectionGraphic(self.bgData[self.bgData.count - 1].direction ?? "")
            
            let eventStartDate = Date(timeIntervalSince1970: self.bgData[self.bgData.count - 1].date)
//                if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Calendar start date") }
            var eventEndDate = eventStartDate.addingTimeInterval(60 * 10)
            var  eventTitle = UserDefaultsRepository.watchLine1.value
            var  eventLocation = UserDefaultsRepository.watchLine2.value
            //if (UserDefaultsRepository.watchLine2.value.count > 1) {
                //eventLocation += UserDefaultsRepository.watchLine2.value
            //<}
            // Replace commas in bgUnits result with periods
            let bgDisplayUnits = bgUnits.toDisplayUnits(String(self.bgData[self.bgData.count - 1].sgv)).replacingOccurrences(of: ",", with: ".")
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

        let fifteenMin = (lastSGV + deltaBGValue * 2.5) * 0.0555
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
            
            var cob = "0"
            if self.latestCOB != "" {
                cob = self.latestCOB
            }
            var basal = "~"
            if self.latestBasal != "" {
                basal = self.latestBasal
            }
            var iob = "0"
            if self.latestIOB != "" {
                iob = self.latestIOB
            }
            eventTitle = eventTitle.replacingOccurrences(of: "%MINAGO%", with: minAgo)
        eventLocation = eventLocation.replacingOccurrences(of: "%IOB%", with: iob)
        eventLocation = eventLocation.replacingOccurrences(of: "%COB%", with: cob)
        eventLocation = eventLocation.replacingOccurrences(of: "%BASAL%", with: basal + "E/h")
        
            
            
            
            
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
                        //if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Calendar Delete") }
                    } catch let error {
                        //if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Error - Calendar Delete") }
                        print(error)
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
                self.calTimer.invalidate()
                self.startCalTimer(time: (60 * 1))
                
                self.lastCalDate = self.bgData[self.bgData.count - 1].date
                //if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Calendar Write: " + eventTitle) }
                //UserDefaultsRepository.savedEventID.value = event.eventIdentifier //save event id to access this particular event later
            } catch {
                print("*** Error storing to the calendar")
                // Display error to user
                //if UserDefaultsRepository.debugLog.value { self.writeDebugLog(value: "Error: Calendar Write") }
            }
    }
    
    
    func persistentNotification(bgTime: TimeInterval)
    {
        if UserDefaultsRepository.persistentNotification.value && bgTime > UserDefaultsRepository.persistentNotificationLastBGTime.value && bgData.count > 0 {
            guard let snoozer = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            snoozer.sendNotification(self, bgVal: bgUnits.toDisplayUnits(String(bgData[bgData.count - 1].sgv)), directionVal: latestDirectionString, deltaVal: bgUnits.toDisplayUnits(String(latestDeltaString)), minAgoVal: latestMinAgoString, alertLabelVal: "Latest BG")
        }
    }
    
    func writeDebugLog(value: String) {
        DispatchQueue.main.async {
            var logText = "\n" + dateTimeUtils.printNow() + " - " + value
            print(logText)
            guard let debug = self.tabBarController!.viewControllers?[2] as? SnoozeViewController else { return }
            if debug.debugTextView.text.lengthOfBytes(using: .utf8) > 20000 {
                debug.debugTextView.text = ""
                    }
            debug.debugTextView.text += logText
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
}
