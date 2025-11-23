//
//  EnableSnoozeAllIntent.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import AppIntents

@available(iOS 16.0, *)
struct EnableSnoozeAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Snooza alla larm"
    static let description = IntentDescription("Snoozar alla larm i ett angivet antal minuter.")

    @Parameter(title: "Minuter", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Snooza alla larm i \(\.$minutes) minuter")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let safeMinutes = max(1, minutes)
        await SnoozeMuteIntentHelper.enableSnoozeAll(minutes: safeMinutes)
        return .result(dialog: "Snoozade alla larm i \(safeMinutes) minuter.")
    }
}

