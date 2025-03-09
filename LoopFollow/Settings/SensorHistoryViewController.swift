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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle"),
            style: .plain,
            target: self,
            action: #selector(addManualSensorNote)
        )

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
