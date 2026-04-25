// LoopFollow
// WatchOverrideView.swift

import SwiftUI

struct WatchOverrideView: View {
    let config: WatchConfig
    @ObservedObject var bgFetcher: BGFetcher
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOverride: OverridePreset?
    @State private var showConfirm = false
    @State private var showCancelConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var showCelebration = false

    var body: some View {
        Group {
            if let result = resultMessage {
                ZStack {
                    VStack {
                        Spacer()
                        Text(result)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(isError ? .red : .green)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    CelebrationOverlay(isActive: $showCelebration)
                }
            } else {
        ScrollView {
            VStack(spacing: 6) {
                if showConfirm, let override = selectedOverride {
                    Text(override.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.purple)

                    if let pct = override.percentage {
                        Text(String(format: "%.0f%%", pct))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    CrownConfirmView(label: "att aktivera") {
                        sendOverride(name: override.name)
                    }
                } else if showCancelConfirm {
                    Text("Avbryt override")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)

                    CrownConfirmView(label: "att avbryta") {
                        cancelOverride()
                    }
                } else {
                    // Active override section (check both devicestatus and treatments)
                    if let activeOverride = activeOverrideEntry {
                        Text("Aktiv override")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(activeOverride.name + (activeOverride.percentage.map { String(format: " %.0f%%", $0) } ?? ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(Color.purple.opacity(0.55))
                            .cornerRadius(8)

                        Button {
                            showCancelConfirm = true
                        } label: {
                            Text("Avbryt override")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.3))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Divider()
                    }

                    Text("Välj override")
                        .font(.system(size: 14, weight: .semibold))

                    if bgFetcher.overridePresets.isEmpty {
                        Text("No presets found.\nCheck Nightscout profile.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        ForEach(bgFetcher.overridePresets) { preset in
                            Button {
                                selectedOverride = preset
                                showConfirm = true
                            } label: {
                                HStack {
                                    Text(preset.name)
                                        .font(.system(size: 15, weight: .medium))
                                    Spacer()
                                    if let pct = preset.percentage {
                                        Text(String(format: "%.0f%%", pct))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 14)
                                .background(Color.purple.opacity(0.55))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
            }
        }
    }

    /// Returns the currently active override from treatments, or nil if none active.
    private var activeOverrideEntry: OverrideEntry? {
        let now = Date()
        return bgFetcher.overrideEntries.first { $0.startDate <= now && $0.endDate > now }
    }

    private func autoDismiss() {
        let delay = showCelebration ? CelebrationOverlay.displayDuration : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            dismiss()
        }
    }

    private func sendOverride(name: String) {
        WatchRemoteService.sendOverride(name: name, config: config) { success, error in
            if success {
                resultMessage = "Override skickades!"
                //showCelebration = CelebrationOverlay.shouldCelebrate()
                //WatchRemoteService.postLocalNotification(
                //    title: "Override aktiverad",
                //    body: "\(name) kommando skickades"
                //)
                autoDismiss()
            } else {
                resultMessage = error ?? "Misslyckades"
                isError = true
            }
        }
    }

    private func cancelOverride() {
        WatchRemoteService.cancelOverride(config: config) { success, error in
            if success {
                resultMessage = "Override avbröts"
                //showCelebration = CelebrationOverlay.shouldCelebrate()
                //WatchRemoteService.postLocalNotification(
                //    title: "Override avbröts",
                //    body: "Avbryt override kommando skickades"
                //)
                autoDismiss()
            } else {
                resultMessage = error ?? "Misslyckades"
                isError = true
            }
        }
    }
}

struct WatchComboView: View {
    let config: WatchConfig
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: WatchComboPreset?
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var showCelebration = false

    var body: some View {
        Group {
            if let result = resultMessage {
                ZStack {
                    VStack {
                        Spacer()
                        Text(result)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(isError ? .red : .green)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    CelebrationOverlay(isActive: $showCelebration)
                }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        if showConfirm, let preset = selectedPreset {
                            Text(preset.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.pink)
                                .multilineTextAlignment(.center)

                            let lines = summaryLines(for: preset)
                            if !lines.isEmpty {
                                VStack(spacing: 3) {
                                    ForEach(lines, id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                            }

                            CrownConfirmView(label: "att skicka") {
                                sendCombo(preset)
                            }
                        } else {
                            Text("Välj snabbval")
                                .font(.system(size: 14, weight: .semibold))

                            if config.comboPresets.isEmpty {
                                Text("Inga snabbval hittades.\nKontrollera inställningarna i iPhone-appen.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                ForEach(config.comboPresets) { preset in
                                    Button {
                                        selectedPreset = preset
                                        showConfirm = true
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(preset.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .lineLimit(1)

                                            let summary = compactSummary(for: preset)
                                            if !summary.isEmpty {
                                                Text(summary)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 14)
                                        .background(Color.orange.opacity(0.55))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func compactSummary(for preset: WatchComboPreset) -> String {
        summaryLines(for: preset).joined(separator: " • ")
    }

    private func summaryLines(for preset: WatchComboPreset) -> [String] {
        var lines: [String] = []

        if preset.carbsGrams > 0 {
            lines.append("KH \(preset.carbsGrams) g")
        }
        if preset.fatGrams > 0 {
            lines.append("Fett \(preset.fatGrams) g")
        }
        if preset.proteinGrams > 0 {
            lines.append("Protein \(preset.proteinGrams) g")
        }
        if preset.bolusUnits > 0 {
            lines.append(String(format: "Bolus %.2f E", preset.bolusUnits))
        }
        if let overrideName = preset.overrideName {
            lines.append("\(overrideName)")
        }

        //let trimmedNotes = preset.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        //if !trimmedNotes.isEmpty {
        //    lines.append(trimmedNotes)
        //}

        return lines
    }

    private func autoDismiss() {
        let delay = showCelebration ? CelebrationOverlay.displayDuration : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            dismiss()
        }
    }

    private func sendCombo(_ preset: WatchComboPreset) {
        WatchRemoteService.sendCombo(
            carbs: preset.carbsGrams,
            protein: preset.proteinGrams,
            fat: preset.fatGrams,
            bolusAmount: preset.bolusUnits,
            notes: preset.notes.isEmpty ? "⌚️" : preset.notes,
            overrideName: preset.overrideName,
            config: config
        ) { success, error in
            if success {
                resultMessage = "Snabbval skickades!"
                autoDismiss()
            } else {
                resultMessage = error ?? "Misslyckades"
                isError = true
            }
        }
    }
}
