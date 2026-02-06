import Foundation
import Combine

class AlarmViewModel {
        let categoryOptions = ["Hög/Låg", "Trend", "Trio", "Teknik", "Övrigt"]
        
        let alertBGOptions = ["Akut låg", "Låg", "Hög", "Akut hög"]
        let alertExtraBGOptions = ["Sjunker snabbt", "Stiger snabbt", "Tillfälligt"]
        let alertSystemOptions = ["Saknar värden", "Loopar inte", "Lågt batteri"]
        let alertHardwareOptions = ["Sensorbyte", "Pumpbyte", "Reservoar"]
        let alertOtherOptions = ["COB", "IOB", "Missad bolus"]
    
    // State för UI
    @Published var selectedCategoryIndex: Int = 0
    @Published var selectedSubCategoryIndex: Int = 0 // Hanterar logiken mellan bgAlerts, otherAlerts etc.
    
    // Data Source Snapshot Data
    var sections: [AlarmSection] = []
    
    // Mockup för datan (Här anropar du din UserDefaultsRepository)
    // I din kod: UserDefaultsRepository.shared...
    
    // MARK: - Logik för att bygga vyn
    func updateSnapshotData() {
        sections = []
        
        // 1. Globala inställningar visas ofta alltid
        sections.append(.globalSettings)
        
        // 2. Hämta namnet på det valda larmet baserat på huvudkategori och underkategori
        let activeAlarmName: String
        switch selectedCategoryIndex {
        case 0: // BG Alerts
            activeAlarmName = alertBGOptions[selectedSubCategoryIndex]
        case 1: // Extra BG Alerts
            activeAlarmName = alertExtraBGOptions[selectedSubCategoryIndex]
        case 2: // Trio Alerts
            activeAlarmName = alertSystemOptions[selectedSubCategoryIndex]
        case 3: // Hardware Alerts
            activeAlarmName = alertHardwareOptions[selectedSubCategoryIndex]
        case 4: // Other Alerts
            activeAlarmName = alertOtherOptions[selectedSubCategoryIndex]
        default:
            activeAlarmName = ""
        }
        
        if !activeAlarmName.isEmpty {
            sections.append(.specificAlarm("\(activeAlarmName)"))
        }
        
        // 3. Nattinställningar
        sections.append(.nightSettings)
    }
    
    // MARK: - Helpers to get rows for a section
    func rows(for section: AlarmSection) -> [AlarmRow] {
        switch section {
        case .categorySelection:
            return [.segmentControl]
            
        case .globalSettings:
            // Hämtar värden från UserDefaultsRepository för de globala sektionerna
            let storedSnoozeTime = UserDefaultsRepository.alertSnoozeAllTime.value
            let isSnoozed = UserDefaultsRepository.alertSnoozeAllIsSnoozed.value
            // Om toggeln är av vill vi *inte* visa sista datumet, precis som i gamla Eureka-vyn
            let snoozeTime = isSnoozed ? storedSnoozeTime : nil

            let storedMuteTime = UserDefaultsRepository.alertMuteAllTime.value
            let isMuted = UserDefaultsRepository.alertMuteAllIsMuted.value
            let muteTime = isMuted ? storedMuteTime : nil

            var rows: [AlarmRow] = []

            // Snooze All rader
            rows.append(.dateValue(title: "Snooza alla larm till", date: snoozeTime, id: "alertSnoozeAllTime"))
            if snoozeTime != nil {
                rows.append(.toggle(title: "Alla larm snoozade", isOn: isSnoozed, id: "alertSnoozeAllIsSnoozed"))
            }

            // Mute All rader
            rows.append(.dateValue(title: "Tysta alla larm till", date: muteTime, id: "alertMuteAllTime"))
            if muteTime != nil {
                rows.append(.toggle(title: "Alla larm tystade", isOn: isMuted, id: "alertMuteAllIsMuted"))
            }

            return rows
            
        case .specificAlarm(let name):
            switch name {
            case "Akut låg":
                return getUrgentLowAlertRows()
            case "Låg":
                return getLowAlertRows()
            case "Hög":
                return getHighAlertRows()
            case "Akut hög":
                return getUrgentHighAlertRows()
            case "Sjunker snabbt":
                return getFastDropAlertRows()
            case "Stiger snabbt":
                return getFastRiseAlertRows()
            case "Tillfälligt":
                return getTemporaryAlertRows()
            // Trio-segment alarms
            case "Saknar värden":
                return getMissingReadingsAlertRows()
            case "Loopar inte":
                return getNotLoopingAlertRows()
            case "Lågt batteri":
                return getLowBatteryAlertRows()
            case "Sensorbyte":
                return getSAgeAlertRows()
            case "Pumpbyte":
                return getCAgeAlertRows()
            case "Reservoar":
                return getReservoirAlertRows()
            case "COB":
                return getCOBAlertRows()
            case "IOB":
                return getIOBAlertRows()
            case "Missad bolus":
                return getMissedBolusAlertRows()
            default:
                return []
            }
            
        case .nightSettings:
            return getNightSettingsRows()
        }
    

    // MARK: - Formatters
    func formatGlucoseValue(_ value: Double) -> String {
        let isMmol = UserDefaultsRepository.units.value == "mmol/L"
        if isMmol {
            // Omräkning från mg/dL till mmol/L (delat med 18.0182)
            let mmolValue = value / 18.0182
            return String(format: "%.1f", mmolValue)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    // MARK: - Urgent Low Alert Logic
    func getUrgentLowAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let units = UserDefaultsRepository.units.value ?? "mg/dL"
        let isActive = UserDefaultsRepository.alertUrgentLowActive.value

        // 1. Active Switch
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "urgent_low_active"))
        guard isActive else { return rows }

        // 2. BG Level (Stepper)
        let bgValue = Double(UserDefaultsRepository.alertUrgentLowBG.value)
        rows.append(.valueStepper(
            title: "Glukos",
            value: bgValue,
            min: 40,
            max: 80,
            step: (units == "mmol/L" ? 0.1 : 1.0),
            unit: "",
            id: "urgent_low_bg"
        ))

        // 3. Predictive Minutes
        rows.append(.valueStepper(
            title: "Prediktivt",
            value: Double(UserDefaultsRepository.alertUrgentLowPredictiveMinutes.value),
            min: 0,
            max: 60,
            step: 5,
            unit: " min",
            id: "urgent_low_predictive"
        ))

        // 4. Default Snooze
        rows.append(.valueStepper(
            title: "Snooze",
            value: Double(UserDefaultsRepository.alertUrgentLowSnooze.value),
            min: 5,
            max: 15,
            step: 5,
            unit: " min",
            id: "urgent_low_snooze"
        ))

        // 5. Sound Selection
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertUrgentLowSound.value ?? "Default",
            id: "urgent_low_sound"
        ))

        // 6. Play Sound (Always, At Night, etc.)
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertUrgentLowAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "urgent_low_audible"
        ))

        // 7. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertUrgentLowRepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "urgent_low_repeat"
        ))

        // 8. Pre-Snooze (AutoSnooze)
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertUrgentLowAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "urgent_low_autosnooze"
        ))

        // 9. Snoozed Until (Date)
        // Visar "Ej snoozad" om toggeln är av (även om det finns ett gammalt datum lagrat)
        let storedSnoozedTime = UserDefaultsRepository.alertUrgentLowSnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertUrgentLowIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "urgent_low_snoozed_time"))

        if snoozedTime != nil {
            rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "urgent_low_is_snoozed"))
        }

        return rows
    }
    
        // MARK: - Low Alert Logic
        func getLowAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertLowActive.value
            
            // 1. Active Switch
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "low_active"))
            guard isActive else { return rows }
            
            // 2. BG Level (Stepper)
            let bgValue = Double(UserDefaultsRepository.alertLowBG.value)
            rows.append(.valueStepper(
                title: "Glukos",
                value: bgValue,
                min: 40, max: 150, step: (units == "mmol/L" ? 0.1 : 1.0), // Stega 0.1 om mmol
                unit: "",
                id: "low_bg"
            ))
            
            // 3. Persistent For (Minutes)
            rows.append(.valueStepper(
                title: "Varit låg i",
                value: Double(UserDefaultsRepository.alertLowPersistent.value),
                min: 0, max: 240, step: 5, unit: " min", id: "low_persistent"
            ))
            
            // 4. Ignore Persistence (-Delta)
            let deltaValue = Double(UserDefaultsRepository.alertLowPersistenceMax.value)
            rows.append(.valueStepper(
                title: "Direktlarm vid -Δ",
                value: deltaValue,
                min: 0, max: 20, step: 1,
                unit: "",
                id: "low_persistence_max"
            ))
            
            // 5. Default Snooze Time
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertLowSnooze.value),
                min: 5, max: 30, step: 5,
                unit: " min",
                id: "low_snooze"
            ))
            
            // 6. Sound Selection
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertLowSound.value ?? "Default",
                id: "low_sound"
            ))
            
            // 7. Play Sound (Always, At Night, etc.)
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertLowAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "low_audible"
            ))
            
            // 8. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertLowRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "low_repeat"
            ))
            
            // 9. Pre-Snooze (AutoSnooze)
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertLowAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "low_autosnooze"
            ))
            
            // 10. Snoozed Until (Date)
            // Visar "Ej snoozad" om toggeln är av (även om det finns ett gammalt datum lagrat)
            let storedSnoozedTime = UserDefaultsRepository.alertLowSnoozedTime.value
            let isLowSnoozed = UserDefaultsRepository.alertLowIsSnoozed.value
            let snoozedTime = isLowSnoozed ? storedSnoozedTime : nil
            
            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "low_snoozed_time"))
            
            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isLowSnoozed, id: "low_is_snoozed"))
            }
            
            return rows
        }

        // MARK: - High Alert Logic
        func getHighAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertHighActive.value

            // 1. Active Switch
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "high_active"))
            guard isActive else { return rows }

            // 2. BG Level (Stepper)
            let bgValue = Double(UserDefaultsRepository.alertHighBG.value)
            rows.append(.valueStepper(
                title: "Glukos",
                value: bgValue,
                min: 120,
                max: 300,
                step: (units == "mmol/L" ? 0.1 : 1.0),
                unit: "",
                id: "high_bg"
            ))

            // 3. Persistent For (Minutes)
            rows.append(.valueStepper(
                title: "Varit hög i",
                value: Double(UserDefaultsRepository.alertHighPersistent.value),
                min: 0,
                max: 120,
                step: 1,
                unit: " min",
                id: "high_persistent"
            ))

            // 4. Default Snooze Time
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertHighSnooze.value),
                min: 10,
                max: 120,
                step: 5,
                unit: " min",
                id: "high_snooze"
            ))

            // 5. Sound Selection
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertHighSound.value ?? "Default",
                id: "high_sound"
            ))

            // 6. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertHighAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "high_audible"
            ))

            // 7. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertHighRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "high_repeat"
            ))

            // 8. Pre-Snooze (AutoSnooze)
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertHighAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "high_autosnooze"
            ))

            // 9. Snoozed Until (Date)
            let storedSnoozedTime = UserDefaultsRepository.alertHighSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertHighIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "high_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "high_is_snoozed"))
            }

            return rows
        }

        // MARK: - Urgent High Alert Logic
        func getUrgentHighAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertUrgentHighActive.value

            // 1. Active Switch
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "urgent_high_active"))
            guard isActive else { return rows }

            // 2. BG Level (Stepper)
            let bgValue = Double(UserDefaultsRepository.alertUrgentHighBG.value)
            rows.append(.valueStepper(
                title: "Glukos",
                value: bgValue,
                min: 120,
                max: 350,
                step: (units == "mmol/L" ? 0.1 : 1.0),
                unit: "",
                id: "urgent_high_bg"
            ))

            // 3. Default Snooze Time
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertUrgentHighSnooze.value),
                min: 10,
                max: 120,
                step: 5,
                unit: " min",
                id: "urgent_high_snooze"
            ))

            // 4. Sound Selection
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertUrgentHighSound.value ?? "Default",
                id: "urgent_high_sound"
            ))

            // 5. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertUrgentHighAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "urgent_high_audible"
            ))

            // 6. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertUrgentHighRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "urgent_high_repeat"
            ))

            // 7. Pre-Snooze (AutoSnooze)
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertUrgentHighAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "urgent_high_autosnooze"
            ))

            // 8. Snoozed Until (Date)
            let storedSnoozedTime = UserDefaultsRepository.alertUrgentHighSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertUrgentHighIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "urgent_high_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "urgent_high_is_snoozed"))
            }

            return rows
        }
        
        // MARK: - Missing Readings Alert Logic
        func getMissingReadingsAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let isActive = UserDefaultsRepository.alertMissedReadingActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "missing_readings_active"))
            guard isActive else { return rows }

            // 2. Time without readings (minutes)
            rows.append(.valueStepper(
                title: "Tid utan värden",
                value: Double(UserDefaultsRepository.alertMissedReading.value),
                min: 11,
                max: 121,
                step: 5,
                unit: " min",
                id: "missing_readings_time"
            ))

            // 3. Snooze (minutes)
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertMissedReadingSnooze.value),
                min: 10,
                max: 180,
                step: 5,
                unit: " min",
                id: "missing_readings_snooze"
            ))

            // 4. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertMissedReadingSound.value ?? "Default",
                id: "missing_readings_sound"
            ))

            // 5. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertMissedReadingAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "missing_readings_audible"
            ))

            // 6. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertMissedReadingRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "missing_readings_repeat"
            ))

            // 7. Pre-Snooze
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertMissedReadingAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "missing_readings_autosnooze"
            ))

            // 8. Snoozed Until
            let storedSnoozedTime = UserDefaultsRepository.alertMissedReadingSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertMissedReadingIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "missing_readings_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "missing_readings_is_snoozed"))
            }

            return rows
        }

        // MARK: - Not Looping Alert Logic
        func getNotLoopingAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertNotLoopingActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "not_looping_active"))
            guard isActive else { return rows }

            // 2. Time (minutes since last successful loop)
            rows.append(.valueStepper(
                title: "Tid utan loop",
                value: Double(UserDefaultsRepository.alertNotLooping.value),
                min: 16,
                max: 61,
                step: 5,
                unit: " min",
                id: "not_looping_time"
            ))

            // 3. Use BG Limits
            let useLimits = UserDefaultsRepository.alertNotLoopingUseLimits.value
            rows.append(.toggle(title: "Använd BG-gränser", isOn: useLimits, id: "not_looping_use_limits"))

            // 4. If Below BG (optional)
            if useLimits {
                rows.append(.valueStepper(
                    title: "Om under glukos",
                    value: Double(UserDefaultsRepository.alertNotLoopingLowerLimit.value),
                    min: 50,
                    max: 200,
                    step: (units == "mmol/L" ? 0.1 : 1.0),
                    unit: "",
                    id: "not_looping_lower_limit"
                ))

                rows.append(.valueStepper(
                    title: "Om över glukos",
                    value: Double(UserDefaultsRepository.alertNotLoopingUpperLimit.value),
                    min: 100,
                    max: 300,
                    step: (units == "mmol/L" ? 0.1 : 1.0),
                    unit: "",
                    id: "not_looping_upper_limit"
                ))
            }

            // 5. Snooze
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertNotLoopingSnooze.value),
                min: 10,
                max: 120,
                step: 5,
                unit: " min",
                id: "not_looping_snooze"
            ))

            // 6. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertNotLoopingSound.value ?? "Default",
                id: "not_looping_sound"
            ))

            // 7. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertNotLoopingAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "not_looping_audible"
            ))

            // 8. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertNotLoopingRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "not_looping_repeat"
            ))

            // 9. Pre-Snooze
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertNotLoopingAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "not_looping_autosnooze"
            ))

            // 10. Snoozed Until
            let storedSnoozedTime = UserDefaultsRepository.alertNotLoopingSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertNotLoopingIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "not_looping_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "not_looping_is_snoozed"))
            }

            return rows
        }

        // MARK: - Low Battery Alert Logic
        func getLowBatteryAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let isActive = UserDefaultsRepository.alertBatteryActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "low_battery_active"))
            guard isActive else { return rows }

            // 2. Battery Level
            rows.append(.valueStepper(
                title: "Batterinivå",
                value: Double(UserDefaultsRepository.alertBatteryLevel.value),
                min: 0,
                max: 100,
                step: 5,
                unit: " %",
                id: "low_battery_level"
            ))

            // 3. Snooze Hours
            rows.append(.valueStepper(
                title: "Snooze (timmar)",
                value: Double(UserDefaultsRepository.alertBatterySnoozeHours.value),
                min: 1,
                max: 24,
                step: 1,
                unit: " h",
                id: "low_battery_snooze_hours"
            ))

            // 4. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertBatterySound.value ?? "Default",
                id: "low_battery_sound"
            ))

            // 5. Repeat Sound (simple on/off)
            rows.append(.toggle(
                title: "Repetera ljud",
                isOn: UserDefaultsRepository.alertBatteryRepeat.value,
                id: "low_battery_repeat"
            ))

            return rows
        }

        
        // MARK: - Fast Drop Alert Logic
        func getFastDropAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertFastDropActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "fast_drop_active"))
            guard isActive else { return rows }

            // 2. Delta
            rows.append(.valueStepper(
                title: "Delta sjunkning",
                value: Double(UserDefaultsRepository.alertFastDropDelta.value),
                min: 3,
                max: 20,
                step: (units == "mmol/L" ? 0.1 : 1.0),
                unit: "",
                id: "fast_drop_delta"
            ))

            // 3. # Readings
            rows.append(.valueStepper(
                title: "Mätningar",
                value: Double(UserDefaultsRepository.alertFastDropReadings.value),
                min: 2,
                max: 4,
                step: 1,
                unit: " st",
                id: "fast_drop_readings"
            ))

            // 4. Use BG Limit
            let useLimit = UserDefaultsRepository.alertFastDropUseLimit.value
            rows.append(.toggle(title: "Använd BG-gräns", isOn: useLimit, id: "fast_drop_use_limit"))

            // 5. Dropping below BG (optional)
            if useLimit {
                rows.append(.valueStepper(
                    title: "Sjunker under BG",
                    value: Double(UserDefaultsRepository.alertFastDropBelowBG.value),
                    min: 40,
                    max: 300,
                    step: (units == "mmol/L" ? 0.1 : 1.0),
                    unit: "",
                    id: "fast_drop_below_bg"
                ))
            }

            // 6. Snooze
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertFastDropSnooze.value),
                min: 5,
                max: 60,
                step: 5,
                unit: " min",
                id: "fast_drop_snooze"
            ))

            // 7. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertFastDropSound.value ?? "Default",
                id: "fast_drop_sound"
            ))

            // 8. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertFastDropAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "fast_drop_audible"
            ))

            // 9. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertFastDropRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "fast_drop_repeat"
            ))

            // 10. Pre-Snooze
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertFastDropAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "fast_drop_autosnooze"
            ))

            // 11. Snoozed Until
            let storedSnoozedTime = UserDefaultsRepository.alertFastDropSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertFastDropIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "fast_drop_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "fast_drop_is_snoozed"))
            }

            return rows
        }

        // MARK: - Fast Rise Alert Logic
        func getFastRiseAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let units = UserDefaultsRepository.units.value ?? "mg/dL"
            let isActive = UserDefaultsRepository.alertFastRiseActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "fast_rise_active"))
            guard isActive else { return rows }

            // 2. Delta
            rows.append(.valueStepper(
                title: "Delta stigning",
                value: Double(UserDefaultsRepository.alertFastRiseDelta.value),
                min: 3,
                max: 20,
                step: (units == "mmol/L" ? 0.1 : 1.0),
                unit: "",
                id: "fast_rise_delta"
            ))

            // 3. # Readings
            rows.append(.valueStepper(
                title: "Mätningar",
                value: Double(UserDefaultsRepository.alertFastRiseReadings.value),
                min: 2,
                max: 4,
                step: 1,
                unit: " st",
                id: "fast_rise_readings"
            ))

            // 4. Use BG Limit
            let useLimit = UserDefaultsRepository.alertFastRiseUseLimit.value
            rows.append(.toggle(title: "Använd BG-gräns", isOn: useLimit, id: "fast_rise_use_limit"))

            // 5. Rising above BG (optional)
            if useLimit {
                rows.append(.valueStepper(
                    title: "Stiger över BG",
                    value: Double(UserDefaultsRepository.alertFastRiseAboveBG.value),
                    min: 40,
                    max: 300,
                    step: (units == "mmol/L" ? 0.1 : 1.0),
                    unit: "",
                    id: "fast_rise_above_bg"
                ))
            }

            // 6. Snooze
            rows.append(.valueStepper(
                title: "Snooza",
                value: Double(UserDefaultsRepository.alertFastRiseSnooze.value),
                min: 5,
                max: 60,
                step: 5,
                unit: " min",
                id: "fast_rise_snooze"
            ))

            // 7. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertFastRiseSound.value ?? "Default",
                id: "fast_rise_sound"
            ))

            // 8. Play Sound
            rows.append(.optionPicker(
                title: "Spela larm",
                currentOption: UserDefaultsRepository.alertFastRiseAudible.value,
                options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
                id: "fast_rise_audible"
            ))

            // 9. Repeat Sound
            rows.append(.optionPicker(
                title: "Repetera larm",
                currentOption: UserDefaultsRepository.alertFastRiseRepeat.value,
                options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
                id: "fast_rise_repeat"
            ))

            // 10. Pre-Snooze
            rows.append(.optionPicker(
                title: "För-Snooza",
                currentOption: UserDefaultsRepository.alertFastRiseAutosnooze.value,
                options: ["Aldrig", "Nattetid", "Dagtid"],
                id: "fast_rise_autosnooze"
            ))

            // 11. Snoozed Until
            let storedSnoozedTime = UserDefaultsRepository.alertFastRiseSnoozedTime.value
            let isSnoozed = UserDefaultsRepository.alertFastRiseIsSnoozed.value
            let snoozedTime = isSnoozed ? storedSnoozedTime : nil

            rows.append(.dateValue(title: "Snoozad till", date: snoozedTime, id: "fast_rise_snoozed_time"))

            if snoozedTime != nil {
                rows.append(.toggle(title: "Är snoozad", isOn: isSnoozed, id: "fast_rise_is_snoozed"))
            }

            return rows
        }

        // MARK: - Temporary Alert Logic
        func getTemporaryAlertRows() -> [AlarmRow] {
            var rows: [AlarmRow] = []
            let isActive = UserDefaultsRepository.alertTemporaryActive.value

            // 1. Active
            rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "temporary_active"))
            guard isActive else { return rows }

            // 2. Alert Below BG (if off => treat as high alert above BG)
            rows.append(.toggle(title: "Larma under glukos", isOn: UserDefaultsRepository.alertTemporaryBelow.value, id: "temporary_below"))

            // 3. BG threshold
            rows.append(.valueStepper(
                title: "Glukos",
                value: Double(UserDefaultsRepository.alertTemporaryBG.value),
                min: 40,
                max: 400,
                step: 1,
                unit: "",
                id: "temporary_bg"
            ))

            // 4. Sound
            rows.append(.soundPicker(
                title: "Larmljud",
                currentSound: UserDefaultsRepository.alertTemporarySound.value ?? "Default",
                id: "temporary_sound"
            ))

            // 5. Repeat Sound (simple on/off)
            rows.append(.toggle(title: "Repetera ljud", isOn: UserDefaultsRepository.alertTemporaryBGRepeat.value, id: "temporary_repeat"))

            return rows
        }
    }
    
    // MARK: - SAGE (Sensorbyte) Alert Logic
    func getSAgeAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let isActive = UserDefaultsRepository.alertSAGEActive.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "sage_active"))
        guard isActive else { return rows }

        // 2. Time (hours before sensor change)
        rows.append(.valueStepper(
            title: "Tid före byte",
            value: Double(UserDefaultsRepository.alertSAGE.value),
            min: 1,
            max: 24,
            step: 1,
            unit: " h",
            id: "sage_time"
        ))

        // 3. Snooze (hours)
        rows.append(.valueStepper(
            title: "Snooze (timmar)",
            value: Double(UserDefaultsRepository.alertSAGESnooze.value),
            min: 1,
            max: 24,
            step: 1,
            unit: " h",
            id: "sage_snooze"
        ))

        // 4. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertSAGESound.value ?? "Default",
            id: "sage_sound"
        ))

        // 5. Play Sound (dag/natt/alltid)
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertSAGEAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "sage_audible"
        ))

        // 6. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertSAGERepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "sage_repeat"
        ))

        // 7. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertSAGEAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "sage_autosnooze"
        ))

        // 8. Snoozad till
        let storedSnoozedTime = UserDefaultsRepository.alertSAGESnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertSAGEIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "sage_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "sage_is_snoozed"
            ))
        }

        return rows
    }

    // MARK: - CAGE (Pumpbyte) Alert Logic
    func getCAgeAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let isActive = UserDefaultsRepository.alertCAGEActive.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "cage_active"))
        guard isActive else { return rows }

        // 2. Time (hours before canula/pump change)
        rows.append(.valueStepper(
            title: "Tid före byte",
            value: Double(UserDefaultsRepository.alertCAGE.value),
            min: 1,
            max: 24,
            step: 1,
            unit: " h",
            id: "cage_time"
        ))

        // 3. Snooze (hours)
        rows.append(.valueStepper(
            title: "Snooze (timmar)",
            value: Double(UserDefaultsRepository.alertCAGESnooze.value),
            min: 1,
            max: 24,
            step: 1,
            unit: " h",
            id: "cage_snooze"
        ))

        // 4. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertCAGESound.value ?? "Default",
            id: "cage_sound"
        ))

        // 5. Play Sound
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertCAGEAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "cage_audible"
        ))

        // 6. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertCAGERepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "cage_repeat"
        ))

        // 7. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertCAGEAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "cage_autosnooze"
        ))

        // 8. Snoozed Until
        let storedSnoozedTime = UserDefaultsRepository.alertCAGESnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertCAGEIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "cage_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "cage_is_snoozed"
            ))
        }

        return rows
    }

    // MARK: - Pump / Reservoar Alert Logic
    func getReservoirAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let isActive = UserDefaultsRepository.alertPump.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "reservoir_active"))
        guard isActive else { return rows }

        // 2. Units Remaining
        rows.append(.valueStepper(
            title: "Enheter kvar",
            value: Double(UserDefaultsRepository.alertPumpAt.value),
            min: 1,
            max: 49,
            step: 1,
            unit: " E",
            id: "reservoir_units"
        ))

        // 3. Snooze Hours
        rows.append(.valueStepper(
            title: "Snooze (timmar)",
            value: Double(UserDefaultsRepository.alertPumpSnoozeHours.value),
            min: 1,
            max: 24,
            step: 1,
            unit: " h",
            id: "reservoir_snooze_hours"
        ))

        // 4. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertPumpSound.value ?? "Default",
            id: "reservoir_sound"
        ))

        // 5. Play Sound
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertPumpAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "reservoir_audible"
        ))

        // 6. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertPumpRepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "reservoir_repeat"
        ))

        // 7. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertPumpAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "reservoir_autosnooze"
        ))

        // 8. Snoozed Until
        let storedSnoozedTime = UserDefaultsRepository.alertPumpSnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertPumpIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "reservoir_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "reservoir_is_snoozed"
            ))
        }

        return rows
    }
    
    // MARK: - COB Alert Logic
    func getCOBAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let isActive = UserDefaultsRepository.alertCOB.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "cob_active"))
        guard isActive else { return rows }

        // 2. COB threshold
        rows.append(.valueStepper(
            title: "COB ≥",
            value: Double(UserDefaultsRepository.alertCOBAt.value),
            min: 1,
            max: 200,
            step: 1,
            unit: " g",
            id: "cob_at"
        ))

        // 3. Snooze (hours)
        rows.append(.valueStepper(
            title: "Snooze",
            value: Double(UserDefaultsRepository.alertCOBSnoozeHours.value),
            min: 1,
            max: 6,
            step: 1,
            unit: " h",
            id: "cob_snooze_hours"
        ))

        // 4. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertCOBSound.value ?? "Default",
            id: "cob_sound"
        ))

        // 5. Play Sound
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertCOBAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "cob_audible"
        ))

        // 6. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertCOBRepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "cob_repeat"
        ))

        // 7. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertCOBAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "cob_autosnooze"
        ))

        // 8. Snoozad till
        let storedSnoozedTime = UserDefaultsRepository.alertCOBSnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertCOBIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "cob_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "cob_is_snoozed"
            ))
        }

        return rows
    }
    
    // MARK: - IOB Alert Logic
    func getIOBAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let isActive = UserDefaultsRepository.alertIOB.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "iob_active"))
        guard isActive else { return rows }

        // 2. Bolus size threshold
        rows.append(.valueStepper(
            title: "Enskild bolus ≥",
            value: Double(UserDefaultsRepository.alertIOBAt.value),
            min: 0.1,
            max: 50,
            step: 0.1,
            unit: " E",
            id: "iob_at"
        ))

        // 3. Number of boluses
        rows.append(.valueStepper(
            title: "Antal bolusar ≥",
            value: Double(UserDefaultsRepository.alertIOBNumber.value),
            min: 1,
            max: 10,
            step: 1,
            unit: " st",
            id: "iob_number"
        ))

        // 4. Within minutes
        rows.append(.valueStepper(
            title: "Inom",
            value: Double(UserDefaultsRepository.alertIOBBolusesWithin.value),
            min: 5,
            max: 120,
            step: 5,
            unit: " min",
            id: "iob_within"
        ))

        // 5. Or total IOB
        rows.append(.valueStepper(
            title: "Eller total IOB ≥",
            value: Double(UserDefaultsRepository.alertIOBMaxBoluses.value),
            min: 1,
            max: 20,
            step: 1,
            unit: " E",
            id: "iob_max_boluses"
        ))

        // 6. Snooze (hours)
        rows.append(.valueStepper(
            title: "Snooze",
            value: Double(UserDefaultsRepository.alertIOBSnoozeHours.value),
            min: 1,
            max: 6,
            step: 1,
            unit: " h",
            id: "iob_snooze_hours"
        ))

        // 7. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertIOBSound.value ?? "Default",
            id: "iob_sound"
        ))

        // 8. Play Sound
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertIOBAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "iob_audible"
        ))

        // 9. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertIOBRepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "iob_repeat"
        ))

        // 10. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertIOBAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "iob_autosnooze"
        ))

        // 11. Snoozad till
        let storedSnoozedTime = UserDefaultsRepository.alertIOBSnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertIOBIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "iob_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "iob_is_snoozed"
            ))
        }

        return rows
    }
    
    // MARK: - Missed Bolus Alert Logic
    func getMissedBolusAlertRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        let units = UserDefaultsRepository.units.value ?? "mg/dL"
        let isActive = UserDefaultsRepository.alertMissedBolusActive.value

        // 1. Active
        rows.append(.toggle(title: "Aktiverat", isOn: isActive, id: "missed_bolus_active"))
        guard isActive else { return rows }

        // 2. Time after carbs without bolus
        rows.append(.valueStepper(
            title: "Tid efter måltid",
            value: Double(UserDefaultsRepository.alertMissedBolus.value),
            min: 5,
            max: 60,
            step: 5,
            unit: " min",
            id: "missed_bolus_time"
        ))

        // 3. Prebolus max time
        rows.append(.valueStepper(
            title: "Prebolus max tid",
            value: Double(UserDefaultsRepository.alertMissedBolusPrebolus.value),
            min: 5,
            max: 45,
            step: 5,
            unit: " min",
            id: "missed_bolus_prebolus_time"
        ))

        // 4. Ignore bolus under
        rows.append(.valueStepper(
            title: "Ignorera när bolus ≤",
            value: Double(UserDefaultsRepository.alertMissedBolusIgnoreBolus.value),
            min: 0.05,
            max: 2.0,
            step: 0.05,
            unit: " E",
            id: "missed_bolus_ignore_bolus"
        ))

        // 5. Ignore low-treatment carbs under grams
        rows.append(.valueStepper(
            title: "Ignorera när kh <",
            value: Double(UserDefaultsRepository.alertMissedBolusLowGrams.value),
            min: 0,
            max: 15,
            step: 1,
            unit: " g",
            id: "missed_bolus_low_grams"
        ))

        // 6. Ignore under BG
        rows.append(.valueStepper(
            title: "Ignorera när glukos <",
            value: Double(UserDefaultsRepository.alertMissedBolusLowGramsBG.value),
            min: 40,
            max: 100,
            step: (units == "mmol/L" ? 0.1 : 1.0),
            unit: "",
            id: "missed_bolus_low_grams_bg"
        ))

        // 7. Snooze
        rows.append(.valueStepper(
            title: "Snooza",
            value: Double(UserDefaultsRepository.alertMissedBolusSnooze.value),
            min: 5,
            max: 60,
            step: 5,
            unit: " min",
            id: "missed_bolus_snooze"
        ))

        // 8. Sound
        rows.append(.soundPicker(
            title: "Larmljud",
            currentSound: UserDefaultsRepository.alertMissedBolusSound.value ?? "Default",
            id: "missed_bolus_sound"
        ))

        // 9. Play Sound
        rows.append(.optionPicker(
            title: "Spela larm",
            currentOption: UserDefaultsRepository.alertMissedBolusAudible.value,
            options: ["Alltid", "Nattetid", "Dagtid", "Aldrig"],
            id: "missed_bolus_audible"
        ))

        // 10. Repeat Sound
        rows.append(.optionPicker(
            title: "Repetera larm",
            currentOption: UserDefaultsRepository.alertMissedBolusRepeat.value,
            options: ["Aldrig", "Alltid", "Nattetid", "Dagtid"],
            id: "missed_bolus_repeat"
        ))

        // 11. Pre-Snooze
        rows.append(.optionPicker(
            title: "För-Snooza",
            currentOption: UserDefaultsRepository.alertMissedBolusAutosnooze.value,
            options: ["Aldrig", "Nattetid", "Dagtid"],
            id: "missed_bolus_autosnooze"
        ))

        // 12. Snoozad till
        let storedSnoozedTime = UserDefaultsRepository.alertMissedBolusSnoozedTime.value
        let isSnoozed = UserDefaultsRepository.alertMissedBolusIsSnoozed.value
        let snoozedTime = isSnoozed ? storedSnoozedTime : nil

        rows.append(.dateValue(
            title: "Snoozad till",
            date: snoozedTime,
            id: "missed_bolus_snoozed_time"
        ))

        if snoozedTime != nil {
            rows.append(.toggle(
                title: "Är snoozad",
                isOn: isSnoozed,
                id: "missed_bolus_is_snoozed"
            ))
        }

        return rows
    }

    
    // MARK: - Night and General Settings Logic
    func getNightSettingsRows() -> [AlarmRow] {
        var rows: [AlarmRow] = []
        
        // --- Alarminställningar (General) ---
        let overrideVolume = UserDefaultsRepository.overrideSystemOutputVolume.value
        rows.append(.toggle(title: "Override systemvolym", isOn: overrideVolume, id: "overrideSystemOutputVolume"))
        
        // I getNightSettingsRows i din ViewModel
        if overrideVolume {
            // Vi skickar in talet som ett heltal mellan 0 och 100
            let volumePercent = (Double(UserDefaultsRepository.forcedOutputVolume.value) * 100).rounded()
            
            rows.append(.valueStepper(
                title: "Volym",
                value: volumePercent, // Här skickar vi 35.0 istället för 0.35
                min: 0,
                max: 100,
                step: 5,            // 5% steg istället för 0.05
                unit: "%",          // Enkel enhet
                id: "forcedOutputVolume"
            ))
        }
        
        rows.append(.toggle(title: "Larmljud under telefonsamtal", isOn: UserDefaultsRepository.alertAudioDuringPhone.value, id: "alertAudioDuringPhone"))
        rows.append(.toggle(title: "Ignorera noll-glukos", isOn: UserDefaultsRepository.alertIgnoreZero.value, id: "alertIgnoreZero"))
        rows.append(.toggle(title: "Auto-Snooza CGM-start", isOn: UserDefaultsRepository.alertAutoSnoozeCGMStart.value, id: "alertAutoSnoozeCGMStart"))
        rows.append(.toggle(title: "Aktivera volymknapp-snooze", isOn: UserDefaultsRepository.enableVolumeButtonSnooze.value, id: "enableVolumeButtonSnooze"))
        
        // --- Nattinställningar (Time Windows) ---
        // Eureka använde TimeInlineRow, vi mappar dem till .dateValue eller en dedikerad .timePicker om du har det
        rows.append(.dateValue(
            title: "Nattetid startar",
            date: UserDefaultsRepository.quietHourStart.value,
            id: "quietHourStart"
        ))
        
        rows.append(.dateValue(
            title: "Nattetid slutar",
            date: UserDefaultsRepository.quietHourEnd.value,
            id: "quietHourEnd"
        ))
        
        return rows
    }
        
        // MARK: - Uppdateringslogik (Hanterar .onChange från Eureka)
        
        // Hjälpfunktion från originalkoden för att parsa dag/natt-inställningar
        private func timeBasedSettings(pickerValue: String) -> (dayTime: Bool, nightTime: Bool) {
            var dayTime = false
            var nightTime = false
            
            if pickerValue.contains("Alltid") {
                dayTime = true
                nightTime = true
            } else if pickerValue.contains("Aldrig") {
                dayTime = false
                nightTime = false
            } else {
                if pickerValue.contains("Nattetid") { nightTime = true }
                if pickerValue.contains("Dagtid") { dayTime = true }
            }
            return (dayTime, nightTime)
        }

    // Hantera Switch-ändringar
    func updateActiveToggle(id: String, value: Bool) {
        switch id {
        case "missing_readings_active":
            UserDefaultsRepository.alertMissedReadingActive.value = value

        case "missing_readings_is_snoozed":
            UserDefaultsRepository.alertMissedReadingIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertMissedReadingSnoozedTime.setNil(key: "alertMissedReadingSnoozedTime")
            }

        case "not_looping_active":
            UserDefaultsRepository.alertNotLoopingActive.value = value

        case "not_looping_use_limits":
            UserDefaultsRepository.alertNotLoopingUseLimits.value = value

        case "not_looping_is_snoozed":
            UserDefaultsRepository.alertNotLoopingIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertNotLoopingSnoozedTime.setNil(key: "alertNotLoopingSnoozedTime")
            }

        case "low_battery_active":
            UserDefaultsRepository.alertBatteryActive.value = value

        case "low_battery_repeat":
            UserDefaultsRepository.alertBatteryRepeat.value = value
            
        case "sage_active":
            UserDefaultsRepository.alertSAGEActive.value = value

        case "sage_is_snoozed":
            UserDefaultsRepository.alertSAGEIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertSAGESnoozedTime.setNil(key: "alertSAGESnoozedTime")
            }

        case "cage_active":
            UserDefaultsRepository.alertCAGEActive.value = value

        case "cage_is_snoozed":
            UserDefaultsRepository.alertCAGEIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertCAGESnoozedTime.setNil(key: "alertCAGESnoozedTime")
            }

        case "reservoir_active":
            UserDefaultsRepository.alertPump.value = value

        case "reservoir_is_snoozed":
            UserDefaultsRepository.alertPumpIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertPumpSnoozedTime.setNil(key: "alertPumpSnoozedTime")
            }
            
        case "cob_active":
            UserDefaultsRepository.alertCOB.value = value

        case "cob_is_snoozed":
            UserDefaultsRepository.alertCOBIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertCOBSnoozedTime.setNil(key: "alertCOBSnoozedTime")
            }

        case "iob_active":
            UserDefaultsRepository.alertIOB.value = value

        case "iob_is_snoozed":
            UserDefaultsRepository.alertIOBIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertIOBSnoozedTime.setNil(key: "alertIOBSnoozedTime")
            }

        case "missed_bolus_active":
            UserDefaultsRepository.alertMissedBolusActive.value = value

        case "missed_bolus_is_snoozed":
            UserDefaultsRepository.alertMissedBolusIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertMissedBolusSnoozedTime.setNil(key: "alertMissedBolusSnoozedTime")
            }
            
        // --- Globala Inställningar ---
        case "alertSnoozeAllIsSnoozed":
            UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = value
            if !value {
                // När vi stänger av ska datumet rensas i UserDefaults
                UserDefaultsRepository.alertSnoozeAllTime.setNil(key: "alertSnoozeAllTime")
            }
            
        case "alertMuteAllIsMuted":
            UserDefaultsRepository.alertMuteAllIsMuted.value = value
            if !value {
                UserDefaultsRepository.alertMuteAllTime.setNil(key: "alertMuteAllTime")
            }

        case "low_active":
            UserDefaultsRepository.alertLowActive.value = value
            
        case "low_is_snoozed":
            UserDefaultsRepository.alertLowIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertLowSnoozedTime.setNil(key: "alertLowSnoozedTime")
            }

        case "urgent_low_active":
            UserDefaultsRepository.alertUrgentLowActive.value = value
            
        case "urgent_low_is_snoozed":
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertUrgentLowSnoozedTime.setNil(key: "alertUrgentLowSnoozedTime")
            }

        case "high_active":
            UserDefaultsRepository.alertHighActive.value = value

        case "high_is_snoozed":
            UserDefaultsRepository.alertHighIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertHighSnoozedTime.setNil(key: "alertHighSnoozedTime")
            }

        case "urgent_high_active":
            UserDefaultsRepository.alertUrgentHighActive.value = value

        case "urgent_high_is_snoozed":
            UserDefaultsRepository.alertUrgentHighIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertUrgentHighSnoozedTime.setNil(key: "alertUrgentHighSnoozedTime")
            }

        case "fast_drop_active":
            UserDefaultsRepository.alertFastDropActive.value = value

        case "fast_drop_use_limit":
            UserDefaultsRepository.alertFastDropUseLimit.value = value

        case "fast_drop_is_snoozed":
            UserDefaultsRepository.alertFastDropIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertFastDropSnoozedTime.setNil(key: "alertFastDropSnoozedTime")
            }

        case "fast_rise_active":
            UserDefaultsRepository.alertFastRiseActive.value = value

        case "fast_rise_use_limit":
            UserDefaultsRepository.alertFastRiseUseLimit.value = value

        case "fast_rise_is_snoozed":
            UserDefaultsRepository.alertFastRiseIsSnoozed.value = value
            if !value {
                UserDefaultsRepository.alertFastRiseSnoozedTime.setNil(key: "alertFastRiseSnoozedTime")
            }

        case "temporary_active":
            UserDefaultsRepository.alertTemporaryActive.value = value

        case "temporary_below":
            UserDefaultsRepository.alertTemporaryBelow.value = value

        case "temporary_repeat":
            UserDefaultsRepository.alertTemporaryBGRepeat.value = value

        case "overrideSystemOutputVolume":
            UserDefaultsRepository.overrideSystemOutputVolume.value = value
            
        case "alertAudioDuringPhone":
            UserDefaultsRepository.alertAudioDuringPhone.value = value
            
        case "alertIgnoreZero":
            UserDefaultsRepository.alertIgnoreZero.value = value
            
        case "alertAutoSnoozeCGMStart":
            UserDefaultsRepository.alertAutoSnoozeCGMStart.value = value
            
        case "enableVolumeButtonSnooze":
            UserDefaultsRepository.enableVolumeButtonSnooze.value = value
            
        default:
            break
        }
        
        // Uppdatera UI
        updateSnapshotData()
    }

        // Hantera Stepper-ändringar
        func updateAlarmValue(id: String, value: Double) {
            switch id {
            case "low_bg":
                UserDefaultsRepository.alertLowBG.value = Float(value)
            case "low_persistent":
                UserDefaultsRepository.alertLowPersistent.value = Int(value)
            case "low_persistence_max":
                UserDefaultsRepository.alertLowPersistenceMax.value = Float(value)
            case "low_snooze":
                UserDefaultsRepository.alertLowSnooze.value = Int(value)
            case "forcedOutputVolume":
                UserDefaultsRepository.forcedOutputVolume.value = Float(value / 100.0)
            case "urgent_low_bg":
                UserDefaultsRepository.alertUrgentLowBG.value = Float(value)
            case "urgent_low_predictive":
                UserDefaultsRepository.alertUrgentLowPredictiveMinutes.value = Int(value)
            case "urgent_low_snooze":
                UserDefaultsRepository.alertUrgentLowSnooze.value = Int(value)
            case "high_bg":
                UserDefaultsRepository.alertHighBG.value = Float(value)
            case "high_persistent":
                UserDefaultsRepository.alertHighPersistent.value = Int(value)
            case "high_snooze":
                UserDefaultsRepository.alertHighSnooze.value = Int(value)
            case "urgent_high_bg":
                UserDefaultsRepository.alertUrgentHighBG.value = Float(value)
            case "urgent_high_snooze":
                UserDefaultsRepository.alertUrgentHighSnooze.value = Int(value)
            case "fast_drop_delta":
                UserDefaultsRepository.alertFastDropDelta.value = Float(value)
            case "fast_drop_readings":
                UserDefaultsRepository.alertFastDropReadings.value = Int(value)
            case "fast_drop_below_bg":
                UserDefaultsRepository.alertFastDropBelowBG.value = Float(value)
            case "fast_drop_snooze":
                UserDefaultsRepository.alertFastDropSnooze.value = Int(value)
            case "fast_rise_delta":
                UserDefaultsRepository.alertFastRiseDelta.value = Float(value)
            case "fast_rise_readings":
                UserDefaultsRepository.alertFastRiseReadings.value = Int(value)
            case "fast_rise_above_bg":
                UserDefaultsRepository.alertFastRiseAboveBG.value = Float(value)
            case "fast_rise_snooze":
                UserDefaultsRepository.alertFastRiseSnooze.value = Int(value)
            case "temporary_bg":
                UserDefaultsRepository.alertTemporaryBG.value = Float(value)
                
            case "missing_readings_time":
                UserDefaultsRepository.alertMissedReading.value = Int(value)
            case "missing_readings_snooze":
                UserDefaultsRepository.alertMissedReadingSnooze.value = Int(value)

            case "not_looping_time":
                UserDefaultsRepository.alertNotLooping.value = Int(value)
            case "not_looping_lower_limit":
                UserDefaultsRepository.alertNotLoopingLowerLimit.value = Float(value)
            case "not_looping_upper_limit":
                UserDefaultsRepository.alertNotLoopingUpperLimit.value = Float(value)
            case "not_looping_snooze":
                UserDefaultsRepository.alertNotLoopingSnooze.value = Int(value)

            case "low_battery_level":
                UserDefaultsRepository.alertBatteryLevel.value = Int(value)
            case "low_battery_snooze_hours":
                UserDefaultsRepository.alertBatterySnoozeHours.value = Int(value)
                
            case "sage_time":
                UserDefaultsRepository.alertSAGE.value = Int(value)

            case "sage_snooze":
                UserDefaultsRepository.alertSAGESnooze.value = Int(value)

            case "cage_time":
                UserDefaultsRepository.alertCAGE.value = Int(value)

            case "cage_snooze":
                UserDefaultsRepository.alertCAGESnooze.value = Int(value)

            case "reservoir_units":
                UserDefaultsRepository.alertPumpAt.value = Int(value)

            case "reservoir_snooze_hours":
                UserDefaultsRepository.alertPumpSnoozeHours.value = Int(value)
                
            case "cob_at":
                UserDefaultsRepository.alertCOBAt.value = Int(value)
            case "cob_snooze_hours":
                UserDefaultsRepository.alertCOBSnoozeHours.value = Int(value)

            case "iob_at":
                UserDefaultsRepository.alertIOBAt.value = value
            case "iob_number":
                UserDefaultsRepository.alertIOBNumber.value = Int(value)
            case "iob_within":
                UserDefaultsRepository.alertIOBBolusesWithin.value = Int(value)
            case "iob_max_boluses":
                UserDefaultsRepository.alertIOBMaxBoluses.value = Int(value)
            case "iob_snooze_hours":
                UserDefaultsRepository.alertIOBSnoozeHours.value = Int(value)

            case "missed_bolus_time":
                UserDefaultsRepository.alertMissedBolus.value = Int(value)
            case "missed_bolus_prebolus_time":
                UserDefaultsRepository.alertMissedBolusPrebolus.value = Int(value)
            case "missed_bolus_ignore_bolus":
                UserDefaultsRepository.alertMissedBolusIgnoreBolus.value = value
            case "missed_bolus_low_grams":
                UserDefaultsRepository.alertMissedBolusLowGrams.value = Int(value)
            case "missed_bolus_low_grams_bg":
                UserDefaultsRepository.alertMissedBolusLowGramsBG.value = Float(value)
            case "missed_bolus_snooze":
                UserDefaultsRepository.alertMissedBolusSnooze.value = Int(value)
                
            default: break
            }
        }

        // Hantera Picker-ändringar (Ljud & Alternativ)
        func updateAlarmStringOption(id: String, value: String) {
            switch id {
                
            case "low_sound":
                UserDefaultsRepository.alertLowSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()
                
            case "low_audible":
                UserDefaultsRepository.alertLowAudible.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertLowDayTimeAudible.value = settings.dayTime
                UserDefaultsRepository.alertLowNightTimeAudible.value = settings.nightTime
                
            case "low_repeat":
                UserDefaultsRepository.alertLowRepeat.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertLowDayTime.value = settings.dayTime
                UserDefaultsRepository.alertLowNightTime.value = settings.nightTime
                
            case "low_autosnooze":
                UserDefaultsRepository.alertLowAutosnooze.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertLowAutosnoozeDay.value = settings.dayTime
                UserDefaultsRepository.alertLowAutosnoozeNight.value = settings.nightTime
            
            case "urgent_low_sound":
                UserDefaultsRepository.alertUrgentLowSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()
            
            case "urgent_low_audible":
                UserDefaultsRepository.alertUrgentLowAudible.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentLowDayTimeAudible.value = settings.dayTime
                UserDefaultsRepository.alertUrgentLowNightTimeAudible.value = settings.nightTime
            
            case "urgent_low_repeat":
                UserDefaultsRepository.alertUrgentLowRepeat.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentLowDayTime.value = settings.dayTime
                UserDefaultsRepository.alertUrgentLowNightTime.value = settings.nightTime
            
            case "urgent_low_autosnooze":
                UserDefaultsRepository.alertUrgentLowAutosnooze.value = value
                let settings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentLowAutosnoozeDay.value = settings.dayTime
                UserDefaultsRepository.alertUrgentLowAutosnoozeNight.value = settings.nightTime

            case "high_sound":
                UserDefaultsRepository.alertHighSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()

            case "high_audible":
                UserDefaultsRepository.alertHighAudible.value = value
                let highAudibleSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertHighDayTimeAudible.value = highAudibleSettings.dayTime
                UserDefaultsRepository.alertHighNightTimeAudible.value = highAudibleSettings.nightTime

            case "high_repeat":
                UserDefaultsRepository.alertHighRepeat.value = value
                let highRepeatSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertHighDayTime.value = highRepeatSettings.dayTime
                UserDefaultsRepository.alertHighNightTime.value = highRepeatSettings.nightTime

            case "high_autosnooze":
                UserDefaultsRepository.alertHighAutosnooze.value = value
                let highAutosnoozeSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertHighAutosnoozeDay.value = highAutosnoozeSettings.dayTime
                UserDefaultsRepository.alertHighAutosnoozeNight.value = highAutosnoozeSettings.nightTime

            case "urgent_high_sound":
                UserDefaultsRepository.alertUrgentHighSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()

            case "urgent_high_audible":
                UserDefaultsRepository.alertUrgentHighAudible.value = value
                let urgentHighAudibleSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentHighDayTimeAudible.value = urgentHighAudibleSettings.dayTime
                UserDefaultsRepository.alertUrgentHighNightTimeAudible.value = urgentHighAudibleSettings.nightTime

            case "urgent_high_repeat":
                UserDefaultsRepository.alertUrgentHighRepeat.value = value
                let urgentHighRepeatSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentHighDayTime.value = urgentHighRepeatSettings.dayTime
                UserDefaultsRepository.alertUrgentHighNightTime.value = urgentHighRepeatSettings.nightTime

            case "urgent_high_autosnooze":
                UserDefaultsRepository.alertUrgentHighAutosnooze.value = value
                let urgentHighAutosnoozeSettings = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertUrgentHighAutosnoozeDay.value = urgentHighAutosnoozeSettings.dayTime
                UserDefaultsRepository.alertUrgentHighAutosnoozeNight.value = urgentHighAutosnoozeSettings.nightTime

            case "fast_drop_sound":
                UserDefaultsRepository.alertFastDropSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()

            case "fast_drop_audible":
                UserDefaultsRepository.alertFastDropAudible.value = value
                let settingsFD = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastDropDayTimeAudible.value = settingsFD.dayTime
                UserDefaultsRepository.alertFastDropNightTimeAudible.value = settingsFD.nightTime

            case "fast_drop_repeat":
                UserDefaultsRepository.alertFastDropRepeat.value = value
                let settingsFDRepeat = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastDropDayTime.value = settingsFDRepeat.dayTime
                UserDefaultsRepository.alertFastDropNightTime.value = settingsFDRepeat.nightTime

            case "fast_drop_autosnooze":
                UserDefaultsRepository.alertFastDropAutosnooze.value = value
                let settingsFDAuto = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastDropAutosnoozeDay.value = settingsFDAuto.dayTime
                UserDefaultsRepository.alertFastDropAutosnoozeNight.value = settingsFDAuto.nightTime

            case "fast_rise_sound":
                UserDefaultsRepository.alertFastRiseSound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()

            case "fast_rise_audible":
                UserDefaultsRepository.alertFastRiseAudible.value = value
                let settingsFR = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastRiseDayTimeAudible.value = settingsFR.dayTime
                UserDefaultsRepository.alertFastRiseNightTimeAudible.value = settingsFR.nightTime

            case "fast_rise_repeat":
                UserDefaultsRepository.alertFastRiseRepeat.value = value
                let settingsFRRepeat = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastRiseDayTime.value = settingsFRRepeat.dayTime
                UserDefaultsRepository.alertFastRiseNightTime.value = settingsFRRepeat.nightTime

            case "fast_rise_autosnooze":
                UserDefaultsRepository.alertFastRiseAutosnooze.value = value
                let settingsFRAuto = timeBasedSettings(pickerValue: value)
                UserDefaultsRepository.alertFastRiseAutosnoozeDay.value = settingsFRAuto.dayTime
                UserDefaultsRepository.alertFastRiseAutosnoozeNight.value = settingsFRAuto.nightTime

            case "temporary_sound":
                UserDefaultsRepository.alertTemporarySound.value = value
                AlarmSound.setSoundFile(str: value)
                AlarmSound.stop()
                AlarmSound.playTest()

                // Trio segment (Missing readings, Not looping, Low battery)
                case "missing_readings_sound":
                    UserDefaultsRepository.alertMissedReadingSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "missing_readings_audible":
                    UserDefaultsRepository.alertMissedReadingAudible.value = value
                    let missedAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedReadingDayTimeAudible.value = missedAudible.dayTime
                    UserDefaultsRepository.alertMissedReadingNightTimeAudible.value = missedAudible.nightTime

                case "missing_readings_repeat":
                    UserDefaultsRepository.alertMissedReadingRepeat.value = value
                    let missedRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedReadingDayTime.value = missedRepeat.dayTime
                    UserDefaultsRepository.alertMissedReadingNightTime.value = missedRepeat.nightTime

                case "missing_readings_autosnooze":
                    UserDefaultsRepository.alertMissedReadingAutosnooze.value = value
                    let missedAuto = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedReadingAutosnoozeDay.value = missedAuto.dayTime
                    UserDefaultsRepository.alertMissedReadingAutosnoozeNight.value = missedAuto.nightTime

                case "not_looping_sound":
                    UserDefaultsRepository.alertNotLoopingSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "not_looping_audible":
                    UserDefaultsRepository.alertNotLoopingAudible.value = value
                    let notLoopingAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertNotLoopingDayTimeAudible.value = notLoopingAudible.dayTime
                    UserDefaultsRepository.alertNotLoopingNightTimeAudible.value = notLoopingAudible.nightTime

                case "not_looping_repeat":
                    UserDefaultsRepository.alertNotLoopingRepeat.value = value
                    let notLoopingRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertNotLoopingDayTime.value = notLoopingRepeat.dayTime
                    UserDefaultsRepository.alertNotLoopingNightTime.value = notLoopingRepeat.nightTime

                case "not_looping_autosnooze":
                    UserDefaultsRepository.alertNotLoopingAutosnooze.value = value
                    let notLoopingAuto = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertNotLoopingAutosnoozeDay.value = notLoopingAuto.dayTime
                    UserDefaultsRepository.alertNotLoopingAutosnoozeNight.value = notLoopingAuto.nightTime

                case "low_battery_sound":
                    UserDefaultsRepository.alertBatterySound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()
                
                // --- SAGE (Sensorbyte) ---
                case "sage_sound":
                    UserDefaultsRepository.alertSAGESound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "sage_audible":
                    UserDefaultsRepository.alertSAGEAudible.value = value
                    let sageAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertSAGEDayTimeAudible.value = sageAudible.dayTime
                    UserDefaultsRepository.alertSAGENightTimeAudible.value = sageAudible.nightTime

                case "sage_repeat":
                    UserDefaultsRepository.alertSAGERepeat.value = value
                    let sageRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertSAGEDayTime.value = sageRepeat.dayTime
                    UserDefaultsRepository.alertSAGENightTime.value = sageRepeat.nightTime

                case "sage_autosnooze":
                    UserDefaultsRepository.alertSAGEAutosnooze.value = value
                    let sageAutosnooze = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertSAGEAutosnoozeDay.value = sageAutosnooze.dayTime
                    UserDefaultsRepository.alertSAGEAutosnoozeNight.value = sageAutosnooze.nightTime

                // --- CAGE (Pumpbyte) ---
                case "cage_sound":
                    UserDefaultsRepository.alertCAGESound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "cage_audible":
                    UserDefaultsRepository.alertCAGEAudible.value = value
                    let cageAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCAGEDayTimeAudible.value = cageAudible.dayTime
                    UserDefaultsRepository.alertCAGENightTimeAudible.value = cageAudible.nightTime

                case "cage_repeat":
                    UserDefaultsRepository.alertCAGERepeat.value = value
                    let cageRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCAGEDayTime.value = cageRepeat.dayTime
                    UserDefaultsRepository.alertCAGENightTime.value = cageRepeat.nightTime

                case "cage_autosnooze":
                    UserDefaultsRepository.alertCAGEAutosnooze.value = value
                    let cageAutosnooze = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCAGEAutosnoozeDay.value = cageAutosnooze.dayTime
                    UserDefaultsRepository.alertCAGEAutosnoozeNight.value = cageAutosnooze.nightTime

                // --- Pump / Reservoir ---
                case "reservoir_sound":
                    UserDefaultsRepository.alertPumpSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "reservoir_audible":
                    UserDefaultsRepository.alertPumpAudible.value = value
                    let pumpAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertPumpDayTimeAudible.value = pumpAudible.dayTime
                    UserDefaultsRepository.alertPumpNightTimeAudible.value = pumpAudible.nightTime

                case "reservoir_repeat":
                    UserDefaultsRepository.alertPumpRepeat.value = value
                    let pumpRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertPumpDayTime.value = pumpRepeat.dayTime
                    UserDefaultsRepository.alertPumpNightTime.value = pumpRepeat.nightTime

                case "reservoir_autosnooze":
                    UserDefaultsRepository.alertPumpAutosnooze.value = value
                    let pumpAutosnooze = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertPumpAutosnoozeDay.value = pumpAutosnooze.dayTime
                    UserDefaultsRepository.alertPumpAutosnoozeNight.value = pumpAutosnooze.nightTime
                
                // --- COB ---
                case "cob_sound":
                    UserDefaultsRepository.alertCOBSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "cob_audible":
                    UserDefaultsRepository.alertCOBAudible.value = value
                    let cobAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCOBDayTimeAudible.value = cobAudible.dayTime
                    UserDefaultsRepository.alertCOBNightTimeAudible.value = cobAudible.nightTime

                case "cob_repeat":
                    UserDefaultsRepository.alertCOBRepeat.value = value
                    let cobRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCOBDayTime.value = cobRepeat.dayTime
                    UserDefaultsRepository.alertCOBNightTime.value = cobRepeat.nightTime

                case "cob_autosnooze":
                    UserDefaultsRepository.alertCOBAutosnooze.value = value
                    let cobAutosnooze = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertCOBAutosnoozeDay.value = cobAutosnooze.dayTime
                    UserDefaultsRepository.alertCOBAutosnoozeNight.value = cobAutosnooze.nightTime

                // --- IOB ---
                case "iob_sound":
                    UserDefaultsRepository.alertIOBSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "iob_audible":
                    UserDefaultsRepository.alertIOBAudible.value = value
                    let iobAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertIOBDayTimeAudible.value = iobAudible.dayTime
                    UserDefaultsRepository.alertIOBNightTimeAudible.value = iobAudible.nightTime

                case "iob_repeat":
                    UserDefaultsRepository.alertIOBRepeat.value = value
                    let iobRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertIOBDayTime.value = iobRepeat.dayTime
                    UserDefaultsRepository.alertIOBNightTime.value = iobRepeat.nightTime

                case "iob_autosnooze":
                    UserDefaultsRepository.alertIOBAutosnooze.value = value
                    let iobAutosnooze = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertIOBAutosnoozeDay.value = iobAutosnooze.dayTime
                    UserDefaultsRepository.alertIOBAutosnoozeNight.value = iobAutosnooze.nightTime

                // --- Missed Bolus ---
                case "missed_bolus_sound":
                    UserDefaultsRepository.alertMissedBolusSound.value = value
                    AlarmSound.setSoundFile(str: value)
                    AlarmSound.stop()
                    AlarmSound.playTest()

                case "missed_bolus_audible":
                    UserDefaultsRepository.alertMissedBolusAudible.value = value
                    let missedAudible = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedBolusDayTimeAudible.value = missedAudible.dayTime
                    UserDefaultsRepository.alertMissedBolusNightTimeAudible.value = missedAudible.nightTime

                case "missed_bolus_repeat":
                    UserDefaultsRepository.alertMissedBolusRepeat.value = value
                    let missedRepeat = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedBolusDayTime.value = missedRepeat.dayTime
                    UserDefaultsRepository.alertMissedBolusNightTime.value = missedRepeat.nightTime

                case "missed_bolus_autosnooze":
                    UserDefaultsRepository.alertMissedBolusAutosnooze.value = value
                    let missedAuto = timeBasedSettings(pickerValue: value)
                    UserDefaultsRepository.alertMissedBolusAutosnoozeDay.value = missedAuto.dayTime
                    UserDefaultsRepository.alertMissedBolusAutosnoozeNight.value = missedAuto.nightTime

            default: break
            }
        }
        
    // Hantera Datum-ändringar (Snoozed Until, Global Snooze/Mute, Nattinställningar)
            func updateDate(id: String, date: Date) {
                switch id {
                case "urgent_low_snoozed_time":
                    UserDefaultsRepository.alertUrgentLowSnoozedTime.value = date
                    UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
                    updateSnapshotData()

                case "low_snoozed_time":
                    UserDefaultsRepository.alertLowSnoozedTime.value = date
                    UserDefaultsRepository.alertLowIsSnoozed.value = true
                    updateSnapshotData()

                case "high_snoozed_time":
                    UserDefaultsRepository.alertHighSnoozedTime.value = date
                    UserDefaultsRepository.alertHighIsSnoozed.value = true
                    updateSnapshotData()

                case "urgent_high_snoozed_time":
                    UserDefaultsRepository.alertUrgentHighSnoozedTime.value = date
                    UserDefaultsRepository.alertUrgentHighIsSnoozed.value = true
                    updateSnapshotData()

                case "missing_readings_snoozed_time":
                    UserDefaultsRepository.alertMissedReadingSnoozedTime.value = date
                    UserDefaultsRepository.alertMissedReadingIsSnoozed.value = true
                    updateSnapshotData()

                case "not_looping_snoozed_time":
                    UserDefaultsRepository.alertNotLoopingSnoozedTime.value = date
                    UserDefaultsRepository.alertNotLoopingIsSnoozed.value = true
                    updateSnapshotData()

                case "fast_drop_snoozed_time":
                    UserDefaultsRepository.alertFastDropSnoozedTime.value = date
                    UserDefaultsRepository.alertFastDropIsSnoozed.value = true
                    updateSnapshotData()

                case "fast_rise_snoozed_time":
                    UserDefaultsRepository.alertFastRiseSnoozedTime.value = date
                    UserDefaultsRepository.alertFastRiseIsSnoozed.value = true
                    updateSnapshotData()
                    
                case "sage_snoozed_time":
                    UserDefaultsRepository.alertSAGESnoozedTime.value = date
                    UserDefaultsRepository.alertSAGEIsSnoozed.value = true
                    updateSnapshotData()

                case "cage_snoozed_time":
                    UserDefaultsRepository.alertCAGESnoozedTime.value = date
                    UserDefaultsRepository.alertCAGEIsSnoozed.value = true
                    updateSnapshotData()

                case "reservoir_snoozed_time":
                    UserDefaultsRepository.alertPumpSnoozedTime.value = date
                    UserDefaultsRepository.alertPumpIsSnoozed.value = true
                    updateSnapshotData()
                    
                case "cob_snoozed_time":
                    UserDefaultsRepository.alertCOBSnoozedTime.value = date
                    UserDefaultsRepository.alertCOBIsSnoozed.value = true
                    updateSnapshotData()

                case "iob_snoozed_time":
                    UserDefaultsRepository.alertIOBSnoozedTime.value = date
                    UserDefaultsRepository.alertIOBIsSnoozed.value = true
                    updateSnapshotData()

                case "missed_bolus_snoozed_time":
                    UserDefaultsRepository.alertMissedBolusSnoozedTime.value = date
                    UserDefaultsRepository.alertMissedBolusIsSnoozed.value = true
                    updateSnapshotData()
                    
                // --- Globala inställningar ---
                case "alertSnoozeAllTime":
                    UserDefaultsRepository.alertSnoozeAllTime.value = date
                    UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = true
                    updateSnapshotData()
                    
                case "alertMuteAllTime":
                    UserDefaultsRepository.alertMuteAllTime.value = date
                    UserDefaultsRepository.alertMuteAllIsMuted.value = true
                    updateSnapshotData()
                    
                // --- Nattinställningar (Dina nya rader) ---
                case "quietHourStart":
                    UserDefaultsRepository.quietHourStart.value = date
                    
                case "quietHourEnd":
                    UserDefaultsRepository.quietHourEnd.value = date
                    
                default:
                    break
                }
            }
}
