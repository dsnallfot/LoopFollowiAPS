import UIKit

protocol AddManualPumpDelegate: AnyObject {
    func didAddManualPumpChange(entry: PumpChangeHistoryEntry)
    func didUpdateManualPumpChange(entry: PumpChangeHistoryEntry, at index: Int)
}

class AddManualPumpViewController: ThemedViewController {

    weak var delegate: AddManualPumpDelegate?
    private var editingIndex: Int?
    private var editingOriginal: PumpChangeHistoryEntry?

    func configureForEditing(entry: PumpChangeHistoryEntry, index: Int) {
        editingIndex = index
        editingOriginal = entry
        if isViewLoaded {
            datePicker.date = Date(timeIntervalSince1970: entry.date)
            self.title = "Redigera pumpbyte"
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

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Registrera pumpbyte"
        //view.backgroundColor = .systemBackground
        updateBackgroundForCurrentMode()
        setupUI()
        setupNavigationBar()

        if let existing = editingOriginal {
            datePicker.date = Date(timeIntervalSince1970: existing.date)
            self.title = "Redigera pumpbyte"
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
        let entry = PumpChangeHistoryEntry(
            date: datePicker.date.timeIntervalSince1970
        )

        if let idx = editingIndex {
            delegate?.didUpdateManualPumpChange(entry: entry, at: idx)
        } else {
            delegate?.didAddManualPumpChange(entry: entry)
        }
        dismiss(animated: true)
    }

    private func setupUI() {
        view.addSubview(datePicker)
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            datePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            datePicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }
}
