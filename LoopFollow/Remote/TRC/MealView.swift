//
//  MealView.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2024-08-25.

//

import SwiftUI
import HealthKit
import LocalAuthentication

@available(iOS 16.0, *)
struct MealView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    @State private var notes: String = ""
    
    private let pushNotificationManager = PushNotificationManager()
    
    @ObservedObject private var maxCarbs = Storage.shared.maxCarbs
    @ObservedObject private var maxProtein = Storage.shared.maxProtein
    @ObservedObject private var maxFat = Storage.shared.maxFat
    @ObservedObject private var mealWithBolus = Storage.shared.mealWithBolus
    @ObservedObject private var mealWithFatProtein = Storage.shared.mealWithFatProtein
    @ObservedObject private var maxBolus = Storage.shared.maxBolus
    
    @FocusState private var carbsFieldIsFocused: Bool
    @FocusState private var proteinFieldIsFocused: Bool
    @FocusState private var fatFieldIsFocused: Bool
    @FocusState private var bolusFieldIsFocused: Bool
    
    @State private var showAlert: Bool = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var statusMessage: String? = nil
    @State private var selectedTime: Date? = nil
    @State private var isScheduling: Bool = false
    
    enum AlertType {
        case confirmMeal
        case statusSuccess
        case statusFailure
        case validationError
    }
    
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()
            VStack {
                Form {
                    Section(header: Text("Måltid")) {
                        HKQuantityInputView(
                            label: "Kolhydrater",
                            quantity: $carbs,
                            unit: .gram(),
                            maxLength: 4,
                            minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                            maxValue: HKQuantity(unit: .gram(), doubleValue: 9999),
                            isFocused: $carbsFieldIsFocused,
                            onValidationError: { _ in }
                        )
                        
                        if mealWithFatProtein.value {
                            HKQuantityInputView(
                                label: "Protein",
                                quantity: $protein,
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 9999),
                                isFocused: $proteinFieldIsFocused,
                                onValidationError: { _ in }
                            )
                            
                            HKQuantityInputView(
                                label: "Fett",
                                quantity: $fat,
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 9999),
                                isFocused: $fatFieldIsFocused,
                                onValidationError: { _ in }
                            )
                        }
                        
                        HStack {
                            Text("Anteckning")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TextField("Lägg till anteckning", text: $notes)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        if mealWithBolus.value {
                            HKQuantityInputView(
                                label: "Bolus",
                                quantity: $bolusAmount,
                                unit: .internationalUnit(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0.05),
                                maxValue: HKQuantity(unit: .internationalUnit(), doubleValue: 999),
                                isFocused: $bolusFieldIsFocused,
                                onValidationError: { _ in }
                            )
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))
                    
                    Section(header: Text("Schemalägg")) {
                        Toggle("Schemalägg till senare", isOn: $isScheduling)
                        if isScheduling {
                            DatePicker(
                                "Välj tid",
                                selection: Binding(
                                    get: { self.selectedTime ?? Date() },
                                    set: { self.selectedTime = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(CompactDatePickerStyle())
                            
                            if bolusAmount.doubleValue(for: .internationalUnit()) > 0 {
                                Text("OBS! Denna måltid schemaläggs, men bolusen ges omgående!")
                            }
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))
                    
                    LoadingButtonView(
                        buttonText: primaryButtonTitle,
                        progressText: "Skickar måltidsregistrering...",
                        isLoading: isLoading,
                        action: {
                            carbsFieldIsFocused = false
                            proteinFieldIsFocused = false
                            fatFieldIsFocused = false

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                guard carbs.doubleValue(for: .gram()) != 0 ||
                                        protein.doubleValue(for: .gram()) != 0 ||
                                        fat.doubleValue(for: .gram()) != 0 else {
                                    return
                                }
                                if !showAlert {
                                    alertType = .confirmMeal
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
                .navigationTitle("Måltid")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            selectedTime = nil
            isScheduling = false
        }
        .alert(isPresented: $showAlert) {
            switch alertType {
            case .confirmMeal:
                let carbsAmount = carbs.doubleValue(for: HKUnit.gram())
                let proteinAmount = protein.doubleValue(for: HKUnit.gram())
                let fatAmount = fat.doubleValue(for: HKUnit.gram())
                let bolusAmount = bolusAmount.doubleValue(for: .internationalUnit())
                
                var message = "Är du säker på att du vill skicka måltidsregistreringen"
                
                if let selectedTime = selectedTime {
                    let timeFormatter = DateFormatter()
                    timeFormatter.timeStyle = .short
                    let timeString = timeFormatter.string(from: selectedTime)
                    message += " till \(timeString)?"
                } else {
                    message += " nu?"
                }
                
                if carbsAmount > 0 {
                    message += String(format: "\n\nKolhydrater: %.0f g", carbsAmount)
                }
                
                if proteinAmount > 0 {
                    message += String(format: "\nProtein: %.0f g", proteinAmount)
                }
                
                if fatAmount > 0 {
                    message += String(format: "\nFett: %.0f g", fatAmount)
                }
                
                if bolusAmount > 0 {
                    message += String(format: "\nBolus: %.2f E", bolusAmount)
                }
                
                if !notes.isEmpty {
                    message += String(format: "\n\nAnteckning: %@", notes)
                }
                
                return Alert(
                    title: Text("Bekräfta måltid"),
                    message: Text(message),
                    primaryButton: .default(Text("Bekräfta"), action: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if bolusAmount > 0 {
                                authenticateUser { success in
                                    if success {
                                        sendMealCommand()
                                    }
                                }
                            } else {
                                sendMealCommand()
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
            case .validationError:
                return Alert(
                    title: Text("Validation Error"),
                    message: Text(alertMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            case .none:
                return Alert(title: Text("Unknown Alert"))
            }
        }
    }

    private var buttonGuardrailMessage: String? {
        let bolusValue = bolusAmount.doubleValue(for: .internationalUnit())
        let carbsValue = carbs.doubleValue(for: .gram())
        let fatValue = fat.doubleValue(for: .gram())
        let proteinValue = protein.doubleValue(for: .gram())

        let maxBolusValue = maxBolus.value.doubleValue(for: .internationalUnit())
        let maxCarbsValue = maxCarbs.value.doubleValue(for: .gram())
        let maxFatValue = maxFat.value.doubleValue(for: .gram())
        let maxProteinValue = maxProtein.value.doubleValue(for: .gram())

        if bolusValue > maxBolusValue {
            return String(format: "⛔️ Max bolus %.1f E", maxBolusValue)
        }
        if carbsValue > maxCarbsValue {
            return String(format: "⛔️ Max kolhydrater %.0f g", maxCarbsValue)
        }
        if fatValue > maxFatValue {
            return String(format: "⛔️ Max fett %.0f g", maxFatValue)
        }
        if proteinValue > maxProteinValue {
            return String(format: "⛔️ Max protein %.0f g", maxProteinValue)
        }
        return nil
    }

    private var primaryButtonTitle: String {
        buttonGuardrailMessage ?? "Skicka måltid"
    }

    private var isButtonDisabled: Bool {
        isLoading || buttonGuardrailMessage != nil
    }

    private func sendMealCommand() {
        isLoading = true

        var scheduledDate: Date? = nil
        if isScheduling, let selectedTime = selectedTime {
            let calendar = Calendar.current
            let now = Date()
            let selectedDateComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
            let currentSecond = calendar.component(.second, from: now)
            scheduledDate = calendar.date(bySettingHour: selectedDateComponents.hour ?? 0,
                                          minute: selectedDateComponents.minute ?? 0,
                                          second: currentSecond,
                                          of: now) ?? now
        }
        
        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Remote" : notes

        pushNotificationManager.sendMealPushNotification(
            carbs: carbs,
            protein: protein,
            fat: fat,
            bolusAmount: bolusAmount,
            notes: finalNotes,
            scheduledTime: scheduledDate
        ) { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    statusMessage = "Måltidskommando lyckades"
                    carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
                    notes = ""
                    selectedTime = nil
                    isScheduling = false
                    alertType = .statusSuccess
                } else {
                    statusMessage = errorMessage ?? "Måltidskommando misslyckades!"
                    alertType = .statusFailure
                }
                showAlert = true
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func handleValidationError(_ message: String) {
        alertMessage = message
        alertType = .validationError
        showAlert = true
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
}
