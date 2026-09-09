import SwiftUI
import HealthKit
import LocalAuthentication

@available(iOS 16.0, *)
struct ManualGlucoseView: View {
    @Environment(\.presentationMode) private var presentationMode

    @State private var manualGlucose = HKQuantity(
        unit: HKUnit(from: "mmol/L"),
        doubleValue: 0.0
    )

    private let pushNotificationManager = PushNotificationManager()

    @FocusState private var manualGlucoseFieldIsFocused: Bool

    @State private var showAlert = false
    @State private var alertType: AlertType? = nil
    @State private var alertMessage: String? = nil
    @State private var isLoading = false
    @State private var scheduledDate = Date()
    @State private var statusMessage: String? = nil

    enum AlertType {
        case confirmManualGlucose
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
                            label: "Blodsocker",
                            quantity: $manualGlucose,
                            unit: HKUnit(from: "mmol/L"),
                            maxLength: 4,
                            minValue: HKQuantity(
                                unit: HKUnit(from: "mmol/L"),
                                doubleValue: 0.1
                            ),
                            maxValue: HKQuantity(
                                unit: HKUnit(from: "mmol/L"),
                                doubleValue: 50.0
                            ),
                            isFocused: $manualGlucoseFieldIsFocused,
                            onValidationError: { _ in }
                        )

                        DatePicker(
                            "Tid",
                            selection: $scheduledDate,
                            in: availableTimeRange,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "sv_SE"))
                    }
                    .listRowBackground(Color(.systemGray).opacity(0.15))

                    LoadingButtonView(
                        buttonText: primaryButtonTitle,
                        progressText: "Skickar blodsocker...",
                        isLoading: isLoading,
                        action: {
                            manualGlucoseFieldIsFocused = false

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if manualGlucose.doubleValue(
                                    for: HKUnit(from: "mmol/L")
                                ) > 0.0 {
                                    alertType = .confirmManualGlucose
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
            }
        }
        .navigationTitle("Blodsocker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scheduledDate = Date()
            manualGlucoseFieldIsFocused = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                manualGlucoseFieldIsFocused = true
            }
        }
        .alert(isPresented: $showAlert) {
            switch alertType {
            case .confirmManualGlucose:
                return Alert(
                    title: Text("Bekräfta blodsocker"),
                    message: Text(
                        "Är du säker på att du vill skicka \(manualGlucose.doubleValue(for: HKUnit(from: "mmol/L")), specifier: "%.1f") mmol/L kl. \(formattedScheduledTime)?"
                    ),
                    primaryButton: .default(Text("Bekräfta"), action: {
                        sendManualGlucose()
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

    private var primaryButtonTitle: String {
        "Skicka blodsocker"
    }

    private var availableTimeRange: ClosedRange<Date> {
        let now = Date()
        return Calendar.current.startOfDay(for: now)...now
    }

    private var formattedScheduledTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: scheduledDate)
    }

    private var isButtonDisabled: Bool {
        isLoading ||
        manualGlucose.doubleValue(
            for: HKUnit(from: "mmol/L")
        ) <= 0
    }

    private func sendManualGlucose() {
        guard !isLoading else { return }

        isLoading = true

        pushNotificationManager.sendManualGlucosePushNotification(
            glucose: manualGlucose,
            scheduledTime: scheduledDate
        ) { success, errorMessage in

            DispatchQueue.main.async {
                isLoading = false

                if success {
                    statusMessage = "Blodsockerkommando lyckades."

                    manualGlucose = HKQuantity(
                        unit: HKUnit(from: "mmol/L"),
                        doubleValue: 0.0
                    )

                    alertType = .statusSuccess
                } else {
                    statusMessage =
                        errorMessage ?? "Blodsockerkommando misslyckades!"

                    alertType = .statusFailure
                }

                showAlert = true
            }
        }
    }
}
