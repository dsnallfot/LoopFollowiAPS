//
//  NightscoutSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.

//

import SwiftUI

@available(iOS 16.0, *)
struct NightscoutSettingsView: View {
    @ObservedObject var viewModel: NightscoutSettingsViewModel
    
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()
            
            Form {
                Section(header: Text("Webbadress & token")) {
                    TextField("Ange URL", text: $viewModel.nightscoutURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: viewModel.nightscoutURL) { newValue in
                            viewModel.processURL(newValue)
                        }
                    
                    TextField("Ange token", text: $viewModel.nightscoutToken)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text(viewModel.nightscoutStatus)
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        //.onDisappear {
        //    viewModel.dismiss()
        //}
    }
}
/*

    // MARK: - Subviews / Computed Properties

    private var urlSection: some View {
        Section {
            TextField("URL", text: $viewModel.nightscoutURL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: viewModel.nightscoutURL) { newValue in
                    viewModel.processURL(newValue)
                }
        } header: {
            Text("URL")
        }
        .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
    }

    private var tokenSection: some View {
        Section {
            TextField("Token", text: $viewModel.nightscoutToken)
                .textContentType(.password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        } header: {
            Text("Token")
        }
        .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
    }

    private var statusSection: some View {
        Section {
            Text(viewModel.nightscoutStatus)
        } header: {
            Text("Status")
        }
        .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
    }
}
*/
