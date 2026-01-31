//
//  AddManualSensorNoteView.swift
//  LoopFollow
//
//  Created by Daniel Snällfot on 2025-03-09.

//

import UIKit

protocol AddManualSensorNoteDelegate: AnyObject {
    func didAddManualSensorNote(note: SensorStartHistoryEntry)
    func didUpdateManualSensorNote(note: SensorStartHistoryEntry, at index: Int)
}

class AddManualSensorNoteViewController: ThemedViewController {
    
    weak var delegate: AddManualSensorNoteDelegate?
    private var editingIndex: Int?
    private var editingOriginal: SensorStartHistoryEntry?

    func configureForEditing(entry: SensorStartHistoryEntry, index: Int) {
        editingIndex = index
        editingOriginal = entry
        if isViewLoaded {
            datePicker.date = Date(timeIntervalSince1970: entry.date)
            notesTextField.text = entry.note
            self.title = "Redigera sensor"
            navigationItem.rightBarButtonItem?.title = "Uppdatera"
        }
    }
    
    private let datePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = Date()
        picker.locale = Locale(identifier: "sv_SE")
        return picker
    }()
    
    private let notesTextField: UITextField = {
        let textField = UITextField()
        textField.borderStyle = .roundedRect
        textField.backgroundColor = .systemGray.withAlphaComponent(0.1)
        textField.placeholder = "Sensorregistrering"
        return textField
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Registrera sensor"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()
        setupUI()
        setupNavigationBar()
        if let existing = editingOriginal {
            datePicker.date = Date(timeIntervalSince1970: existing.date)
            notesTextField.text = existing.note
            self.title = "Redigera sensor"
            navigationItem.rightBarButtonItem?.title = "Uppdatera"
        }
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Avbryt",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Spara",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func saveTapped() {
        guard let noteText = notesTextField.text, !noteText.isEmpty else { return }

        let updatedEntry = SensorStartHistoryEntry(
            date: datePicker.date.timeIntervalSince1970,
            note: noteText
        )

        if let idx = editingIndex {
            delegate?.didUpdateManualSensorNote(note: updatedEntry, at: idx)
        } else {
            delegate?.didAddManualSensorNote(note: updatedEntry)
        }
        dismiss(animated: true)
    }
    
    private func setupUI() {
        view.addSubview(datePicker)
        view.addSubview(notesTextField)
        
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        notesTextField.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            datePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            datePicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            
            notesTextField.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 20),
            notesTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            notesTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            notesTextField.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
}
