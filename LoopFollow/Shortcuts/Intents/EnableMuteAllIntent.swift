//
//  EnableMuteAllIntent.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import AppIntents

@available(iOS 16.0, *)
struct EnableMuteAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Tysta alla larm"
    static let description = IntentDescription("Tystar alla larm i ett angivet antal minuter.")

    @Parameter(title: "Minuter", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Tysta alla larm i \(\.$minutes) minuter")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let safeMinutes = max(1, minutes)
        await SnoozeMuteIntentHelper.enableMuteAll(minutes: safeMinutes)
        return .result(dialog: "Tystade alla larm i \(safeMinutes) minuter.")
    }
}
