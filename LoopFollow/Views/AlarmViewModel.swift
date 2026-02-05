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
            default:
                // Hantera andra larm här...
                return []
            }
            
        case .nightSettings:
                return getNightSettingsRows()
            }
    }
    

    // MARK: - Formatters
    private func formatGlucoseValue(_ value: Double) -> String {
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
                // I updateAlarmValue i din ViewModel
            case "forcedOutputVolume":
                // Vi räknar tillbaka från 35.0 till 0.35 innan vi sparar i Repo
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
            default: break
            }
        }

        // Hantera Picker-ändringar (Ljud & Alternativ)
        func updateAlarmStringOption(id: String, value: String) {
            switch id {
                
            case "low_sound":
                UserDefaultsRepository.alertLowSound.value = value
                // Spela upp ljudtest (från originalkoden)
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
                
            default: break
            }
        }
        
    // Hantera Datum-ändringar (Snoozed Until, Global Snooze/Mute, Nattinställningar)
            func updateDate(id: String, date: Date) {
                switch id {
                // --- Specifika larm (t.ex. Akut låg) ---
                case "urgent_low_snoozed_time":
                    UserDefaultsRepository.alertUrgentLowSnoozedTime.value = date
                    UserDefaultsRepository.alertUrgentLowIsSnoozed.value = true
                    updateSnapshotData()
                // --- Specifika larm (t.ex. Låg) ---
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
