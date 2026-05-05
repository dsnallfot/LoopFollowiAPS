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
                Section(header: Text("Realtidsuppdateringar")) {
                    webSocketSection
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
    
    @State private var showWebSocketInfo = false

        private var webSocketSection: some View {
            Section(header: webSocketSectionHeader) {
                Toggle("Aktivera WebSocket", isOn: $viewModel.webSocketEnabled)
                if viewModel.webSocketEnabled {
                    HStack {
                        //Text("Status")
                        //Spacer()
                        Text(viewModel.webSocketStatus)
                            //.foregroundColor(viewModel.webSocketStatusColor)
                    }
                }
            }
            .sheet(isPresented: $showWebSocketInfo) {
                NavigationStack {
                    ScrollView {
                        Text("""
                        När funktionen är aktiverad upprätthåller LoopFollow en live-anslutning till Nightscout via WebSocket när appen är öppen. Detta gör att uppdateringar (nya glukosvärden, behandlingar, enhetsstatus) kommer in inom några sekunder istället för att vänta på nästa uppdateringsintervall.
                        """)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Realtidsuppdateringar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Klar") { showWebSocketInfo = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }

        private var webSocketSectionHeader: some View {
            HStack(spacing: 4) {
                Text("Observera")
                Button {
                    showWebSocketInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
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
