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
    @State private var isUsingCalculatedBolus: Bool = false
    @State private var notes: String = ""
    
    private let minPredBGThreshold: Double = 3.9
    private let minEvBGThreshold: Double = 3.9
    
    private let pushNotificationManager = PushNotificationManager()
    
    @ObservedObject private var maxCarbs = Storage.shared.maxCarbs
    @ObservedObject private var maxProtein = Storage.shared.maxProtein
    @ObservedObject private var maxFat = Storage.shared.maxFat
    @ObservedObject private var mealWithBolus = Storage.shared.mealWithBolus
    @ObservedObject private var mealWithFatProtein = Storage.shared.mealWithFatProtein
    @ObservedObject private var maxBolus = Storage.shared.maxBolus
    @ObservedObject private var CRValue = Storage.shared.sharedCRValue
    
    @ObservedObject private var showAdvancedBolusCalc = Storage.shared.showAdvancedBolusCalc

    @State private var showBolusCalculationSheet: Bool = false
    
    @FocusState private var carbsFieldIsFocused: Bool
    @FocusState private var proteinFieldIsFocused: Bool
    @FocusState private var fatFieldIsFocused: Bool
    @FocusState private var bolusFieldIsFocused: Bool
    @State private var notesFieldIsFocused: Bool = false
    
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
                    Section() {
                        HKQuantityInputView(
                            label: "Kolhydrater",
                            quantity: $carbs,
                            unit: .gram(),
                            maxLength: 4,
                            minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                            maxValue: HKQuantity(unit: .gram(), doubleValue: 9999),
                            isFocused: $carbsFieldIsFocused,
                            onValidationError: { _ in },
                            nextToolbarAction: {
                                focusNextMealInput(after: .carbs)
                            },
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
                                onValidationError: { _ in },
                                nextToolbarAction: {
                                    focusNextMealInput(after: .protein)
                                },
                            )
                            
                            HKQuantityInputView(
                                label: "Fett",
                                quantity: $fat,
                                unit: .gram(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .gram(), doubleValue: 0),
                                maxValue: HKQuantity(unit: .gram(), doubleValue: 9999),
                                isFocused: $fatFieldIsFocused,
                                onValidationError: { _ in },
                                nextToolbarAction: {
                                    focusNextMealInput(after: .fat)
                                },
                            )
                        }
                        HStack {
                            Text("Anteckning")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            MealNotesTextField(
                                text: $notes,
                                isFocused: $notesFieldIsFocused,
                                nextToolbarAction: {
                                    focusNextMealInput(after: .notes)
                                }
                            )
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))
                    Section() {
                        
                        if mealWithBolus.value {
                            HStack(spacing: 8) {
                                if showAdvancedBolusCalc.value {
                                    Button {
                                        showBolusCalculationSheet = true
                                    } label: {
                                        Image(systemName: advancedBolusCalcIconName)
                                    }
                                    .disabled(mealBolusCalculation == nil)

                                } else {
                                    Text("CR: \(formattedCRValue) g/E")
                                        .monospacedDigit()
                                }
                                
                                Spacer()

                                Button {
                                    toggleCalculatedBolus()
                                } label: {
                                    showAdvancedBolusCalc.value ? Text("Förslag bolus:") : Text("Beräknad bolus:")
                                    Text("\(formattedCalculatedBolus) E")
                                        .monospacedDigit()
                                    Image(systemName: isUsingCalculatedBolus ? "plus.app.fill" : "plus.app")
                                        //.fontWeight(.semibold)
                                }
                                .buttonStyle(.plain)
                                .disabled(calculatedBolusValue <= 0)
                                //.foregroundColor(.blue)
                            }
                            //.font(.subheadline)
                            .foregroundColor(advancedBolusCalcRowColor)
                            .fontWeight(.semibold)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                            HKQuantityInputView(
                                label: "Bolus",
                                quantity: $bolusAmount,
                                unit: .internationalUnit(),
                                maxLength: 4,
                                minValue: HKQuantity(unit: .internationalUnit(), doubleValue: 0.05),
                                maxValue: HKQuantity(unit: .internationalUnit(), doubleValue: 999),
                                isFocused: $bolusFieldIsFocused,
                                onValidationError: { _ in },
                                nextToolbarAction: {
                                    focusNextMealInput(after: .bolus)
                                },
                            )
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))
                    
                    if mealWithFatProtein.value {
                    Section() {
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
                }
                    
                    LoadingButtonView(
                        buttonText: primaryButtonTitle,
                        progressText: "Skickar måltidsregistrering...",
                        isLoading: isLoading,
                        action: {
                            clearMealInputFocus()

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

            clearMealInputFocus()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                carbsFieldIsFocused = true
            }
/*
            // Debug: Fetch sharedCRValue from DeviceStatusOpenAPS
            print("📊 sharedCRValue from DeviceStatusOpenAPS: \(CRValue.value)")

            let storage = Storage.shared

            print("📊 sharedRawMinPredBG: \(storage.sharedRawMinPredBG.value)")
            print("📊 sharedRawEvBG: \(storage.sharedRawEvBG.value)")
            print("📊 sharedRawIOB: \(storage.sharedRawIOB.value)")
            print("📊 sharedRawCOB: \(storage.sharedRawCOB.value)")
            print("📊 sharedRawISF: \(storage.sharedRawISF.value)")
            print("📊 sharedRawCarbReq: \(storage.sharedRawCarbReq.value)")
            print("📊 sharedRawInsulinReq: \(storage.sharedRawInsulinReq.value)")
            print("📊 sharedRawBG: \(storage.sharedRawBG.value)")
            print("📊 sharedRawBG15MinTrend: \(storage.sharedRawBG15MinTrend.value)")
            print("📊 sharedRawTarget (mmol/L): \(storage.sharedRawTarget.value)")
            //printMealBolusCalculationDebug()
            */
        }
        .onChange(of: carbs.doubleValue(for: .gram())) { _ in
            //printMealBolusCalculationDebug()

            if isUsingCalculatedBolus {
                bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: calculatedBolusValue)
            }
        }
        .onChange(of: bolusAmount.doubleValue(for: .internationalUnit())) { newValue in
            let roundedCalculated = (calculatedBolusValue * 100).rounded() / 100
            let roundedCurrent = (newValue * 100).rounded() / 100
            if isUsingCalculatedBolus, roundedCurrent != roundedCalculated {
                isUsingCalculatedBolus = false
            }
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
        .sheet(isPresented: $showBolusCalculationSheet) {
            if let calculation = mealBolusCalculation {
                MealBolusCalculationView(
                    calculation: calculation,
                    recommendedBolus: advancedCalculatedBolusValue,
                    minPredBG: Storage.shared.sharedRawMinPredBG.value,
                    evBG: Storage.shared.sharedRawEvBG.value,
                    minPredBGThreshold: minPredBGThreshold,
                    minEvBGThreshold: minEvBGThreshold,
                    useRecommendedBolus: {
                        applyCalculatedBolus()
                    }
                )
            }
        }
    }
    
    private enum MealInputField {
        case carbs, protein, fat, notes, bolus
    }
    
    struct MealBolusCalculation {
        let bg: Double
        let target: Double
        let isf: Double
        let iob: Double
        let cob: Double
        let pendingCarbs: Double
        let cr: Double
        let delta: Double
        let glucoseEffect: Double
        let iobEffect: Double
        let cobEffect: Double
        let deltaEffect: Double
        let fullBolus: Double
        let recommendedBolus: Double
    }

    private var mealInputFocusOrder: [MealInputField] {
        mealWithFatProtein.value
            ? [.carbs, .protein, .fat, .notes, .bolus]
            : [.carbs, .notes, .bolus]
    }

    private func clearMealInputFocus() {
        carbsFieldIsFocused = false
        proteinFieldIsFocused = false
        fatFieldIsFocused = false
        notesFieldIsFocused = false
        bolusFieldIsFocused = false
    }

    private func focusNextMealInput(after currentField: MealInputField) {
        let order = mealInputFocusOrder
        guard let currentIndex = order.firstIndex(of: currentField) else { return }

        let nextIndex = order.index(after: currentIndex) == order.endIndex
            ? order.startIndex
            : order.index(after: currentIndex)

        clearMealInputFocus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            switch order[nextIndex] {
            case .carbs: carbsFieldIsFocused = true
            case .protein: proteinFieldIsFocused = true
            case .fat: fatFieldIsFocused = true
            case .notes: notesFieldIsFocused = true
            case .bolus: bolusFieldIsFocused = true
            }
        }
    }
    
    private func floorToTwoDecimals(_ value: Double) -> Double {
        floor(value * 100) / 100
    }

    private func floorToBolusStep(_ value: Double) -> Double {
        let roundedToTwoDecimals = (value * 100).rounded() / 100
        return max(0, floor(roundedToTwoDecimals * 20) / 20)
    }

    private var mealBolusCalculation: MealBolusCalculation? {
        let storage = Storage.shared

        let bg = storage.sharedRawBG.value
        let target = storage.sharedRawTarget.value
        let isf = storage.sharedRawISF.value
        let iob = storage.sharedRawIOB.value
        let cob = storage.sharedRawCOB.value
        let pendingCarbs = carbs.doubleValue(for: .gram())
        let cr = parsedCRValue ?? 0.0
        let delta = storage.sharedRawBG15MinTrend.value

        guard bg > 0, target > 0, isf > 0, cr > 0 else { return nil }

        let glucoseEffect = floorToTwoDecimals((bg - target) / isf)
        let iobEffect = -iob
        let totalCarbs = cob + pendingCarbs
        let cobEffect = floorToTwoDecimals(totalCarbs / cr)
        let deltaEffect = floorToTwoDecimals(delta / isf)
        let fullBolus = glucoseEffect + iobEffect + cobEffect + deltaEffect
        let recommendedBolus = floorToBolusStep(fullBolus)

        return MealBolusCalculation(
            bg: bg,
            target: target,
            isf: isf,
            iob: iob,
            cob: cob,
            pendingCarbs: pendingCarbs,
            cr: cr,
            delta: delta,
            glucoseEffect: glucoseEffect,
            iobEffect: iobEffect,
            cobEffect: cobEffect,
            deltaEffect: deltaEffect,
            fullBolus: fullBolus,
            recommendedBolus: recommendedBolus
        )
    }
/*
    private func printMealBolusCalculationDebug() {
        guard let calculation = mealBolusCalculation else {
            print("🧮 Meal bolus calculation: saknar giltiga värden")
            return
        }

        print("🧮 Meal bolus calculation")
        print("🧮 bg: \(calculation.bg)")
        print("🧮 target: \(calculation.target)")
        print("🧮 isf: \(calculation.isf)")
        print("🧮 iob: \(calculation.iob)")
        print("🧮 cob: \(calculation.cob)")
        print("🧮 pendingCarbs: \(calculation.pendingCarbs)")
        print("🧮 cr: \(calculation.cr)")
        print("🧮 delta: \(calculation.delta)")
        print("🧮 glucoseEffect: \(calculation.glucoseEffect)")
        print("🧮 iobEffect: \(calculation.iobEffect)")
        print("🧮 cobEffect: \(calculation.cobEffect)")
        print("🧮 deltaEffect: \(calculation.deltaEffect)")
        print("🧮 fullBolus: \(calculation.fullBolus)")
        print("🧮 recommendedBolus: \(calculation.recommendedBolus)")
    }
    */

    private var parsedCRValue: Double? {
        let normalized = CRValue.value.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var formattedCRValue: String {
        guard let parsedCRValue, parsedCRValue > 0 else { return "--.-" }
        return String(format: "%.0f", parsedCRValue)
    }

    private var simpleCalculatedBolusValue: Double {
        guard let parsedCRValue, parsedCRValue > 0 else { return 0.0 }
        let carbsValue = carbs.doubleValue(for: .gram())
        let raw = carbsValue / parsedCRValue
        let step = 0.05
        return floor(raw / step) * step
    }

    private var advancedCalculatedBolusValue: Double {
        mealBolusCalculation?.recommendedBolus ?? 0.0
    }

    private var effectiveCalculatedBolusValue: Double {
        showAdvancedBolusCalc.value ? advancedCalculatedBolusValue : simpleCalculatedBolusValue
    }

    private var calculatedBolusValue: Double {
        effectiveCalculatedBolusValue
    }

    private var hasEvBGLowWarning: Bool {
        Storage.shared.sharedRawEvBG.value < minEvBGThreshold
    }

    private var hasMinPredBGLowWarning: Bool {
        Storage.shared.sharedRawMinPredBG.value < minPredBGThreshold
    }

    private var hasAnyBolusCalcWarning: Bool {
        hasEvBGLowWarning || hasMinPredBGLowWarning
    }

    private var advancedBolusCalcIconName: String {
        hasAnyBolusCalcWarning ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var advancedBolusCalcRowColor: Color {
        guard showAdvancedBolusCalc.value else {
            return Color(UIColor.insulin.withAlphaComponent(0.7))
        }

        if hasEvBGLowWarning {
            return Color.red.opacity(0.75)
        }

        if hasMinPredBGLowWarning {
            return Color.orange.opacity(0.85)
        }

        return Color(UIColor.insulin.withAlphaComponent(0.7))
    }

    private var formattedCalculatedBolus: String {
        String(format: "%.2f", calculatedBolusValue)
    }

    private func applyCalculatedBolus() {
        let calculatedValue = calculatedBolusValue
        guard calculatedValue > 0 else { return }

        bolusFieldIsFocused = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: calculatedValue)
            isUsingCalculatedBolus = true
            showBolusCalculationSheet = false
        }
    }

    private func toggleCalculatedBolus() {
        if isUsingCalculatedBolus {
            bolusFieldIsFocused = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
                isUsingCalculatedBolus = false
            }
        } else {
            applyCalculatedBolus()
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

    private var defaultPrimaryButtonTitle: String {
        let bolusValue = bolusAmount.doubleValue(for: .internationalUnit())
        return bolusValue > 0 ? "Skicka Måltid och Bolus" : "Skicka Måltid"
    }

    private var primaryButtonTitle: String {
        buttonGuardrailMessage ?? defaultPrimaryButtonTitle
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
        let bolusValue = bolusAmount.doubleValue(for: .internationalUnit())
        let mealBolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)

        func sendMealPayload() {
            pushNotificationManager.sendMealPushNotification(
                carbs: carbs,
                protein: protein,
                fat: fat,
                bolusAmount: mealBolusAmount,
                notes: finalNotes,
                scheduledTime: scheduledDate
            ) { success, errorMessage in
                DispatchQueue.main.async {
                    isLoading = false
                    if success {
                        statusMessage = bolusValue > 0 ? "Bolus- och måltidskommando lyckades" : "Måltidskommando lyckades"
                        carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
                        protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
                        fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
                        bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
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

        if bolusValue > 0 {
            pushNotificationManager.sendBolusPushNotification(bolusAmount: bolusAmount) { success, errorMessage in
                DispatchQueue.main.async {
                    if success {
                        sendMealPayload()
                    } else {
                        isLoading = false
                        statusMessage = errorMessage ?? "Boluskommando misslyckades!"
                        alertType = .statusFailure
                        showAlert = true
                    }
                }
            }
        } else {
            sendMealPayload()
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

@available(iOS 16.0, *)
private struct MealNotesTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let nextToolbarAction: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = "Lägg till anteckning"
        textField.textAlignment = .right
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .next
        textField.delegate = context.coordinator
        textField.inputAccessoryView = makeToolbar(for: textField, context: context)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func makeToolbar(for textField: UITextField, context: Context) -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let nextButton = UIBarButtonItem(
            image: UIImage(systemName: "forward.fill"),
            style: .plain,
            target: context.coordinator,
            action: #selector(Coordinator.nextButtonTapped)
        )

        let doneButton = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .done,
            target: textField,
            action: #selector(UITextField.resignFirstResponder)
        )

        toolbar.items = [flexibleSpace, nextButton, doneButton]
        toolbar.sizeToFit()
        return toolbar
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MealNotesTextField

        init(parent: MealNotesTextField) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            parent.isFocused = false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.nextToolbarAction()
            return false
        }

        @objc func nextButtonTapped() {
            parent.nextToolbarAction()
        }
    }
}

@available(iOS 16.0, *)
private struct MealBolusCalculationView: View {
    let calculation: MealView.MealBolusCalculation
    let recommendedBolus: Double
    let minPredBG: Double
    let evBG: Double
    let minPredBGThreshold: Double
    let minEvBGThreshold: Double
    let useRecommendedBolus: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    calcRow(
                        image: "1.circle.fill",
                        label: "(Glukos - Målglukos) / ISF",
                        detail: "(\(fmtInt(calculation.bg)) − \(fmtInt(calculation.target))) / \(fmtInt(calculation.isf))",
                        result: calculation.glucoseEffect
                    )
                    
                    calcRow(
                        image: "2.circle.fill",
                        label: "IOB",
                        detail: "\(fmt(calculation.iob))",
                        result: calculation.iobEffect
                    )
                    
                    calcRow(
                        image: "3.circle.fill",
                        label: "(COB + Måltid kh) / CR",
                        detail: "(\(fmtInt(calculation.cob)) + \(fmtInt(calculation.pendingCarbs))) / \(fmtInt(calculation.cr))",
                        result: calculation.cobEffect
                    )
                    
                    calcRow(
                        image: "4.circle.fill",
                        label: "15 min delta / ISF",
                        detail: "\(fmtInt(calculation.delta)) / \(fmtInt(calculation.isf))",
                        result: calculation.deltaEffect
                    )
                    
                    summaryRow(image: "equal.circle.fill", label: "Summerad beräkning", value: "\(fmt(calculation.fullBolus)) E", color: calculation.fullBolus >= 0 ? .green : .red)

                    if let warningMessage = bolusWarningMessage {
                        bolusWarningRow(message: warningMessage, color: bolusWarningColor)
                            .padding(.leading, 15)
                    }
                    
                    Spacer(minLength: 40)
                    
                    Button {
                        useRecommendedBolus()
                    } label: {
                        summaryRowProminent(image: recommendedBolusImage, label: calculation.recommendedBolus > 0 ? " Förslag bolus" : " Ingen bolus krävs", value: "\(fmt(recommendedBolus)) E ", color: calculation.recommendedBolus > 0 ? .primary : .gray, background: recommendedBolusBackground)
                    }
                    .buttonStyle(.plain)
                    .disabled(recommendedBolus <= 0)
                    
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Bolusberäkning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stäng") {
                        dismiss()
                    }
                }
            }
        }
    }
}

    private var hasEvBGLowWarning: Bool {
        evBG < minEvBGThreshold
    }

    private var hasMinPredBGLowWarning: Bool {
        minPredBG < minPredBGThreshold
    }

    private var bolusWarningMessage: String? {
        if hasEvBGLowWarning {
            return "Den senaste prognosen visar att blodsockret är eller förväntas bli lågt (\(fmtOne(evBG)) mmol/L) inom kort.\n\nDet är troligtvis bäst att börja äta och avvakta en liten stund innan du ger en bolus till måltiden."
        }

        if hasMinPredBGLowWarning {
            return "Den senaste prognosen visar att blodsockret väntas landa inom målområdet längre fram, men kan bli lågt (\(fmtOne(minPredBG)) mmol/L) innan det vänder upp igen."
        }

        return nil
    }

    private var bolusWarningColor: Color {
        hasEvBGLowWarning ? .red : .orange
    }

    private var recommendedBolusBackground: Color {
        if calculation.recommendedBolus <= 0 {
            return Color(.systemGray).opacity(0.4)
        }

        if hasEvBGLowWarning {
            return Color.red.opacity(0.9)
        }

        if hasMinPredBGLowWarning {
            return Color.orange.opacity(0.9)
        }

        return Color(UIColor.insulin).opacity(0.9)
    }
    
    private var recommendedBolusImage: String {
        if calculation.recommendedBolus <= 0 {
            return "x.circle.fill"
        }

        if hasEvBGLowWarning {
            return "exclamationmark.triangle.fill"
        }

        if hasMinPredBGLowWarning {
            return "exclamationmark.triangle.fill"
        }

        return "checkmark.circle.fill"
    }

    private func bolusWarningRow(message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(color)

            Text(message)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func calcRow(image: String, label: String, detail: String, result: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: image)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(" ")
                    .font(.system(.headline).weight(.semibold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(detail)
                    .font(.system(.headline).weight(.semibold))
                    .monospacedDigit()
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(" ")
                    .font(.subheadline)
                
                Text("\(fmt(result)) E")
                    .font(.system(.headline).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(result >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemGray).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func summaryRow(image: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: image)
                .font(.subheadline)
            Text(label)
                .font(.system(.headline).weight(.semibold))
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundColor(color)
                .font(.system(.headline).weight(.bold))
        }
        .padding()
        .background(Color(.systemGray).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func summaryRowProminent(image: String, label: String, value: String, color: Color, background: Color) -> some View {
        HStack {
            Image(systemName: image)
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(.title3).weight(.bold))
        .padding()
        .foregroundColor(color)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func fmtOne(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func fmtInt(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
