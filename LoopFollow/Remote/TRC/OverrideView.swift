//
//  OverrideView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-10-07.

//

import SwiftUI
import HealthKit

struct OverrideView: View {
    @Environment(\.presentationMode) private var presentationMode
    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject var device = ObservableUserDefaults.shared.device
    @ObservedObject var overrideNote = Observable.shared.override

    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil

    @State private var selectedOverride: ProfileManager.TrioOverride? = nil
    @State private var showConfirmation: Bool = false

    @FocusState private var noteFieldIsFocused: Bool

    private var profileManager = ProfileManager.shared

    enum AlertType {
        case confirmActivation
        case confirmCancellation
        case statusSuccess
        case statusFailure
        case validation
    }

    var body: some View {
        NavigationView {
            VStack {
                if device.value != "Trio" {
                    ErrorMessageView(
                        message: "Remote commands are currently only available for Trio."
                    )
                } else {
                    Form {
                        if let activeNote = overrideNote.value {
                            Section(header: Text("Aktiv Override")) {
                                HStack {
                                    Text("Override")
                                    Spacer()
                                    Text(activeNote)
                                        .foregroundColor(.secondary)
                                }
                                Button {
                                    alertType = .confirmCancellation
                                    showAlert = true
                                } label: {
                                    HStack {
                                        Text("Avbryt Override")
                                        Spacer()
                                        Image(systemName: "xmark.app")
                                            .font(.title)
                                    }
                                }
                                .tint(.red)
                            }
                        }
                        
                        Section(header: Text("Tillgängliga Overrides")) {
                            if profileManager.trioOverrides.isEmpty {
                                Text("No overrides available.")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(profileManager.trioOverrides, id: \.name) { override in
                                    Button(action: {
                                        selectedOverride = override
                                        alertType = .confirmActivation
                                        showAlert = true
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(override.name)
                                                    .font(.headline)
                                                if let duration = override.duration {
                                                    Text("Varaktighet: \(Int(duration)) minuter")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let percentage = override.percentage {
                                                    Text("Procent: \(Int(percentage))%")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                if let target = override.target {
                                                    Text("Mål: \(Localizer.formatQuantity(target)) \(UserDefaultsRepository.getPreferredUnit().localizedShortUnitString)")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.right.circle")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if isLoading {
                        ProgressView("Vänligen vänta...")
                            .padding()
                    }
                }
            }
                .navigationTitle("Override")
                .navigationBarTitleDisplayMode(.inline)
                .alert(isPresented: $showAlert) {
                    switch alertType {
                    case .confirmActivation:
                        return Alert(
                            title: Text("Aktivera Override"),
                            message: Text("Vill du aktivera override '\(selectedOverride?.name ?? "")'?"),
                            primaryButton: .default(Text("Confirm"), action: {
                                if let override = selectedOverride {
                                    activateOverride(override)
                                }
                            }),
                            secondaryButton: .cancel()
                        )
                    case .confirmCancellation:
                        return Alert(
                            title: Text("Avbryt Override"),
                            message: Text("Är du säker på att du vill avbryta pågående override"),
                            primaryButton: .default(Text("Bekräfta"), action: {
                                cancelOverride()
                            }),
                            secondaryButton: .cancel()
                        )
                    case .statusSuccess:
                        return Alert(
                            title: Text("Lyckades"),
                            message: Text(statusMessage ?? ""),
                            dismissButton: .default(Text("OK"), action: {
                                presentationMode.wrappedValue.dismiss()
                            })
                        )
                    case .statusFailure:
                        return Alert(
                            title: Text("Fel"),
                            message: Text(statusMessage ?? "An error occurred."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .validation:
                        return Alert(
                            title: Text("Validation Error"),
                            message: Text(alertMessage ?? "Invalid input."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .none:
                        return Alert(title: Text("Unknown Alert"))
                    }
                }
            }
    }

    // MARK: - Functions

    private func activateOverride(_ override: ProfileManager.TrioOverride) {
        isLoading = true

        pushNotificationManager.sendOverridePushNotification(override: override) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.statusMessage = "Overridekommando lyckades."
                    self.alertType = .statusSuccess
                } else {
                    self.statusMessage = errorMessage ?? "Overridekommando misslyckades!"
                    self.alertType = .statusFailure
                }
                self.showAlert = true
            }
        }
    }

    private func cancelOverride() {
        isLoading = true

        pushNotificationManager.sendCancelOverridePushNotification { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.statusMessage = "Avbryt override-kommando lyckades."
                    self.alertType = .statusSuccess
                } else {
                    self.statusMessage = errorMessage ?? "Avbryt override-kommando misslyckades!"
                    self.alertType = .statusFailure
                }
                self.showAlert = true
            }
        }
    }
}
