//
//  AdvancedSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.

//

import SwiftUI
import UIKit

@available(iOS 16.0, *)
struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: AdvancedSettingsViewModel
    @Environment(\.presentationMode) var presentationMode

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
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Ladda ner prognoser", isOn: $viewModel.downloadPrediction)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Rendera basal", isOn: $viewModel.graphBasal)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Rendera bolusar", isOn: $viewModel.graphBolus)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Rendera måltider", isOn: $viewModel.graphCarbs)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Rendera andra behandlingar", isOn: $viewModel.graphOtherTreatments)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Stepper(value: $viewModel.bgUpdateDelay, in: 1...30, step: 1) {
                                Text("BG fördröjning (sek): \(viewModel.bgUpdateDelay)")
                            }
                        }
                    }
                    .themedCardBackground()

                    // MARK: - Loggalternativ
                    Text("Loggalternativ")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        themedRow {
                            Toggle("Visa debugloggar", isOn: $viewModel.debugLogLevel)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Visa temporära debugloggar", isOn: $viewModel.tempDebugLogLevel)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Toggle("Ladda upp appstart till NS", isOn: $viewModel.uploadAppStartNote)
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Button {
                                viewModel.archivePreviousMonth()
                            } label: {
                                Text("Arkivera fg månads data")
                            }
                            
                        }
                        if !viewModel.lastArchiveDebugMessage.isEmpty {
                            Divider().opacity(0.35)
                            themedRow {
                                Text(viewModel.lastArchiveDebugMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider().opacity(0.35)
                        themedRow {
                            Button {
                                viewModel.exportArchiveZipAndShare()
                            } label: {
                                Text("Exportera Arkiv (zip)…")
                            }
                        }
                        if !viewModel.lastArchiveExportMessage.isEmpty {
                            Divider().opacity(0.35)
                            themedRow {
                                Text(viewModel.lastArchiveExportMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .themedCardBackground()

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $viewModel.isPresentingArchiveShareSheet) {
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

