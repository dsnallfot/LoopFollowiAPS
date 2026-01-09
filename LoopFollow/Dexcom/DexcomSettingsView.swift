//
//  DexcomSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
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
                Section(header: Text("Dexcom")) {
                    TextField("Användarnamn", text: $viewModel.userName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Lösenord", text: $viewModel.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Picker("Server", selection: $viewModel.server) {
                        Text("US").tag("US")
                        Text("NON-US").tag("NON-US")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Toggle("Endast adhoc hämtningar", isOn: $viewModel.adhocOnly)
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }
}
