//
//  SnoozeStatusView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-03.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI
import Combine

struct SnoozedAlarmItem: Identifiable {
    let id = UUID()
    let title: String
    let time: Date?
}

final class SnoozeStatusViewModel: ObservableObject {
    @Published var items: [SnoozedAlarmItem] = []

    private var timer: AnyCancellable?

    private lazy var timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "sv_SE")
        df.setLocalizedDateFormatFromTemplate("HH:mm:ss")
        return df
    }()

    init() {
        refresh()
        // Uppdatera var 5e sekund ifall snooze-flaggor ändras medan vyn är öppen
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    deinit { timer?.cancel() }

    func formatted(_ date: Date?) -> String {
        guard let date = date else { return "okänt" }
        return timeFormatter.string(from: date)
    }

    func refresh() {
        var list: [SnoozedAlarmItem] = []

        // Samma display-namn som i SnoozeViewController.setSnoozeTime()
        if UserDefaultsRepository.alertUrgentLowIsSnoozed.value {
            list.append(.init(title: "🆘 Akut lågt socker!", time: UserDefaultsRepository.alertUrgentLowSnoozedTime.value))
        }
        if UserDefaultsRepository.alertLowIsSnoozed.value {
            list.append(.init(title: "Lågt blodsocker", time: UserDefaultsRepository.alertLowSnoozedTime.value))
        }
        if UserDefaultsRepository.alertHighIsSnoozed.value {
            list.append(.init(title: "Högt blodsocker", time: UserDefaultsRepository.alertHighSnoozedTime.value))
        }
        if UserDefaultsRepository.alertUrgentHighIsSnoozed.value {
            list.append(.init(title: "⚠️ Akut högt socker!", time: UserDefaultsRepository.alertUrgentHighSnoozedTime.value))
        }
        if UserDefaultsRepository.alertFastDropIsSnoozed.value {
            list.append(.init(title: "Sjunker snabbt", time: UserDefaultsRepository.alertFastDropSnoozedTime.value))
        }
        if UserDefaultsRepository.alertFastRiseIsSnoozed.value {
            list.append(.init(title: "Stiger snabbt", time: UserDefaultsRepository.alertFastRiseSnoozedTime.value))
        }
        if UserDefaultsRepository.alertMissedReadingIsSnoozed.value {
            list.append(.init(title: "⚠️ Inga värden", time: UserDefaultsRepository.alertMissedReadingSnoozedTime.value))
        }
        if UserDefaultsRepository.alertSAGEIsSnoozed.value {
            list.append(.init(title: "⏰ Påminnelse sensorbyte", time: UserDefaultsRepository.alertSAGESnoozedTime.value))
        }
        if UserDefaultsRepository.alertCAGEIsSnoozed.value {
            list.append(.init(title: "⏰ Påminnelse pumpbyte", time: UserDefaultsRepository.alertCAGESnoozedTime.value))
        }
        if UserDefaultsRepository.alertNotLoopingIsSnoozed.value {
            list.append(.init(title: "❌ Loop ej aktiv!", time: UserDefaultsRepository.alertNotLoopingSnoozedTime.value))
        }
        if UserDefaultsRepository.alertMissedBolusIsSnoozed.value {
            list.append(.init(title: "Missad måltidsbolus", time: UserDefaultsRepository.alertMissedBolusSnoozedTime.value))
        }
        if UserDefaultsRepository.alertPumpIsSnoozed.value {
            list.append(.init(title: "Låg insulinnivå", time: UserDefaultsRepository.alertPumpSnoozedTime.value))
        }
        if UserDefaultsRepository.alertIOBIsSnoozed.value {
            list.append(.init(title: "IOB Varning", time: UserDefaultsRepository.alertIOBSnoozedTime.value))
        }
        if UserDefaultsRepository.alertCOBIsSnoozed.value {
            list.append(.init(title: "COB Varning", time: UserDefaultsRepository.alertCOBSnoozedTime.value))
        }
        if UserDefaultsRepository.alertBatteryIsSnoozed.value {
            list.append(.init(title: "🪫 Låg batterinivå", time: UserDefaultsRepository.alertBatterySnoozedTime.value))
        }
        if UserDefaultsRepository.alertRecBolusIsSnoozed.value {
            list.append(.init(title: "Rek. Bolus", time: UserDefaultsRepository.alertRecBolusSnoozedTime.value))
        }
        if UserDefaultsRepository.alertTempTargetStartIsSnoozed.value {
            list.append(.init(title: "Temp Target Start", time: UserDefaultsRepository.alertTempTargetStartSnoozedTime.value))
        }
        if UserDefaultsRepository.alertTempTargetEndIsSnoozed.value {
            list.append(.init(title: "Temp Target End", time: UserDefaultsRepository.alertTempTargetEndSnoozedTime.value))
        }
        // Not: "⚠️ Snart akut låg!" använder samma UrgentLow-nycklar i din controller
        // och täcks därför av posten för UrgentLow ovan.

        // Sortera: tidigast först, okända tider sist; ties på titel
        list.sort { a, b in
            switch (a.time, b.time) {
            case let (t1?, t2?): return t1 < t2
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title < b.title
            }
        }

        items = list
    }
}

struct SnoozeStatusView: View {
    @ObservedObject var viewModel = SnoozeStatusViewModel()
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                if viewModel.items.isEmpty {
                    Text("Inga aktiva snoozade larm")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(" Larm snoozat till kl:  \(viewModel.formatted(item.time))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationBarTitle("Snoozade larm", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
