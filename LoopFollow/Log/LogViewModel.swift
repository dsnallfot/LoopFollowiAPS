// LogViewModel.swift

import Foundation
import Combine

class LogViewModel: ObservableObject {
    @Published var allLogEntries: [LogEntry] = []
    @Published var filteredLogEntries: [LogEntry] = []
    @Published var selectedCategory: LogManager.Category? = nil
    @Published var searchText: String = ""
    @Published var searchResultsIsHighlighted: Bool = false

    // MARK: - Multi-search filters (split by '.')
    private var activeSearchFilters: [String] {
        searchText
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func matchesAnyFilter(_ line: String, filters: [String]) -> Bool {
        guard !filters.isEmpty else { return true }
        return filters.contains(where: { line.localizedCaseInsensitiveContains($0) })
    }

    private enum DefaultsKeys {
        static let selectedCategory = "LogView_SelectedCategory"
        static let searchText = "LogView_SearchText"
        static let searchResultsIsHighlighted = "LogView_SearchResultsIsHighlighted"
    }

    private var cancellables = Set<AnyCancellable>()

    /// Hårt tak för hur många loggrader vi visar (nyaste först).
    /// Du kan justera den här uppåt/nedåt om du vill.
    private let maxDisplayedLines = 5000

    init() {
        let defaults = UserDefaults.standard

        // Restore selected category from UserDefaults, if any
        if let rawCategory = defaults.string(forKey: DefaultsKeys.selectedCategory),
           let restoredCategory = LogManager.Category(rawValue: rawCategory) {
            selectedCategory = restoredCategory
        }

        // Restore search text
        if let restoredSearchText = defaults.string(forKey: DefaultsKeys.searchText) {
            searchText = restoredSearchText
        }

        // Restore highlight mode (defaults to false if key missing)
        searchResultsIsHighlighted = defaults.bool(forKey: DefaultsKeys.searchResultsIsHighlighted)

        // När kategori / söktext / highlight ändras → filtrera om och persistera
        Publishers.CombineLatest3($selectedCategory, $searchText, $searchResultsIsHighlighted)
            .sink { [weak self] category, search, isHighlighted in
                guard let self = self else { return }
                let defaults = UserDefaults.standard

                // Persist selected category (or clear if nil)
                if let category = category {
                    defaults.set(category.rawValue, forKey: DefaultsKeys.selectedCategory)
                } else {
                    defaults.removeObject(forKey: DefaultsKeys.selectedCategory)
                }

                // Persist search text (empty string is allowed)
                defaults.set(search, forKey: DefaultsKeys.searchText)

                // Persist highlight mode
                defaults.set(isHighlighted, forKey: DefaultsKeys.searchResultsIsHighlighted)

                self.filterLogs(category: category,
                                searchText: search,
                                searchResultsIsHighlighted: isHighlighted)
            }
            .store(in: &cancellables)

        // ⚡️ Throttle/debounce logguppdateringar så vi inte läser filen 50 ggr/sek
        LogManager.shared.logUpdateSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.loadLogEntries()
            }
            .store(in: &cancellables)

        // Initial inläsning
        loadLogEntries()
        /*
        // Gamla timer-lösningen (behövs inte längre):
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadLogEntries()
            }
            .store(in: &cancellables)
        */
    }

    func loadLogEntries() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let logManager = LogManager.shared
            let logFileURL = logManager.currentLogFileURL

            guard FileManager.default.fileExists(atPath: logFileURL.path) else {
                DispatchQueue.main.async {
                    self.allLogEntries = []
                    self.filteredLogEntries = []
                }
                return
            }

            do {
                let logContent = try String(contentsOf: logFileURL, encoding: .utf8)

                // Splitta upp i rader + behåll originalindex (0 = äldsta raden i filen)
                // så att vi kan använda indexet som stabilt ID.
                var enumeratedLines = logContent
                    .components(separatedBy: .newlines)
                    .enumerated()
                    .filter { !$0.element.isEmpty }   // släng tomma

                // Behåll bara de senaste maxDisplayedLines raderna (baserat på filens naturliga ordning)
                if enumeratedLines.count > maxDisplayedLines {
                    enumeratedLines = Array(enumeratedLines.suffix(maxDisplayedLines))
                }

                // Bygg LogEntry med stabila IDs = radindex i filen.
                // entriesForward = äldst → nyast, vi vänder sen till nyast → äldst.
                let entriesForward: [LogEntry] = enumeratedLines.map { (index, line) in
                    LogEntry(id: index, text: line)
                }

                let newestFirst = Array(entriesForward.reversed())

                DispatchQueue.main.async {
                    self.allLogEntries = newestFirst
                    // Kör om filtreringen med nuvarande inställningar
                    self.filterLogs(category: self.selectedCategory,
                                    searchText: self.searchText,
                                    searchResultsIsHighlighted: self.searchResultsIsHighlighted)
                }
            } catch {
                print("Error reading log file: \(error)")
                DispatchQueue.main.async {
                    self.allLogEntries = []
                    self.filteredLogEntries = []
                }
            }
        }
    }

    private func filterLogs(category: LogManager.Category?,
                            searchText: String,
                            searchResultsIsHighlighted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var filtered = self.allLogEntries

            // Filter by category and remove category tag
            if let category = category {
                let categoryTag = "[\(category.rawValue)] "
                filtered = filtered
                    .filter { $0.text.contains(categoryTag) }
                    .map { logEntry in
                        var text = logEntry.text
                        if let range = text.range(of: categoryTag) {
                            text.removeSubrange(range)
                        }
                        return LogEntry(id: logEntry.id,
                                        text: text.trimmingCharacters(in: .whitespaces))
                    }
            }

            // Filter by search text only when not in highlight mode.
            // Supports up to N filters separated by '.' and matches ANY of them.
            if !searchResultsIsHighlighted {
                let filters = searchText
                    .split(separator: ".", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if !filters.isEmpty {
                    filtered = filtered.filter { self.matchesAnyFilter($0.text, filters: filters) }
                }
            }

            // (Valfri extra-säkerhet: om du vill ha annat max-tak efter filtrering)
            // let limited = filtered.prefix(self.maxDisplayedLines)

            DispatchQueue.main.async {
                self.filteredLogEntries = filtered
            }
        }
    }
}
