//
//  DisableMuteAllIntent.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-11-23.
//

import AppIntents

@available(iOS 16.0, *)
struct DisableMuteAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Avtysta alla larm"
    static let description = IntentDescription("Tar bort mute för alla larm.")

    static var parameterSummary: some ParameterSummary {
        Summary("Avtysta alla larm")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SnoozeMuteIntentHelper.disableMuteAll()
        return .result(dialog: "Avtystade alla larm.")
    }
}
