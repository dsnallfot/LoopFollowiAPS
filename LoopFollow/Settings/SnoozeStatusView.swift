//
//  SnoozeStatusView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-03.
//

import SwiftUI
import Combine

// MARK: - Model

enum SnoozeKey: CaseIterable, Identifiable {
    case all, muteAll,
         urgentLow, low, high, urgentHigh,
         fastDrop, fastRise,
         missedReading,
         sage, cage,
         notLooping,
         missedBolus,
         pump,
         iob, cob,
         battery,
         recBolus,
         tempTargetStart, tempTargetEnd

    var id: String { displayTitle }

    var displayTitle: String {
        switch self {
        case .all: return "⏱️ Snooza alla larm"
        case .muteAll: return "🔇 Tysta alla larm"
        case .urgentLow: return "🆘 Akut lågt socker!"
        case .low: return "🔴 Lågt blodsocker"
        case .high: return "🟣 Högt blodsocker"
        case .urgentHigh: return "⚠️ Akut högt socker!"
        case .fastDrop: return "⏬ Sjunker snabbt"
        case .fastRise: return "⏫ Stiger snabbt"
        case .missedReading: return "⚠️ Inga värden"
        case .sage: return "⏰ Påminnelse sensorbyte"
        case .cage: return "⏰ Påminnelse pumpbyte"
        case .notLooping: return "❌ Loop ej aktiv!"
        case .missedBolus: return "⚠️ Missad måltidsbolus"
        case .pump: return "⚠️ Låg insulinnivå"
        case .iob: return "💉 IOB Varning"
        case .cob: return "🥨 COB Varning"
        case .battery: return "🪫 Låg batterinivå"
        case .recBolus: return "👉 Rek. Bolus"
        case .tempTargetStart: return "▶️ Temp Target Start"
        case .tempTargetEnd: return "⏹️ Temp Target End"
        }
    }

    // UserDefaultsRepository bool/time accessors
    var isSnoozed: Bool {
        switch self {
        case .all: return UserDefaultsRepository.alertSnoozeAllIsSnoozed.value
        case .muteAll: return UserDefaultsRepository.alertMuteAllIsMuted.value
        case .urgentLow: return UserDefaultsRepository.alertUrgentLowIsSnoozed.value
        case .low: return UserDefaultsRepository.alertLowIsSnoozed.value
        case .high: return UserDefaultsRepository.alertHighIsSnoozed.value
        case .urgentHigh: return UserDefaultsRepository.alertUrgentHighIsSnoozed.value
        case .fastDrop: return UserDefaultsRepository.alertFastDropIsSnoozed.value
        case .fastRise: return UserDefaultsRepository.alertFastRiseIsSnoozed.value
        case .missedReading: return UserDefaultsRepository.alertMissedReadingIsSnoozed.value
        case .sage: return UserDefaultsRepository.alertSAGEIsSnoozed.value
        case .cage: return UserDefaultsRepository.alertCAGEIsSnoozed.value
        case .notLooping: return UserDefaultsRepository.alertNotLoopingIsSnoozed.value
        case .missedBolus: return UserDefaultsRepository.alertMissedBolusIsSnoozed.value
        case .pump: return UserDefaultsRepository.alertPumpIsSnoozed.value
        case .iob: return UserDefaultsRepository.alertIOBIsSnoozed.value
        case .cob: return UserDefaultsRepository.alertCOBIsSnoozed.value
        case .battery: return UserDefaultsRepository.alertBatteryIsSnoozed.value
        case .recBolus: return UserDefaultsRepository.alertRecBolusIsSnoozed.value
        case .tempTargetStart: return UserDefaultsRepository.alertTempTargetStartIsSnoozed.value
        case .tempTargetEnd: return UserDefaultsRepository.alertTempTargetEndIsSnoozed.value
        }
    }

    var snoozedTime: Date? {
        switch self {
        case .all: return UserDefaultsRepository.alertSnoozeAllTime.value
        case .muteAll: return UserDefaultsRepository.alertMuteAllTime.value
        case .urgentLow: return UserDefaultsRepository.alertUrgentLowSnoozedTime.value
        case .low: return UserDefaultsRepository.alertLowSnoozedTime.value
        case .high: return UserDefaultsRepository.alertHighSnoozedTime.value
        case .urgentHigh: return UserDefaultsRepository.alertUrgentHighSnoozedTime.value
        case .fastDrop: return UserDefaultsRepository.alertFastDropSnoozedTime.value
        case .fastRise: return UserDefaultsRepository.alertFastRiseSnoozedTime.value
        case .missedReading: return UserDefaultsRepository.alertMissedReadingSnoozedTime.value
        case .sage: return UserDefaultsRepository.alertSAGESnoozedTime.value
        case .cage: return UserDefaultsRepository.alertCAGESnoozedTime.value
        case .notLooping: return UserDefaultsRepository.alertNotLoopingSnoozedTime.value
        case .missedBolus: return UserDefaultsRepository.alertMissedBolusSnoozedTime.value
        case .pump: return UserDefaultsRepository.alertPumpSnoozedTime.value
        case .iob: return UserDefaultsRepository.alertIOBSnoozedTime.value
        case .cob: return UserDefaultsRepository.alertCOBSnoozedTime.value
        case .battery: return UserDefaultsRepository.alertBatterySnoozedTime.value
        case .recBolus: return UserDefaultsRepository.alertRecBolusSnoozedTime.value
        case .tempTargetStart: return UserDefaultsRepository.alertTempTargetStartSnoozedTime.value
        case .tempTargetEnd: return UserDefaultsRepository.alertTempTargetEndSnoozedTime.value
        }
    }

    // Keys for reloader bridge
    var isKeyString: String {
        switch self {
        case .all: return "alertSnoozeAllIsSnoozed"
        case .muteAll: return "alertMuteAllIsMuted"
        case .urgentLow: return "alertUrgentLowIsSnoozed"
        case .low: return "alertLowIsSnoozed"
        case .high: return "alertHighIsSnoozed"
        case .urgentHigh: return "alertUrgentHighIsSnoozed"
        case .fastDrop: return "alertFastDropIsSnoozed"
        case .fastRise: return "alertFastRiseIsSnoozed"
        case .missedReading: return "alertMissedReadingIsSnoozed"
        case .sage: return "alertSAGEIsSnoozed"
        case .cage: return "alertCAGEIsSnoozed"
        case .notLooping: return "alertNotLoopingIsSnoozed"
        case .missedBolus: return "alertMissedBolusIsSnoozed"
        case .pump: return "alertPumpIsSnoozed"
        case .iob: return "alertIOBIsSnoozed"
        case .cob: return "alertCOBIsSnoozed"
        case .battery: return "alertBatteryIsSnoozed"
        case .recBolus: return "alertRecBolusIsSnoozed"
        case .tempTargetStart: return "alertTempTargetStartIsSnoozed"
        case .tempTargetEnd: return "alertTempTargetEndIsSnoozed"
        }
    }

    var timeKeyString: String {
        switch self {
        case .all: return "alertSnoozeAllTime"
        case .muteAll: return "alertMuteAllTime"
        case .urgentLow: return "alertUrgentLowSnoozedTime"
        case .low: return "alertLowSnoozedTime"
        case .high: return "alertHighSnoozedTime"
        case .urgentHigh: return "alertUrgentHighSnoozedTime"
        case .fastDrop: return "alertFastDropSnoozedTime"
        case .fastRise: return "alertFastRiseSnoozedTime"
        case .missedReading: return "alertMissedReadingSnoozedTime"
        case .sage: return "alertSAGESnoozedTime"
        case .cage: return "alertCAGESnoozedTime"
        case .notLooping: return "alertNotLoopingSnoozedTime"
        case .missedBolus: return "alertMissedBolusSnoozedTime"
        case .pump: return "alertPumpSnoozedTime"
        case .iob: return "alertIOBSnoozedTime"
        case .cob: return "alertCOBSnoozedTime"
        case .battery: return "alertBatterySnoozedTime"
        case .recBolus: return "alertRecBolusSnoozedTime"
        case .tempTargetStart: return "alertTempTargetStartSnoozedTime"
        case .tempTargetEnd: return "alertTempTargetEndSnoozedTime"
        }
    }
}

struct SnoozedAlarmItem: Identifiable {
    let id = UUID()
    let key: SnoozeKey
    let title: String
    let time: Date?
}

// MARK: - ViewModel

final class SnoozeStatusViewModel: ObservableObject {
    @Published var items: [SnoozedAlarmItem] = []

    private var timer: AnyCancellable?

    private lazy var timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.setLocalizedDateFormatFromTemplate("HH:mm")
        return df
    }()

    init() {
        refresh()
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    deinit { timer?.cancel() }

    func formatted(_ date: Date?) -> String {
        guard let date = date else { return "okänt" }
        return timeFormatter.string(from: date)
    }

    func refresh() {
        var list: [SnoozedAlarmItem] = []
        if SnoozeKey.all.isSnoozed {
            list.append(.init(key: .all, title: SnoozeKey.all.displayTitle, time: SnoozeKey.all.snoozedTime))
        }
        if SnoozeKey.muteAll.isSnoozed {
            list.append(.init(key: .muteAll, title: SnoozeKey.muteAll.displayTitle, time: SnoozeKey.muteAll.snoozedTime))
        }
        // Övriga, i samma mapping som setSnoozeTime()
        let order: [SnoozeKey] = [
            .urgentLow, .low, .high, .urgentHigh,
            .fastDrop, .fastRise,
            .missedReading,
            .sage, .cage,
            .notLooping,
            .missedBolus,
            .pump,
            .iob, .cob,
            .battery,
            .recBolus,
            .tempTargetStart, .tempTargetEnd
        ]
        // Sortera efter tid (okända sist), men behåll globalerna i topp om de fanns
        let headCount = list.count
        let tailSource = order.compactMap { key in
            key.isSnoozed ? SnoozedAlarmItem(key: key, title: key.displayTitle, time: key.snoozedTime) : nil
        }
        let tail = tailSource.sorted { a, b in
            switch (a.time, b.time) {
            case let (t1?, t2?): return t1 < t2
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title < b.title
            }
        }
        items = Array(list.prefix(headCount)) + tail
    }

    // MARK: Mutations

    func setSnoozed(_ on: Bool, for key: SnoozeKey) {
        let alarms = ViewControllerManager.shared.alarmViewController
        switch key {
        case .all:
            UserDefaultsRepository.alertSnoozeAllIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .muteAll:
            UserDefaultsRepository.alertMuteAllIsMuted.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .urgentLow:
            UserDefaultsRepository.alertUrgentLowIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .low:
            UserDefaultsRepository.alertLowIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .high:
            UserDefaultsRepository.alertHighIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .urgentHigh:
            UserDefaultsRepository.alertUrgentHighIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .fastDrop:
            UserDefaultsRepository.alertFastDropIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .fastRise:
            UserDefaultsRepository.alertFastRiseIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .missedReading:
            UserDefaultsRepository.alertMissedReadingIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .sage:
            UserDefaultsRepository.alertSAGEIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .cage:
            UserDefaultsRepository.alertCAGEIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .notLooping:
            UserDefaultsRepository.alertNotLoopingIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .missedBolus:
            UserDefaultsRepository.alertMissedBolusIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .pump:
            UserDefaultsRepository.alertPumpIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .iob:
            UserDefaultsRepository.alertIOBIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .cob:
            UserDefaultsRepository.alertCOBIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .battery:
            UserDefaultsRepository.alertBatteryIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .recBolus:
            UserDefaultsRepository.alertRecBolusIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .tempTargetStart:
            UserDefaultsRepository.alertTempTargetStartIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        case .tempTargetEnd:
            UserDefaultsRepository.alertTempTargetEndIsSnoozed.value = on
            alarms?.reloadIsSnoozed(key: key.isKeyString, value: on)
        }
    }

    func setTime(_ date: Date?, for key: SnoozeKey) {
        let alarms = ViewControllerManager.shared.alarmViewController
        let setNil = (date == nil)
        switch key {
        case .all:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertSnoozeAllTime.value = date }
        case .muteAll:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertMuteAllTime.value = date }
        case .urgentLow:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertUrgentLowSnoozedTime.value = date }
        case .low:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertLowSnoozedTime.value = date }
        case .high:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertHighSnoozedTime.value = date }
        case .urgentHigh:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertUrgentHighSnoozedTime.value = date }
        case .fastDrop:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertFastDropSnoozedTime.value = date }
        case .fastRise:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertFastRiseSnoozedTime.value = date }
        case .missedReading:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertMissedReadingSnoozedTime.value = date }
        case .sage:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertSAGESnoozedTime.value = date }
        case .cage:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertCAGESnoozedTime.value = date }
        case .notLooping:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertNotLoopingSnoozedTime.value = date }
        case .missedBolus:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertMissedBolusSnoozedTime.value = date }
        case .pump:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertPumpSnoozedTime.value = date }
        case .iob:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertIOBSnoozedTime.value = date }
        case .cob:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertCOBSnoozedTime.value = date }
        case .battery:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertBatterySnoozedTime.value = date }
        case .recBolus:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertRecBolusSnoozedTime.value = date }
        case .tempTargetStart:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertTempTargetStartSnoozedTime.value = date }
        case .tempTargetEnd:
            if setNil { UserDefaults.standard.removeObject(forKey: key.timeKeyString) }
            else { UserDefaultsRepository.alertTempTargetEndSnoozedTime.value = date }
        }
        alarms?.reloadSnoozeTime(key: key.timeKeyString, setNil: setNil, value: (date ?? Date()))
    }

    func bumpTime(by minutes: Int, for key: SnoozeKey) {
        let base = key.snoozedTime ?? Date()
        if let next = Calendar.current.date(byAdding: .minute, value: minutes, to: base) {
            setTime(next, for: key)
        }
    }
}

// MARK: - View

struct SnoozeStatusView: View {
    @ObservedObject var viewModel = SnoozeStatusViewModel()
    @Environment(\.presentationMode) var presentationMode

    @State private var showingEditor = false
    @State private var editingKey: SnoozeKey? = nil
    @State private var editingTime: Date = Date()

    var body: some View {
        NavigationView {
            List {
                if viewModel.items.isEmpty {
                    Text("Inga snoozade larm just nu")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text("\((item.key == .muteAll) ? "Alla larm tystade till kl:" : (item.key == .all) ? "Alla larm snoozade till kl:" : "Larm snoozat till kl:") \(viewModel.formatted(item.time))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.setTime(nil, for: item.key)
                                viewModel.setSnoozed(false, for: item.key)
                                viewModel.refresh()
                            } label: {
                                Label("Ta bort", systemImage: "trash.fill")
                            }
                            .tint(.red)

                            Button {
                                editingKey = item.key
                                editingTime = item.time ?? Date()
                                showingEditor = true
                            } label: {
                                Label("Ändra tid", systemImage: "clock.badge")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationBarTitle("Snoozade larm", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        setGlobalSnooze(minutes: 60)
                    } label: {
                        Image(systemName: "clock.badge")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .contextMenu {
                        Text("Snooza alla larm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(true)
                        Divider()
                        Button("2 h") { setGlobalSnooze(minutes: 120) }
                        Button("4 h") { setGlobalSnooze(minutes: 240) }
                        Button("8 h") { setGlobalSnooze(minutes: 480) }
                        Button("10 h") { setGlobalSnooze(minutes: 600) }
                        Button("12 h") { setGlobalSnooze(minutes: 720) }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        setGlobalMute(minutes: 60)
                    } label: {
                        Image(systemName: "speaker.slash")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .contextMenu {
                        Text("Tysta alla larm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(true)
                        Divider()
                        Button("2 h") { setGlobalMute(minutes: 120) }
                        Button("4 h") { setGlobalMute(minutes: 240) }
                        Button("8 h") { setGlobalMute(minutes: 480) }
                        Button("10 h") { setGlobalMute(minutes: 600) }
                        Button("12 h") { setGlobalMute(minutes: 720) }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor) {
                if #available(iOS 16.0, *) {
                    NavigationView {
                        VStack(spacing: 16) {
                            DatePicker("Tid", selection: $editingTime)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "sv_SE"))
                            HStack(spacing: 12) {
                                Button {
                                    editingTime = Calendar.current.date(byAdding: .minute, value: -15, to: editingTime) ?? editingTime
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 36))
                                }

                                Text("15 minuter")
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                Button {
                                    editingTime = Calendar.current.date(byAdding: .minute, value: 15, to: editingTime) ?? editingTime
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 36))
                                }
                            }
                            .padding(.top, 8)
                            Spacer()
                        }
                        .padding()
                        .navigationTitle("Ändra snooze-tid")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Avbryt") { showingEditor = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Spara") {
                                    if let key = editingKey {
                                        viewModel.setSnoozed(true, for: key)
                                        viewModel.setTime(editingTime, for: key)
                                        viewModel.refresh()
                                    }
                                    showingEditor = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                } else {
                    // Fallback on earlier versions
                }
            }
        }
    }
    private func setGlobalSnooze(minutes: Int) {
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        viewModel.setSnoozed(true, for: .all)
        viewModel.setTime(target, for: .all)
        viewModel.refresh()
    }

    private func setGlobalMute(minutes: Int) {
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        viewModel.setSnoozed(true, for: .muteAll)
        viewModel.setTime(target, for: .muteAll)
        viewModel.refresh()
    }
}
