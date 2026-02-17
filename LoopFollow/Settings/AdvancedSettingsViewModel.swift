//
//  AdvancedSettingsViewModel.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-23.

//

import Foundation

class AdvancedSettingsViewModel: ObservableObject {
    @Published var downloadTreatments: Bool {
        didSet {
            UserDefaultsRepository.downloadTreatments.value = downloadTreatments
        }
    }
    @Published var downloadPrediction: Bool {
        didSet {
            UserDefaultsRepository.downloadPrediction.value = downloadPrediction
        }
    }
    @Published var graphBasal: Bool {
        didSet {
            UserDefaultsRepository.graphBasal.value = graphBasal
        }
    }
    @Published var graphBolus: Bool {
        didSet {
            UserDefaultsRepository.graphBolus.value = graphBolus
        }
    }
    @Published var graphCarbs: Bool {
        didSet {
            UserDefaultsRepository.graphCarbs.value = graphCarbs
        }
    }
    @Published var graphOtherTreatments: Bool {
        didSet {
            UserDefaultsRepository.graphOtherTreatments.value = graphOtherTreatments
        }
    }
    @Published var bgUpdateDelay: Int {
        didSet {
            UserDefaultsRepository.bgUpdateDelay.value = bgUpdateDelay
        }
    }
    @Published var debugLogLevel: Bool {
        didSet {
            Storage.shared.debugLogLevel.value = debugLogLevel
        }
    }
    @Published var tempDebugLogLevel: Bool {
        didSet {
            Storage.shared.tempDebugLogLevel.value = tempDebugLogLevel
        }
    }
    @Published var uploadAppStartNote: Bool {
        didSet {
            Storage.shared.uploadAppStartNote.value = uploadAppStartNote
        }
    }
    @Published var lastArchiveDebugMessage: String = ""
    @Published var lastArchiveExportMessage: String = ""
    @Published var archiveShareURL: URL? = nil
    @Published var isPresentingArchiveShareSheet: Bool = false
    
    init() {
        self.downloadTreatments = UserDefaultsRepository.downloadTreatments.value
        self.downloadPrediction = UserDefaultsRepository.downloadPrediction.value
        self.graphBasal = UserDefaultsRepository.graphBasal.value
        self.graphBolus = UserDefaultsRepository.graphBolus.value
        self.graphCarbs = UserDefaultsRepository.graphCarbs.value
        self.graphOtherTreatments = UserDefaultsRepository.graphOtherTreatments.value
        self.bgUpdateDelay = UserDefaultsRepository.bgUpdateDelay.value
        self.debugLogLevel = Storage.shared.debugLogLevel.value
        self.tempDebugLogLevel = Storage.shared.tempDebugLogLevel.value
        self.uploadAppStartNote = Storage.shared.uploadAppStartNote.value
    }

    /// Manually triggers archiving of the previous month’s cached data.
    @MainActor
    func archivePreviousMonth() {
        // Bevis direkt
        print("✅ AdvancedSettings - manual archive button tapped")
        LogManager.shared.log(category: .taskScheduler, message: "AdvancedSettings - manual archive button tapped")

        lastArchiveDebugMessage = "Startar arkivering…"

        Task {
            await ArchiveManager.archivePreviousMonthIfNeeded()
            await MainActor.run {
                self.lastArchiveDebugMessage = "Arkivering klar (eller redan gjord)."
            }
        }
    }
    
    /// Creates a ZIP of the entire Arkiv folder and opens the share sheet so the user can save to Files/iCloud.
    @MainActor
    func exportArchiveZipAndShare() {
        print("✅ AdvancedSettings - export archive zip tapped")
        LogManager.shared.log(category: .taskScheduler, message: "AdvancedSettings - export archive zip tapped")

        lastArchiveExportMessage = "Skapar zip…"

        Task {
            do {
                let url = try await ArchiveManager.createArchiveZipSnapshot()
                await MainActor.run {
                    self.archiveShareURL = url
                    self.isPresentingArchiveShareSheet = true
                    self.lastArchiveExportMessage = "Zip skapad. Välj var du vill spara den…"
                }
            } catch {
                await MainActor.run {
                    self.lastArchiveExportMessage = "Misslyckades skapa zip: \(error.localizedDescription)"
                }
            }
        }
    }
}
