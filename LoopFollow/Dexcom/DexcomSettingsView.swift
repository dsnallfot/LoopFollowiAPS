//
//  DexcomSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import SwiftUI

struct DexcomSettingsView: View {
    @ObservedObject var viewModel: DexcomSettingsViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dexcominställningar")) {
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
            }
            .navigationBarTitle("Dexcominställningar", displayMode: .inline)
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
