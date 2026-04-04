//
//  AdvancedSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.

//

import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: AdvancedSettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showClippyHistory = false

    @available(iOS 26.0, *)
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Avancerade inställningar
                    Text("Avancerade inställningar")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        themedRow {
                            Toggle("Ladda ner behandlingar", isOn: $viewModel.downloadTreatments)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Ladda ner prognoser", isOn: $viewModel.downloadPrediction)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera basal", isOn: $viewModel.graphBasal)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera bolusar", isOn: $viewModel.graphBolus)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera måltider", isOn: $viewModel.graphCarbs)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Rendera andra behandlingar", isOn: $viewModel.graphOtherTreatments)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Stepper(value: $viewModel.bgUpdateDelay, in: 1...30, step: 1) {
                                Text("BG fördröjning (sek): \(viewModel.bgUpdateDelay)")
                            }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Tillåt Clippy-info", isOn: $viewModel.allowClippy)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Clippy historik")
                                Spacer()
                                Button {
                                    showClippyHistory = true
                                } label: {
                                    Text("Visa")
                                        .frame(width: 70, alignment: .center)
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                    .themedCardBackground(opacity: 0.15)

                    // MARK: - Loggalternativ
                    Text("Loggalternativ")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        themedRow {
                            Toggle("Visa debugloggar", isOn: $viewModel.debugLogLevel)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Visa temporära debugloggar", isOn: $viewModel.tempDebugLogLevel)
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            Toggle("Ladda upp appstart till NS", isOn: $viewModel.uploadAppStartNote)
                        }
                    }
                    .themedCardBackground(opacity: 0.15)
                    
                    Text("Manuell arkivering/export")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    
                    VStack(spacing: 0) {
                        themedRow {
                            HStack {
                                Text("Spara fg månad")
                                Spacer()
                            Button {
                                viewModel.archivePreviousMonth()
                            } label: {
                                Text("Arkivera")
                                    .frame(width: 70, alignment: .center)
                            }
                            .buttonStyle(.glassProminent)
                        }
                            
                        }
                        if !viewModel.lastArchiveDebugMessage.isEmpty {
                            Divider().opacity(0.8)
                            themedRow {
                                Text(viewModel.lastArchiveDebugMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Skapa zip för hela arkivet")
                                Spacer()
                            Button {
                                viewModel.exportArchiveZipAndShare()
                            } label: {
                                Text("Export")
                                    .frame(width: 70, alignment: .center)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        }
                        Divider().opacity(0.8)
                        themedRow {
                            HStack {
                                Text("Skapa zip för fg månad")
                                Spacer()
                                Button {
                                    viewModel.exportLatestArchivedMonthZipAndShare()
                                } label: {
                                    Text("Export")
                                        .frame(width: 70, alignment: .center)
                                }
                                .buttonStyle(.glassProminent)
                            }

                        }
                        if !viewModel.lastArchiveExportMessage.isEmpty {
                            Divider().opacity(0.8)
                            themedRow {
                                Text(viewModel.lastArchiveExportMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .themedCardBackground(opacity: 0.15)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showClippyHistory) {
            ClippyHistoryView()
        }
        .sheet(isPresented: $viewModel.isPresentingArchiveShareSheet, onDismiss: {
            viewModel.handleArchiveShareSheetDismissed()
        }) {
            if let url = viewModel.archiveShareURL {
                ActivityView(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private func themedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .tint(Color(uiColor: .systemGreen))
    }
}

@available(iOS 26.0, *)
private struct ClippyHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    private enum RowItem {
        case reached(ClippyDailyTargetHistoryEntry)
        case missed(Date)
    }

    private var sortedHistory: [ClippyDailyTargetHistoryEntry] {
        Storage.shared.clippyDailyTargetHistory.sorted { $0.date > $1.date }
    }

    private var rows: [RowItem] {
        guard !sortedHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        var result: [RowItem] = []

        for index in sortedHistory.indices {
            let entry = sortedHistory[index]
            let entryDate = Date(timeIntervalSince1970: entry.date)
            result.append(.reached(entry))

            guard index < sortedHistory.count - 1 else { continue }

            let nextEntry = sortedHistory[index + 1]
            let nextDate = Date(timeIntervalSince1970: nextEntry.date)

            let currentStartOfDay = calendar.startOfDay(for: entryDate)
            let nextStartOfDay = calendar.startOfDay(for: nextDate)

            guard let daysBetween = calendar.dateComponents([.day], from: nextStartOfDay, to: currentStartOfDay).day,
                  daysBetween > 1 else {
                continue
            }

            for offset in 1..<daysBetween {
                if let missingDay = calendar.date(byAdding: .day, value: -offset, to: currentStartOfDay) {
                    result.append(.missed(missingDay))
                }
            }
        }

        return result
    }

    private static let rowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd, HH:mm"
        return formatter
    }()

    private static let missedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()
                    .ignoresSafeArea()

                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen Clippy-historik", systemImage: "star.fill")
                    } description: {
                        Text("Det finns inga sparade tider ännu.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                VStack(spacing: 0) {
                                    HStack(alignment: .center, spacing: 12) {
                                        switch row {
                                        case .reached(let entry):
                                            HStack(spacing: 8) {
                                                Image(systemName: "star.fill")
                                                    .foregroundStyle(.yellow)
                                                Text("Mål nåddes")
                                            }

                                            Spacer(minLength: 8)

                                            Text(Self.rowFormatter.string(from: Date(timeIntervalSince1970: entry.date)))
                                                .font(.system(size: 13).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)

                                        case .missed(let date):
                                            HStack(spacing: 8) {
                                                Image(systemName: "xmark")
                                                    .foregroundStyle(.red)
                                                Text("Mål nåddes ej")
                                            }

                                            Spacer(minLength: 8)

                                            Text("\(Self.missedFormatter.string(from: date)), 00:00")
                                                .font(.system(size: 13).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if index < rows.count - 1 {
                                        Divider().opacity(0.8)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Clippy historik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
        }
    }
}
