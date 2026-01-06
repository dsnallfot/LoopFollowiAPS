//
//  NightscoutSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-18.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
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
                urlSection
                tokenSection
                statusSection
            }
            // Let gradient show through the Form background
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .onDisappear {
            viewModel.dismiss()
        }
    }

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
            Divider().opacity(0.35)
        } header: {
            Text("URL")
        }
        .listRowBackground(Color.clear)
    }

    private var tokenSection: some View {
        Section {
            TextField("Token", text: $viewModel.nightscoutToken)
                .textContentType(.password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Divider().opacity(0.35)
        } header: {
            Text("Token")
        }
        .listRowBackground(Color.clear)
    }

    private var statusSection: some View {
        Section {
            Text(viewModel.nightscoutStatus)
            Divider().opacity(0.35)
        } header: {
            Text("Status")
        }
        .listRowBackground(Color.clear)
    }
}
