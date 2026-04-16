//
//  TempTargetView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import SwiftUI
import HealthKit

@available(iOS 16.0, *)
struct TempTargetView: View {
    @Environment(\.presentationMode) private var presentationMode
    private let pushNotificationManager = PushNotificationManager()

    @ObservedObject var device = ObservableUserDefaults.shared.device
    @ObservedObject var tempTarget = Observable.shared.tempTarget

    @State private var newHKTarget = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 0.0)
    @State private var duration = HKQuantity(unit: .minute(), doubleValue: 0.0)
    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil

    @State private var showPresetSheet: Bool = false
    @State private var presetName = ""
    @ObservedObject var presetManager = TempTargetPresetManager.shared

    @FocusState private var targetFieldIsFocused: Bool
    @FocusState private var durationFieldIsFocused: Bool

    enum AlertType {
        case confirmCommand
        case statusSuccess
        case statusFailure
        case validation
        case confirmCancellation
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()
        VStack {
            if device.value != "Trio" {
                ErrorMessageView(
                    message: "Remote commands are currently only available for Trio."
                )
            } else {
                Form {
                    if let tempTargetValue = tempTarget.value {
                        Section(header: Text("Befintliga tillfälliga mål")) {
                            HStack {
                                Text("Nuvarande mål")
                                Spacer()
                                Text(Localizer.formatQuantity(tempTargetValue))
                                Text(UserDefaultsRepository.getPreferredUnit().localizedShortUnitString).foregroundColor(.secondary)
                            }
                            Button {
                                alertType = .confirmCancellation
                                showAlert = true
                            } label: {
                                HStack {
                                    Text("Avbryt tillfälligt mål")
                                    Spacer()
                                    Image(systemName: "xmark.app")
                                        .font(.title)
                                }
                            }
                            .tint(.red)
                        }
                        .listRowBackground(Color(.systemGray).opacity(0.15))
                    }
                    Section() {
                        HStack {
                            Text("Målvärde")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $newHKTarget,
                                maxLength: 4,
                                unit: UserDefaultsRepository.getPreferredUnit(),
                                minValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80),
                                maxValue: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .focused($targetFieldIsFocused)
                            Text(UserDefaultsRepository.getPreferredUnit().localizedShortUnitString).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Varaktighet")
                            Spacer()
                            TextFieldWithToolBar(
                                quantity: $duration,
                                maxLength: 4,
                                unit: HKUnit.minute(),
                                minValue: HKQuantity(unit: .minute(), doubleValue: 5),
                                onValidationError: { message in
                                    handleValidationError(message)
                                }
                            )
                            .focused($durationFieldIsFocused)
                            Text("minuter").foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))
                    Section() {
                    HStack {
                        if #available(iOS 26.0, *) {
                            Button {
                                alertType = .confirmCommand
                                showAlert = true
                                targetFieldIsFocused = false
                                durationFieldIsFocused = false
                            } label: {
                                Text("Aktivera")
                            }
                            .disabled(isButtonDisabled)
                            .buttonStyle(.glassProminent)
                            .padding(.leading, -15)
                            //.font(.callout)
                            //.controlSize(.mini)
                        } else {
                            // Fallback on earlier versions
                        }
                        
                        Spacer()
                        
                        if #available(iOS 26.0, *) {
                            Button {
                                showPresetSheet = true
                                targetFieldIsFocused = false
                                durationFieldIsFocused = false
                            } label: {
                                Text("Spara som förval")
                            }
                            .disabled(isButtonDisabled)
                            .buttonStyle(.glassProminent)
                            .padding(.trailing, -15)
                            //.font(.callout)
                            //.controlSize(.mini)
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                    .listRowBackground(Color(.clear))
                    
                    if !presetManager.presets.isEmpty {
                        Section(header: Text("Förval")) {
                            ForEach(presetManager.presets) { preset in
                                HStack {
                                    Text(preset.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    alertType = .confirmCommand
                                    newHKTarget = preset.target
                                    duration = preset.duration
                                    showAlert = true
                                    targetFieldIsFocused = false
                                    durationFieldIsFocused = false
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        if let index = presetManager.presets.firstIndex(where: { $0.id == preset.id }) {
                                            presetManager.deletePreset(at: index)
                                        }
                                        targetFieldIsFocused = false
                                        durationFieldIsFocused = false
                                    } label: {
                                        Label("Radera", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color(.systemGray).opacity(0.15))
                    }
                }
                
                if isLoading {
                    ProgressView("Vänligen vänta...")
                        .padding()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Tillfälligt mål")
        .navigationBarTitleDisplayMode(.inline)
    }
            .alert(isPresented: $showAlert) {
                switch alertType {
                case .confirmCommand:
                    return Alert(
                        title: Text("Bekräfta kommando"),
                        message: Text("Nytt mål: \(Localizer.formatQuantity(newHKTarget)) \(UserDefaultsRepository.getPreferredUnit().localizedShortUnitString)\nVaraktighet: \(Int(duration.doubleValue(for: HKUnit.minute()))) minuter"),
                        primaryButton: .default(Text("Bekräfta"), action: {
                            enactTempTarget()
                        }),
                        secondaryButton: .cancel(Text("Avbryt"))
                    )
                case .statusSuccess:
                    return Alert(
                        title: Text("Status"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"), action: {
                            presentationMode.wrappedValue.dismiss()
                        })
                    )
                case .statusFailure:
                    return Alert(
                        title: Text("Status"),
                        message: Text(statusMessage ?? ""),
                        dismissButton: .default(Text("OK"))
                    )
                case .confirmCancellation:
                    return Alert(
                        title: Text("Bekräfta avbryt"),
                        message: Text("AÄr du säker på att du vill avbryta nuvarande tillfälliga mål?"),
                        primaryButton: .default(Text("Bekräfta"), action: {
                            cancelTempTarget()
                        }),
                        secondaryButton: .cancel(Text("Avbryt"))
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
            .sheet(isPresented: $showPresetSheet) {
                ZStack {
                    ThemeBackground()
                        .ignoresSafeArea()
                VStack {
                    Text("Spara förval")
                        .font(.headline)
                        .padding()
                    TextField("Förval namn", text: $presetName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    HStack {
                        if #available(iOS 26.0, *) {
                            Button("Avbryt") {
                                showPresetSheet = false
                            }
                            .buttonStyle(.glassProminent)
                            .padding()
                        } else {
                            // Fallback on earlier versions
                        }
                        Spacer()
                        if #available(iOS 26.0, *) {
                            Button("Spara") {
                                presetManager.addPreset(name: presetName, target: newHKTarget, duration: duration)
                                presetName = ""
                                showPresetSheet = false
                            }
                            .disabled(presetName.isEmpty)
                            .buttonStyle(.glassProminent)
                            .padding()
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            }
    }

    private var isButtonDisabled: Bool {
        return newHKTarget.doubleValue(for: UserDefaultsRepository.getPreferredUnit()) == 0 ||
        duration.doubleValue(for: HKUnit.minute()) == 0 || isLoading
    }

    private func enactTempTarget() {
        isLoading = true

        pushNotificationManager.sendTempTargetPushNotification(target: newHKTarget, duration: duration) { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.statusMessage = "Tillfälligt mål-kommando lyckades."
                    self.alertType = .statusSuccess
                } else {
                    self.statusMessage = errorMessage ?? "Tillfälligt mål-kommando misslyckades!"
                    self.alertType = .statusFailure
                }
                self.showAlert = true
            }
        }
    }

    private func cancelTempTarget() {
        isLoading = true

        pushNotificationManager.sendCancelTempTargetPushNotification { success, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.statusMessage = "Avbryt tillfälligt mål-kommando lyckades."
                    self.alertType = .statusSuccess
                } else {
                    self.statusMessage = errorMessage ?? "Avbryt tillfälligt mål-kommando misslyckades!"
                    self.alertType = .statusFailure
                }
                self.showAlert = true
            }
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validation
        showAlert = true
    }
}
