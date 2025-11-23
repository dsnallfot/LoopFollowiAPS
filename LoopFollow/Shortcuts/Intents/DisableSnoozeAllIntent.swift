//
//  DisableSnoozeAllIntent.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import AppIntents

@available(iOS 16.0, *)
struct DisableSnoozeAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Avsnooza alla larm"
    static let description = IntentDescription("Tar bort snooze för alla larm.")

    static var parameterSummary: some ParameterSummary {
        Summary("Avsnooza alla larm")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SnoozeMuteIntentHelper.disableSnoozeAll()
        return .result(dialog: "Avsnoozade alla larm.")
    }
}
