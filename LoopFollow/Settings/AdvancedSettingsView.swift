//
//  AdvancedSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: AdvancedSettingsViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Avancerade inställningar")) {
                    Toggle("Ladda ner behandlingar", isOn: $viewModel.downloadTreatments)
                    Toggle("Ladda ner prognoser", isOn: $viewModel.downloadPrediction)
                    Toggle("Rita basal", isOn: $viewModel.graphBasal)
                    Toggle("Rita bolusar", isOn: $viewModel.graphBolus)
                    Toggle("Rita måltider", isOn: $viewModel.graphCarbs)
                    Toggle("Rita nadra behandlingar", isOn: $viewModel.graphOtherTreatments)

                    Stepper(value: $viewModel.bgUpdateDelay, in: 1...30, step: 1) {
                        Text("BG fördröjning (sek): \(viewModel.bgUpdateDelay)")
                    }
                }

                Section(header: Text("Loggalternativ")) {
                    Toggle("Visa debugloggar", isOn: $viewModel.debugLogLevel)
                }
            }
            .navigationBarTitle("Avancerade inställningar", displayMode: .inline)
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
