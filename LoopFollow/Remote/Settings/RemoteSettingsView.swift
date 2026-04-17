//
//  RemoteSettingsView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.
//  Updated on 2024-09-16.

//

import SwiftUI
import HealthKit

@available(iOS 16.0, *)
struct RemoteSettingsView: View {
    @ObservedObject var viewModel: RemoteSettingsViewModel
    @FocusState private var focusedField: Field?

    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil

    enum Field: Hashable {
        case user
        case deviceToken
        case sharedSecret
        case apnsKey
        case teamId
        case keyId
        case bundleId
        case maxBolus
    }

    enum AlertType {
        case validation
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            Form {
                // Remote Type Section
                // Instructions for Remote Type options
                Section {
                    Picker("Fjärrkommandon", selection: $viewModel.remoteType) {
                        Text("Ingen").tag(RemoteType.none)
                        Text("Nightscout").tag(RemoteType.nightscout)
                        if BuildDetails.default.branch?.lowercased() != "main" {
                            Text("Trio Remote Control").tag(RemoteType.trc)
                        }
                        Text("SMS Remote Control").tag(RemoteType.sms)
                    }
                    .pickerStyle(MenuPickerStyle())

                    Text("Nightscout använder Care portal-registreringar för fjärrstyning av Trio")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("Trio Remote Control använder APNS för att skicka säkra kommandon från Loop Follow till Trio")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("SMS Remote Control använder SMS/iMessage över iOS genvägar eller Twilio SMS API för att skicka kommandon från Loop Follow till Trio")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .listRowBackground(Color(UIColor.systemGray).opacity(0.15))

                // User Information Section
                if viewModel.remoteType != .none {
                    Section(header: Text("Användarinformation")) {
                        HStack {
                            Text("Användare")
                            TextField("Ange användare", text: $viewModel.user)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .user)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                }

                // Trio Remote Control Settings Section
                if viewModel.remoteType == .trc {
                    Section(header: Text("Trio remote inställningar")) {
                        HStack {
                            Text("Shared Secret")
                            TextField("Enter Shared Secret", text: $viewModel.sharedSecret)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .sharedSecret)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("APNS Key ID")
                            TextField("Enter APNS Key ID", text: $viewModel.keyId)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .focused($focusedField, equals: .keyId)
                                .multilineTextAlignment(.trailing)
                        }

                        VStack(alignment: .leading) {
                            Text("APNS Key")
                            TextEditor(text: $viewModel.apnsKey)
                                .frame(height: 100)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                                .focused($focusedField, equals: .apnsKey)
                        }

                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))

                    // Guardrails Section
                    Section(header: Text("Maxgränser")) {
                        HStack {
                            Text("Max bolus")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $viewModel.maxBolus,
                                maxLength: 4,
                                unit: HKUnit.internationalUnit(),
                                allowDecimalSeparator: true,
                                minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0.0),
                                maxValue: HKQuantity(unit: .internationalUnit(), doubleValue: 10.0),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .frame(width: 100)
                            Text("E")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Max kh")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $viewModel.maxCarbs,
                                maxLength: 4,
                                unit: HKUnit.gram(),
                                allowDecimalSeparator: true,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 100),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .frame(width: 100)
                            Text("g")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Max protein")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $viewModel.maxProtein,
                                maxLength: 4,
                                unit: HKUnit.gram(),
                                allowDecimalSeparator: true,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 100),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .frame(width: 100)
                            Text("g")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Max fett")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $viewModel.maxFat,
                                maxLength: 4,
                                unit: HKUnit.gram(),
                                allowDecimalSeparator: true,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 100),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .frame(width: 100)
                            Text("g")
                                .foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))

                    // Meal Section
                    Section(header: Text("Måltidsinställningar")) {
                        Toggle("Måltid med bolus", isOn: $viewModel.mealWithBolus)
                            .toggleStyle(SwitchToggleStyle())

                        Toggle("Måltid med Fett/Protein/Tid", isOn: $viewModel.mealWithFatProtein)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))

                    Section(header: Text("Debug / Info")) {
                        Text("Device Token: \(Storage.shared.deviceToken.value)")
                        Text("Produktionsmiljö: \(Storage.shared.productionEnvironment.value ? "True" : "False")")
                        Text("Team ID: \(Storage.shared.teamId.value ?? "")")
                        Text("Bundle ID: \(Storage.shared.bundleId.value)")
                    }
                    .listRowBackground(Color(UIColor.systemGray).opacity(0.15))
                }
            }
            // Let the gradient show through the Form/List background
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onTapGesture { focusedField = nil }
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .validation:
                    return Alert(
                        title: Text("Valideringsfel"),
                        message: Text(alertMessage ?? "Felaktig input."),
                        dismissButton: .default(Text("OK"))
                    )
                case .none:
                    return Alert(title: Text("Okänt fel"))
                }
            }
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validation
        showAlert = true
    }
}
