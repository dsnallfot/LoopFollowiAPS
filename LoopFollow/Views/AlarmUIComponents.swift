import UIKit

// MARK: - Enums för strukturen
enum AlarmSection: Hashable {
    case categorySelection
    case globalSettings // Snooze all, mute all
    case specificAlarm(String) // T.ex. "Low Alert", "High Alert"
    case nightSettings
}

enum AlarmRow: Hashable {
    // Navigation/Kategorier
    case segmentControl
    
    // Generella inställningar
    case snoozeAll(Date?)
    case muteAll(Date?)
    
    // Specifika Larm-rader (Generisk wrapper för att slippa göra en case för varje larm)
    case toggle(title: String, isOn: Bool, id: String)
    case valueStepper(title: String, value: Double, min: Double, max: Double, step: Double, unit: String?, id: String)
    case soundPicker(title: String, currentSound: String, id: String)
    case optionPicker(title: String, currentOption: String, options: [String], id: String)
    case timePicker(title: String, date: Date?, id: String)
    case dateValue(title: String, date: Date?, id: String)
}

// MARK: - Återanvändbara Celler

// 1. Switch Cell
class SettingSwitchCell: UITableViewCell {
    static let reuseIdentifier = "SettingSwitchCell"
    private let switchControl = UISwitch()
    var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
    
        // 🔹 Halvtransparent grå bakgrund (som i andra vyer)
                let bgColor = UIColor.clear
                backgroundColor = bgColor
                contentView.backgroundColor = bgColor

        
        contentView.addSubview(switchControl)
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            switchControl.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            switchControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        switchControl.addTarget(self, action: #selector(didToggle), for: .valueChanged)
    }
    
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        textLabel?.text = title
        switchControl.isOn = isOn
        self.onToggle = onToggle
    }

    @objc private func didToggle() {
        onToggle?(switchControl.isOn)
    }
}

// 2. Stepper Cell (Moderniserad)
class SettingStepperCell: UITableViewCell {
    static let reuseIdentifier = "SettingStepperCell"
    private let stepper = UIStepper()
    private let valueLabel = UILabel()
    var onValueChanged: ((Double) -> Void)?
    
    private var currentUnit: String?
    private var currentTitle: String = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
        
        // 🔹 Samma halvtransparenta grå bakgrund
                let bgColor = UIColor.clear
                backgroundColor = bgColor
                contentView.backgroundColor = bgColor
        
    }
    
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        let stack = UIStackView(arrangedSubviews: [valueLabel, stepper])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.centerXAnchor)
        ])
        
        valueLabel.textColor = .secondaryLabel
        valueLabel.font = .preferredFont(forTextStyle: .body)
        stepper.addTarget(self, action: #selector(stepperDidChange), for: .valueChanged)
    }

    func configure(title: String, value: Double, min: Double, max: Double, step: Double, unit: String?, onValueChanged: @escaping (Double) -> Void) {
            textLabel?.text = title
            self.currentTitle = title
            self.currentUnit = unit
            
            stepper.minimumValue = min
            stepper.maximumValue = max
            stepper.stepValue = step
            stepper.value = value
            
            updateLabelText(for: value)
            self.onValueChanged = onValueChanged
        }

    @objc private func stepperDidChange() {
            updateLabelText(for: stepper.value)
            onValueChanged?(stepper.value)
        }
    
    // Ny hjälpfunktion som sköter all visning
        private func updateLabelText(for value: Double) {
            let unit = currentUnit ?? ""
            
            if currentTitle.contains("Glukos") || currentTitle.contains("delta") {
                // Omräkning för mmol/L
                let mmolValue = value / 18.0182
                valueLabel.text = String(format: "%.1f%@", mmolValue, unit)
            } else if unit == "%" || currentTitle.contains("Volume") {
                // Fix för decimalfelet (0.8999...) och visning av %
                let percentage = Int((value).rounded())
                valueLabel.text = "\(percentage)%"
            } else {
                // Standardvisning för minuter etc (heltal)
                valueLabel.text = "\(Int(value.rounded()))\(unit)"
            }
        }
}

// 3. Segment Cell (För toppmenyn)
class SegmentSelectionCell: UITableViewCell {
    static let reuseIdentifier = "SegmentSelectionCell"
    let segmentedControl = UISegmentedControl()
    var onSegmentChanged: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(segmentedControl)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        // Layout constraints...
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            segmentedControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
        segmentedControl.addTarget(self, action: #selector(changed), for: .valueChanged)
        selectionStyle = .none
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    
    @objc func changed() {
        onSegmentChanged?(segmentedControl.selectedSegmentIndex)
    }
}
