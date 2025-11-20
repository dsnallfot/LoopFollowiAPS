//
//  LogViewModel.swift
//  LoopFollow
//
//  Created by Jonas Björkert on 2025-01-13.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//

import Foundation
import Combine

class LogViewModel: ObservableObject {
    @Published var allLogEntries: [LogEntry] = []
    @Published var filteredLogEntries: [LogEntry] = []
    @Published var selectedCategory: LogManager.Category? = nil
    @Published var searchText: String = ""
    @Published var searchResultsIsHighlighted: Bool = false

    private enum DefaultsKeys {
        static let selectedCategory = "LogView_SelectedCategory"
        static let searchText = "LogView_SearchText"
        static let searchResultsIsHighlighted = "LogView_SearchResultsIsHighlighted"
    }

    private var cancellables = Set<AnyCancellable>()

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

        Publishers.CombineLatest3($selectedCategory, $searchText, $searchResultsIsHighlighted)
            .sink { [weak self] category, search, isHighlighted in
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

                self?.filterLogs(category: category, searchText: search, searchResultsIsHighlighted: isHighlighted)
            }
            .store(in: &cancellables)
        
        // Daniel: Test to subscribe to log updates from LogManager instead of using timer
                LogManager.shared.logUpdateSubject
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in
                        self?.loadLogEntries()
                    }
                    .store(in: &cancellables)

        loadLogEntries()
/*
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
                var logLines = logContent.components(separatedBy: .newlines)
                logLines = logLines.filter { !$0.isEmpty }

                // Reverse the log lines to have newest first
                logLines.reverse()

                let uniqueLogEntries = logLines.map { LogEntry(id: UUID(), text: $0) }

                DispatchQueue.main.async {
                    self.allLogEntries = uniqueLogEntries
                    self.filterLogs(category: self.selectedCategory, searchText: self.searchText, searchResultsIsHighlighted: self.searchResultsIsHighlighted)
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

    private func filterLogs(category: LogManager.Category?, searchText: String, searchResultsIsHighlighted: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var filtered = self.allLogEntries

            // Filter by category and remove category tag
            if let category = category {
                let categoryTag = "[\(category.rawValue)] "
                filtered = filtered.filter { $0.text.contains(categoryTag) }
                    .map { logEntry in
                        var text = logEntry.text
                        if let range = text.range(of: categoryTag) {
                            text.removeSubrange(range)
                        }
                        return LogEntry(id: logEntry.id, text: text.trimmingCharacters(in: .whitespaces))
                    }
            }

            // Filter by search text only when not in highlight mode
            if !searchText.isEmpty && !searchResultsIsHighlighted {
                filtered = filtered.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
            }

            DispatchQueue.main.async {
                self.filteredLogEntries = filtered
            }
        }
    }
}
