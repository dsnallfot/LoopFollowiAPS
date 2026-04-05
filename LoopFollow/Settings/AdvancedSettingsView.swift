//
//  AdvancedSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.

//

import SwiftUI
import UIKit
import Charts

@available(iOS 26.0, *)
struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: AdvancedSettingsViewModel
    @Environment(\.presentationMode) var presentationMode
    //@State private var showClippyHistory = false

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
                        /*Divider().opacity(0.8)
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
                        }*/
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
        /*.sheet(isPresented: $showClippyHistory) {
            ClippyHistoryView()
        }*/
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
