
//
//  ComboView.swift
//  LoopFollow
//
//  Created by OpenAI on 2026-04-15.
//

import SwiftUI
import HealthKit
import LocalAuthentication

@available(iOS 16.0, *)
struct ComboView: View {
    @State private var presets: [ComboPreset] = []
    private let storage = Storage.shared
    @State private var selectedPreset: ComboPreset? = nil
    @State private var presetBeingEdited: ComboPreset? = nil
    @State private var showCreatePreset: Bool = false
    @State private var presetPendingDelete: ComboPreset? = nil
    @State private var listRefreshID = UUID()

    var body: some View {
        ZStack {
            ThemeBackground()
                .ignoresSafeArea()

            Group {
                if presets.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("Skapa ett förval genom att klicka på plustecknet uppe till höger")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sortedPresets) { preset in
                            Button {
                                selectedPreset = preset
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    HStack(spacing: 10) {
                                        if preset.carbs.doubleValue(for: .gram()) > 0 {
                                            Text("KH: \(Int(preset.carbs.doubleValue(for: .gram()))) g")
                                        }
                                        if preset.protein.doubleValue(for: .gram()) > 0 {
                                            Text("Protein: \(Int(preset.protein.doubleValue(for: .gram()))) g")
                                        }
                                        if preset.fat.doubleValue(for: .gram()) > 0 {
                                            Text("Fett: \(Int(preset.fat.doubleValue(for: .gram()))) g")
                                        }
                                        if preset.bolusAmount.doubleValue(for: .internationalUnit()) > 0 {
                                            Text(String(format: "Bolus: %.2f E", preset.bolusAmount.doubleValue(for: .internationalUnit())))
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                    if let overrideName = preset.overrideName, !overrideName.isEmpty {
                                        Text("Override: \(overrideName)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    presetPendingDelete = preset
                                } label: {
                                    Label("Radera", systemImage: "trash")
                                }

                                Button {
                                    presetBeingEdited = preset
                                } label: {
                                    Label("Redigera", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .listRowBackground(Color(.systemGray).opacity(0.15))
                        }
                    }
                    .id(listRefreshID)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationTitle("Förval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreatePreset = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $selectedPreset) { preset in
            NavigationStack {
                ComboEditorView(mode: .sendFromPreset, preset: preset) { _ in }
            }
        }
        .sheet(item: $presetBeingEdited, onDismiss: {
            refreshPresets()
        }) { preset in
            NavigationStack {
                ComboEditorView(mode: .editPreset, preset: preset) { updatedPreset in
                    if let index = presets.firstIndex(where: { $0.id == updatedPreset.id }) {
                        presets[index] = updatedPreset
                        savePresetsToStorage()
                        refreshPresets()
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePreset, onDismiss: {
            refreshPresets()
        }) {
            NavigationStack {
                ComboEditorView(mode: .createPreset, preset: nil) { newPreset in
                    presets.append(newPreset)
                    savePresetsToStorage()
                    refreshPresets()
                }
            }
        }
        .onAppear {
            refreshPresets()
        }
        .alert("Vill du verkligen radera \(presetPendingDelete?.name ?? "detta förval")?", isPresented: Binding(
            get: { presetPendingDelete != nil },
            set: { if !$0 { presetPendingDelete = nil } }
        )) {
            Button("Avbryt", role: .cancel) {
                presetPendingDelete = nil
            }
            Button("Ja", role: .destructive) {
                if let presetPendingDelete {
                    presets.removeAll { $0.id == presetPendingDelete.id }
                    savePresetsToStorage()
                    refreshPresets()
                }
                presetPendingDelete = nil
            }
        }
    }

    private var sortedPresets: [ComboPreset] {
        presets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func loadPresetsFromStorage() {
        presets = storage.comboPresets.map { ComboPreset(storageEntry: $0) }
    }

    private func refreshPresets() {
        loadPresetsFromStorage()
        listRefreshID = UUID()
    }

    private func savePresetsToStorage() {
        let sorted = presets.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        storage.comboPresets = sorted.map { $0.storageEntry }
    }
}

@available(iOS 16.0, *)
private struct ComboEditorView: View {
    enum Mode {
        case createPreset
        case editPreset
        case sendFromPreset
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let preset: ComboPreset?
    let onSavePreset: (ComboPreset) -> Void

    @State private var presetName: String = ""
    @State private var carbs = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var protein = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var fat = HKQuantity(unit: .gram(), doubleValue: 0.0)
    @State private var bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: 0.0)
    @State private var notes: String = ""

    private let pushNotificationManager = PushNotificationManager()
    private let profileManager = ProfileManager.shared

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

    @State private var selectedOverride: ProfileManager.TrioOverride? = nil
    @State private var showOverridePicker: Bool = false

    enum AlertType {
        case confirmCombo
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
                    if mode != .sendFromPreset {
                        Section(header: Text("Namn på förval")) {
                            TextField("Ange namn", text: $presetName)
                        }
                        .listRowBackground(Color(.systemGray).opacity(0.15))
                    }

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
                                label: "Bolus mängd",
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


                    Section(header: Text("Override")) {
                        Button {
                            showOverridePicker = true
                        } label: {
                            HStack {
                                Text("Välj override")
                                    .foregroundColor(.primary)

                                Spacer()

                                Text(selectedOverride?.name ?? "Ingen vald")
                                    .foregroundColor(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
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
                                Text("OBS! Denna måltid schemaläggs, men overriden aktiveras och bolusen ges omgående!")
                            }
                        }
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))

                    LoadingButtonView(
                        buttonText: primaryButtonTitle,
                        progressText: progressText,
                        isLoading: isLoading,
                        action: {
                            carbsFieldIsFocused = false
                            proteinFieldIsFocused = false
                            fatFieldIsFocused = false
                            bolusFieldIsFocused = false

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                guard carbs.doubleValue(for: .gram()) != 0 ||
                                        protein.doubleValue(for: .gram()) != 0 ||
                                        fat.doubleValue(for: .gram()) != 0 else {
                                    handleValidationError("Du måste ange minst ett värde för kolhydrater, protein eller fett.")
                                    return
                                }

                                switch mode {
                                case .createPreset, .editPreset:
                                    guard !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                        handleValidationError("Du måste ange ett namn på förvalet.")
                                        return
                                    }
                                    savePreset()
                                case .sendFromPreset:
                                    if !showAlert {
                                        alertType = .confirmCombo
                                        showAlert = true
                                    }
                                }
                            }
                        },
                        isDisabled: isButtonDisabled
                    )
                    .id("\(primaryButtonTitle)-\(isButtonDisabled)-\(isLoading)")
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Avbryt") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            if let preset {
                presetName = preset.name
                carbs = preset.carbs
                protein = preset.protein
                fat = preset.fat
                bolusAmount = preset.bolusAmount
                notes = preset.notes
                if let overrideName = preset.overrideName {
                    selectedOverride = profileManager.trioOverrides.first(where: { $0.name == overrideName })
                }
            } else {
                selectedTime = nil
                isScheduling = false
            }
        }
        .sheet(isPresented: $showOverridePicker) {
            NavigationStack {
                List {
                    if profileManager.trioOverrides.isEmpty {
                        Text("Inga overrides tillgängliga.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(profileManager.trioOverrides, id: \.name) { override in
                            Button {
                                selectedOverride = override
                                showOverridePicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(override.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)

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

                                    if selectedOverride?.name == override.name {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Välj override")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Stäng") {
                            showOverridePicker = false
                        }
                    }
                }
            }
        }
        .alert(isPresented: $showAlert) {
            switch alertType {
            case .confirmCombo:
                let carbsAmount = carbs.doubleValue(for: HKUnit.gram())
                let proteinAmount = protein.doubleValue(for: HKUnit.gram())
                let fatAmount = fat.doubleValue(for: HKUnit.gram())
                let bolus = bolusAmount.doubleValue(for: .internationalUnit())
                let name = presetName

                var message = "Är du säker på att du vill skicka förvalet '\(name)'?\n"

                if carbsAmount > 0 {
                    message += String(format: "\nKolhydrater: %.0f g", carbsAmount)
                }

                if proteinAmount > 0 {
                    message += String(format: "\nProtein: %.0f g", proteinAmount)
                }

                if fatAmount > 0 {
                    message += String(format: "\nFett: %.0f g", fatAmount)
                }

                if bolus > 0 {
                    message += String(format: "\nBolus: %.2f E", bolus)
                }

                if let selectedOverride {
                    message += "\nOverride: \(selectedOverride.name)"
                }

                if !notes.isEmpty {
                    message += "\n\nAnteckning: \(notes)"
                }

                return Alert(
                    title: Text("Bekräfta förval"),
                    message: Text(message),
                    primaryButton: .default(Text("Bekräfta"), action: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if bolus > 0 {
                                authenticateUser { success in
                                    if success {
                                        sendComboCommand()
                                    }
                                }
                            } else {
                                sendComboCommand()
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
                        dismiss()
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

    private var navigationTitle: String {
        switch mode {
        case .createPreset:
            return "Nytt förval"
        case .editPreset:
            return "Redigera förval"
        case .sendFromPreset:
            return preset?.name ?? "Förval"
        }
    }

    private var defaultPrimaryButtonTitle: String {
        switch mode {
        case .createPreset:
            return "Spara förval"
        case .editPreset:
            return "Uppdatera förval"
        case .sendFromPreset:
            return "Skicka Förval"
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
        buttonGuardrailMessage ?? defaultPrimaryButtonTitle
    }

    private var progressText: String {
        switch mode {
        case .createPreset:
            return "Sparar förval..."
        case .editPreset:
            return "Uppdaterar förval..."
        case .sendFromPreset:
            return "Skickar förvalskommando..."
        }
    }

    private var isButtonDisabled: Bool {
        isLoading || buttonGuardrailMessage != nil
    }

    private func savePreset() {
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetToSave = ComboPreset(
            id: preset?.id ?? UUID(),
            name: trimmedName,
            carbs: carbs,
            protein: protein,
            fat: fat,
            bolusAmount: bolusAmount,
            notes: notes,
            overrideName: selectedOverride?.name
        )
        onSavePreset(presetToSave)
        dismiss()
    }

    private func sendComboCommand() {
        isLoading = true

        var scheduledDate: Date? = nil
        if isScheduling, let selectedTime = selectedTime {
            let calendar = Calendar.current
            let now = Date()
            let selectedDateComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
            let currentSecond = calendar.component(.second, from: now)

            scheduledDate = calendar.date(
                bySettingHour: selectedDateComponents.hour ?? 0,
                minute: selectedDateComponents.minute ?? 0,
                second: currentSecond,
                of: now
            ) ?? now
        }
        
        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Remote" : notes

        pushNotificationManager.sendComboPushNotification(
            carbs: carbs,
            protein: protein,
            fat: fat,
            bolusAmount: bolusAmount,
            notes: finalNotes,
            scheduledTime: scheduledDate,
            override: selectedOverride
        ) { success, errorMessage in
            DispatchQueue.main.async {
                isLoading = false

                if success {
                    statusMessage = "Förvalskommando lyckades"
                    alertType = .statusSuccess
                } else {
                    statusMessage = errorMessage ?? "Förvalskommando misslyckades!"
                    alertType = .statusFailure
                }

                showAlert = true
            }
        }
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

private struct ComboPreset: Identifiable, Equatable {
    let id: UUID
    var name: String
    var carbs: HKQuantity
    var protein: HKQuantity
    var fat: HKQuantity
    var bolusAmount: HKQuantity
    var notes: String
    var overrideName: String?

    init(
        id: UUID,
        name: String,
        carbs: HKQuantity,
        protein: HKQuantity,
        fat: HKQuantity,
        bolusAmount: HKQuantity,
        notes: String,
        overrideName: String?
    ) {
        self.id = id
        self.name = name
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.bolusAmount = bolusAmount
        self.notes = notes
        self.overrideName = overrideName
    }

    init(storageEntry: ComboPresetEntry) {
        self.id = storageEntry.id
        self.name = storageEntry.name
        self.carbs = HKQuantity(unit: .gram(), doubleValue: storageEntry.carbsGrams)
        self.protein = HKQuantity(unit: .gram(), doubleValue: storageEntry.proteinGrams)
        self.fat = HKQuantity(unit: .gram(), doubleValue: storageEntry.fatGrams)
        self.bolusAmount = HKQuantity(unit: .internationalUnit(), doubleValue: storageEntry.bolusUnits)
        self.notes = storageEntry.notes
        self.overrideName = storageEntry.overrideName
    }

    var storageEntry: ComboPresetEntry {
        ComboPresetEntry(
            id: id,
            name: name,
            carbsGrams: carbs.doubleValue(for: .gram()),
            proteinGrams: protein.doubleValue(for: .gram()),
            fatGrams: fat.doubleValue(for: .gram()),
            bolusUnits: bolusAmount.doubleValue(for: .internationalUnit()),
            notes: notes,
            overrideName: overrideName
        )
    }

    static func == (lhs: ComboPreset, rhs: ComboPreset) -> Bool {
        lhs.id == rhs.id
    }
}
