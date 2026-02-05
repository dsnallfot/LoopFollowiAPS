import UIKit
import AVFoundation

class SoundSelectionViewController: ThemedViewController, UITableViewDelegate, UITableViewDataSource {

    // MARK: - Public Properties
    var selectedSound: String?
    var onSelection: ((String) -> Void)?

    // MARK: - Data
    // Kopiera in hela din lista från originalfilen här.
    // Jag tar med ett urval för att visa principen.
    private let soundFiles: [String] = [
        "Alarm_Buzzer",
        "Alarm_Clock",
        "Alert_Tone_Busy",
        "Alert_Tone_Ringtone_1",
        "Alert_Tone_Ringtone_2",
        "Alien_Siren",
        "Ambulance",
        "Analog_Watch_Alarm",
        "Big_Clock_Ticking",
        "Burglar_Alarm_Siren_1",
        "Burglar_Alarm_Siren_2",
        "Cartoon_Ascend_Climb_Sneaky",
        "Cartoon_Ascend_Then_Descend",
        "Cartoon_Bounce_To_Ceiling",
        "Cartoon_Dreamy_Glissando_Harp",
        "Cartoon_Fail_Strings_Trumpet",
        "Cartoon_Machine_Clumsy_Loop",
        "Cartoon_Siren",
        "Cartoon_Tip_Toe_Sneaky_Walk",
        "Cartoon_Uh_Oh",
        "Cartoon_Villain_Horns",
        "Cell_Phone_Ring_Tone",
        "Chimes_Glassy",
        "Computer_Magic",
        "CSFX-2_Alarm",
        "Cuckoo_Clock",
        "Dhol_Shuffleloop",
        "Discreet",
        "Early_Sunrise",
        "Emergency_Alarm_Carbon_Monoxide",
        "Emergency_Alarm_Siren",
        "Emergency_Alarm",
        "Ending_Reached",
        "Fly",
        "Ghost_Hover",
        "Good_Morning",
        "Hell_Yeah_Somewhat_Calmer",
        "In_A_Hurry",
        "Indeed",
        "Insistently",
        "Jingle_All_The_Way",
        "Laser_Shoot",
        "Machine_Charge",
        "Magical_Twinkle",
        "Marching_Heavy_Footed_Fat_Elephants",
        "Marimba_Descend",
        "Marimba_Flutter_or_Shake",
        "Martian_Gun",
        "Martian_Scanner",
        "Metallic",
        "Nightguard",
        "Not_Kiddin",
        "Open_Your_Eyes_And_See",
        "Orchestral_Horns",
        "Oringz",
        "Pager_Beeps",
        "Remembers_Me_Of_Asia",
        "Rise_And_Shine",
        "Rush",
        "Sci-Fi_Air_Raid_Alarm",
        "Sci-Fi_Alarm_Loop_1",
        "Sci-Fi_Alarm_Loop_2",
        "Sci-Fi_Alarm_Loop_3",
        "Sci-Fi_Alarm_Loop_4",
        "Sci-Fi_Alarm",
        "Sci-Fi_Computer_Console_Alarm",
        "Sci-Fi_Console_Alarm",
        "Sci-Fi_Eerie_Alarm",
        "Sci-Fi_Engine_Shut_Down",
        "Sci-Fi_Incoming_Message_Alert",
        "Sci-Fi_Spaceship_Message",
        "Sci-Fi_Spaceship_Warm_Up",
        "Sci-Fi_Warning",
        "Signature_Corporate",
        "Siri_Alert_Calibration_Needed",
        "Siri_Alert_Device_Muted",
        "Siri_Alert_Glucose_Dropping_Fast",
        "Siri_Alert_Glucose_Rising_Fast",
        "Siri_Alert_High_Glucose",
        "Siri_Alert_Low_Glucose",
        "Siri_Alert_Missed_Readings",
        "Siri_Alert_Transmitter_Battery_Low",
        "Siri_Alert_Urgent_High_Glucose",
        "Siri_Alert_Urgent_Low_Glucose",
        "Siri_Calibration_Needed",
        "Siri_Device_Muted",
        "Siri_Glucose_Dropping_Fast",
        "Siri_Glucose_Rising_Fast",
        "Siri_High_Glucose",
        "Siri_Low_Glucose",
        "Siri_Missed_Readings",
        "Siri_Transmitter_Battery_Low",
        "Siri_Urgent_High_Glucose",
        "Siri_Urgent_Low_Glucose",
        "Soft_Marimba_Pad_Positive",
        "Soft_Warm_Airy_Optimistic",
        "Soft_Warm_Airy_Reassuring",
        "Store_Door_Chime",
        "Sunny",
        "Thunder_Sound_FX",
        "Time_Has_Come",
        "Tornado_Siren",
        "Two_Turtle_Doves",
        "Unpaved",
        "Wake_Up_Will_You",
        "Win_Gain",
        "Wrong_Answer",
        "Vibrate_Only" // Specialfall
    ]

    // MARK: - Private Properties
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Välj Larmljud" // Eller "Select Sound"
        //view.backgroundColor = .systemGroupedBackground
        updateBackgroundForCurrentMode()
        
        setupTableView()
        scrollToSelection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAudio() // Stoppa ljudet om användaren backar ut
    }

    // MARK: - Setup
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SoundCell")

        // Viktigt: låt gradienten från ThemedViewController synas igenom
        tableView.backgroundColor = .clear
        tableView.layer.backgroundColor = UIColor.clear.cgColor
    }

    private func scrollToSelection() {
        guard let current = selectedSound,
              let index = soundFiles.firstIndex(of: current) else { return }
        
        let indexPath = IndexPath(row: index, section: 0)
        // Vänta lite så layouten hinner sätta sig
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }

    // MARK: - TableView Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return soundFiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SoundCell", for: indexPath)
        let soundName = soundFiles[indexPath.row]
        
        // Snygga till namnet (ta bort underscores)
        cell.textLabel?.text = formatSoundName(soundName)
        
        // Hantera checkmark
        if soundName == selectedSound {
            cell.accessoryType = .checkmark
            cell.textLabel?.textColor = .systemBlue // Highlighta vald text
            cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        } else {
            cell.accessoryType = .none
            cell.textLabel?.textColor = .label
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        }
        
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
        cell.backgroundConfiguration = background
        
        return cell
    }

    // MARK: - TableView Delegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let newSound = soundFiles[indexPath.row]
        
        // Uppdatera state
        selectedSound = newSound
        
        // Informera parent controllern
        onSelection?(newSound)
        
        // Spela upp ljudet
        playPreview(for: newSound)
        
        // Ladda om tabellen för att flytta checkmark
        tableView.reloadData()
    }

    // MARK: - Audio Logic
    private func playPreview(for soundName: String) {
        // Stoppa eventuellt pågående ljud
        stopAudio()
        
        // Specialfall om du har "Tyst" eller "Vibrate Only"
        if soundName == "Vibrate_Only" {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }

        // Hitta filen i main bundle. Antar att filerna är .mp3 eller .caf etc.
        // Du kan behöva loopa extensions om du har blandade filtyper.
        let extensions = ["mp3", "caf", "wav", "m4a"]
        var url: URL?
        
        for ext in extensions {
            if let fileUrl = Bundle.main.url(forResource: soundName, withExtension: ext) {
                url = fileUrl
                break
            }
        }
        
        guard let soundUrl = url else {
            print("Kunde inte hitta ljudfil: \(soundName)")
            return
        }

        do {
            // Se till att ljudet spelas även om telefonen är i tyst läge (om du vill det för preview)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: soundUrl)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Kunde inte spela upp ljud: \(error)")
        }
    }
    
    private func stopAudio() {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
    }
    
    // MARK: - Helper
    private func formatSoundName(_ name: String) -> String {
        return name.replacingOccurrences(of: "_", with: " ")
    }
}
