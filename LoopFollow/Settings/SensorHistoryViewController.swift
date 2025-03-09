//
//  SensorHistoryViewController.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-03-09.
//  Copyright © 2025 Jon Fawcett. All rights reserved.
//
import UIKit

class SensorHistoryViewController: UITableViewController {
    
    private var sensorHistory: [SensorStartHistoryEntry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Sensorhistorik"
        setupNavigationBar()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SensorHistoryCell")
        loadSensorHistory()
    }
    
    // MARK: - Navigation Bar Setup
    
    private func setupNavigationBar() {
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle"),
            style: .plain,
            target: self,
            action: #selector(addManualSensorNote)
        )

        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), // Export/Share
            style: .plain,
            target: self,
            action: #selector(exportSensorHistory)
        )

        let importButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"), // Import
            style: .plain,
            target: self,
            action: #selector(importSensorHistory)
        )

        navigationItem.leftBarButtonItems = [addButton, shareButton, importButton]

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true, completion: nil)
    }

    private func loadSensorHistory() {
        sensorHistory = Storage.shared.sensorStartNotes
        sensorHistory.sort { $0.date > $1.date }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sensorHistory.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SensorHistoryCell", for: indexPath)
        let entry = sensorHistory[indexPath.row]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let formattedDate = dateFormatter.string(from: Date(timeIntervalSince1970: entry.date))

        cell.textLabel?.text = "\(formattedDate)\n\(entry.note)"
        cell.textLabel?.numberOfLines = 0
        return cell
    }

    // MARK: - Add Manual Sensor Note
    
    @objc private func addManualSensorNote() {
        let addNoteVC = AddManualSensorNoteViewController()
        addNoteVC.delegate = self
        let navController = UINavigationController(rootViewController: addNoteVC)
        present(navController, animated: true)
    }
    
    // MARK: - Export Sensor History
    
    @objc private func exportSensorHistory() {
        DispatchQueue.global(qos: .background).async {
            do {
                let jsonData = try JSONEncoder().encode(self.sensorHistory)
                
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("📤 Exporting JSON: \(jsonString)")
                }

                // ✅ Save in the Documents Directory instead of tmp
                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                let exportURL = documentsURL.appendingPathComponent("SensorHistory.json")

                try jsonData.write(to: exportURL, options: .atomic)

                DispatchQueue.main.async {
                    if fileManager.fileExists(atPath: exportURL.path) {
                        let activityVC = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
                        self.present(activityVC, animated: true)
                    } else {
                        print("❌ JSON file does not exist at \(exportURL.path)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Failed to export sensor history: \(error)")
                }
            }
        }
    }

    // MARK: - Import Sensor History
    
    @objc private func importSensorHistory() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
}

// MARK: - Handle New Manual Notes
extension SensorHistoryViewController: AddManualSensorNoteDelegate {
    func didAddManualSensorNote(note: SensorStartHistoryEntry) {
        var storedHistory = Storage.shared.sensorStartNotes
        storedHistory.append(note)
        Storage.shared.sensorStartNotes = storedHistory
        
        loadSensorHistory() // Reload table with updated data
    }
}

extension SensorHistoryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else { return }

        // ✅ Request access for iCloud Drive / Downloads
        if fileURL.startAccessingSecurityScopedResource() {
            defer { fileURL.stopAccessingSecurityScopedResource() } // Always clean up access

            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsURL.appendingPathComponent("ImportedSensorHistory.json")

            do {
                // ✅ Copy file into the app's Documents folder (bypassing permission issue)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL) // Ensure it's fresh
                }
                try fileManager.copyItem(at: fileURL, to: destinationURL)

                // ✅ Read from the local copy
                let jsonData = try Data(contentsOf: destinationURL)
                let importedHistory = try JSONDecoder().decode([SensorStartHistoryEntry].self, from: jsonData)

                DispatchQueue.main.async {
                    var storedHistory = Storage.shared.sensorStartNotes
                    for entry in importedHistory {
                        if !storedHistory.contains(where: { $0.date == entry.date && $0.note == entry.note }) {
                            storedHistory.append(entry)
                        }
                    }
                    
                    Storage.shared.sensorStartNotes = storedHistory
                    self.loadSensorHistory() // Reload UI
                    
                    print("✅ Successfully imported sensor history from local copy")
                }
            } catch {
                print("❌ Failed to copy or import sensor history: \(error)")
            }
        } else {
            print("❌ Failed to access security-scoped resource for file: \(fileURL)")
        }
    }
}
