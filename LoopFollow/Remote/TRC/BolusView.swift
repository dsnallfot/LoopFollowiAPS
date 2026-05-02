//
//  BolusView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import SwiftUI
import HealthKit
import LocalAuthentication

@available(iOS 16.0, *)
struct BolusView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    private let pushNotificationManager = PushNotificationManager()
    @ObservedObject private var maxBolus = Storage.shared.maxBolus

    @FocusState private var bolusFieldIsFocused: Bool

    @State private var showAlert = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading = false
    @State private var statusMessage: String? = nil

    enum AlertType {
        case confirmBolus
        case statusSuccess
        case statusFailure
        case validation
    }

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()
        VStack {
            Form {
                Section {
                    HKQuantityInputView(
                        label: "Bolus",
                        quantity: $bolusAmount,
                        unit: .internationalUnit(),
                        maxLength: 4,
                        minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0.05),
                        maxValue: permissiveBolusInputMax,
                        isFocused: $bolusFieldIsFocused,
                        onValidationError: { _ in }
                    )
                }
                .listRowBackground(Color(.systemGray).opacity(0.15))
                
                LoadingButtonView(
                    buttonText: primaryButtonTitle,
                    progressText: "Skickar Bolus...",
                    isLoading: isLoading,
                    action: {
                        bolusFieldIsFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if bolusAmount.doubleValue(for: HKUnit.internationalUnit()) > 0.0 {
                                alertType = .confirmBolus
                                showAlert = true
                            }
                        }
                    },
                    isDisabled: isButtonDisabled
                )
                .id("\(primaryButtonTitle)-\(isButtonDisabled)-\(isLoading)")
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                bolusFieldIsFocused = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    bolusFieldIsFocused = true
                }
            }
        }
    }
                .alert(isPresented: $showAlert) {
                    switch alertType {
                    case .confirmBolus:
                        return Alert(
                            title: Text("Bekräfta Bolus"),
                            message: Text("Är du säker på att du vill skicka \(bolusAmount.doubleValue(for: HKUnit.internationalUnit()), specifier: "%.2f") E?"),
                            primaryButton: .default(Text("Bekräfta"), action: {
                                authenticateUser { success in
                                    if success {
                                        sendBolus()
                                    }
                                }
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

    private var permissiveBolusInputMax: HKQuantity {
        HKQuantity(unit: .internationalUnit(), doubleValue: 999)
    }

    private var buttonGuardrailMessage: String? {
        let bolusValue = bolusAmount.doubleValue(for: .internationalUnit())
        let maxBolusValue = maxBolus.value.doubleValue(for: .internationalUnit())

        if bolusValue > maxBolusValue {
            return String(format: "⛔️ Max bolus %.1f E", maxBolusValue)
        }
        return nil
    }

    private var primaryButtonTitle: String {
        buttonGuardrailMessage ?? "Skicka Bolus"
    }

    private var isButtonDisabled: Bool {
        isLoading || buttonGuardrailMessage != nil
    }

    private func sendBolus() {
        guard !isLoading else { return }
        isLoading = true

        pushNotificationManager.sendBolusPushNotification(bolusAmount: bolusAmount) { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    statusMessage = "Boluskommando lyckades."
                    bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
                    alertType = .statusSuccess
                } else {
                    statusMessage = errorMessage ?? "Boluskommando misslyckades!"
                    alertType = .statusFailure
                }
                showAlert = true
            }
        }
    }

    private func authenticateUser(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        let reason = "Bekräfta din identitet för att skicka bolus."

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validation
        showAlert = true
    }
}
