//
//  DexcomSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.

//

import SwiftUI

@available(iOS 16.0, *)
struct DexcomSettingsView: View {
    @ObservedObject var viewModel: DexcomSettingsViewModel

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            Form {
                Section(header: Text("Användaruppgifter")) {
                    TextField("Ange användarnamn", text: $viewModel.userName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Ange lösenord", text: $viewModel.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Picker("Server", selection: $viewModel.server) {
                        Text("US").tag("US")
                        Text("EU").tag("NON-US")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Toggle("Endast adhoc hämtningar", isOn: $viewModel.adhocOnly)
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }
}
