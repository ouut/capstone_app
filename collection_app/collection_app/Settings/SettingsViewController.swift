import UIKit
import UniformTypeIdentifiers
import Combine

final class SettingsViewController: UIViewController, UITextFieldDelegate {

    // Recording tab
    private let subjectIDField = UITextField()
    private let sessionNoteField = UITextField()
    private let saveCSVToggle = UISwitch()
    private let saveVideoToggle = UISwitch()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let udpToggle = UISwitch()
    private let hostError = UILabel()
    private let portError = UILabel()

    // UDP Video
    private let videoHostField = UITextField()
    private let videoPortField = UITextField()
    private let udpVideoToggle = UISwitch()
    private let videoHostError = UILabel()
    private let videoPortError = UILabel()

    // WebSocket tab
    private let wsURLField = UITextField()
    private let wsToggle = UISwitch()
    private let wsVideoToggle = UISwitch()
    private let wsURLError = UILabel()
    private let wsVideoRow = UIStackView()
    private let wsLogView = UITextView()

    private var wsLogLines: [String] = []
    private let maxLogLines = 50

    var recordingManager: RecordingManager?
    private var cancellables = Set<AnyCancellable>()

    private let defaults = UserDefaults.standard
    private let kSubjectID = "subject_id"
    private let kSessionNote = "session_note"
    private let kSaveCSV = "recording_save_csv"
    private let kSaveVideo = "recording_save_video"
    private let kHost = "udp_host"
    private let kPort = "udp_port"
    private let kUDP = "udp_enabled"
    private let kVideoHost = "udp_video_host"
    private let kVideoPort = "udp_video_port"
    private let kVideoEnabled = "udp_video_enabled"
    private let kWSURL = "ws_url"
    private let kWSEnabled = "ws_enabled"
    private let kWSVideo = "ws_video_enabled"

    // Tab containers
    private let recordingStack = UIStackView()
    private let wsStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        setupUI()
        loadSettings()
        observeWS()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func setupUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let rootStack = UIStackView()
        rootStack.axis = .vertical
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rootStack)

        // ── Segmented control ──
        let seg = UISegmentedControl(items: ["Recording", "WebSocket"])
        seg.selectedSegmentIndex = 0
        seg.addTarget(self, action: #selector(tabChanged(_:)), for: .valueChanged)
        rootStack.addArrangedSubview(seg)

        // ── Recording tab content ──
        recordingStack.axis = .vertical
        recordingStack.spacing = 24
        buildRecordingTab()
        rootStack.addArrangedSubview(recordingStack)

        // ── WebSocket tab content ──
        wsStack.axis = .vertical
        wsStack.spacing = 24
        wsStack.isHidden = true
        buildWebSocketTab()
        rootStack.addArrangedSubview(wsStack)

        // Layout
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            rootStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -16),
            rootStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            rootStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])
    }

    @objc private func tabChanged(_ seg: UISegmentedControl) {
        recordingStack.isHidden = seg.selectedSegmentIndex != 0
        wsStack.isHidden = seg.selectedSegmentIndex != 1
    }

    // MARK: - Recording tab

    private func buildRecordingTab() {
        // ── Recording Config ──
        recordingStack.addArrangedSubview(sectionHeader("RECORDING CONFIG"))

        let card1 = cardView()
        let card1Stack = UIStackView()
        card1Stack.axis = .vertical
        card1Stack.spacing = 0
        card1Stack.translatesAutoresizingMaskIntoConstraints = false
        card1.addSubview(card1Stack)

        subjectIDField.borderStyle = .none
        subjectIDField.font = .systemFont(ofSize: 16)
        subjectIDField.textAlignment = .right
        subjectIDField.textColor = .secondaryLabel
        subjectIDField.placeholder = "P001"
        subjectIDField.delegate = self
        subjectIDField.addTarget(self, action: #selector(subjectIDChanged), for: .editingChanged)
        card1Stack.addArrangedSubview(labeledRow("Subject ID", subjectIDField))

        card1Stack.addArrangedSubview(divider())

        sessionNoteField.borderStyle = .none
        sessionNoteField.font = .systemFont(ofSize: 16)
        sessionNoteField.textAlignment = .right
        sessionNoteField.textColor = .secondaryLabel
        sessionNoteField.placeholder = "walking"
        sessionNoteField.delegate = self
        sessionNoteField.addTarget(self, action: #selector(sessionNoteChanged), for: .editingChanged)
        card1Stack.addArrangedSubview(labeledRow("Session Note", sessionNoteField))

        card1Stack.addArrangedSubview(divider())

        saveCSVToggle.isOn = true
        saveCSVToggle.addTarget(self, action: #selector(saveCSVToggled), for: .valueChanged)
        card1Stack.addArrangedSubview(toggleRow("Save CSV file", saveCSVToggle))

        card1Stack.addArrangedSubview(divider())

        let videoRow = UIStackView()
        videoRow.axis = .horizontal
        videoRow.spacing = 8
        videoRow.alignment = .center
        videoRow.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        videoRow.isLayoutMarginsRelativeArrangement = true
        let videoLabel = UILabel()
        videoLabel.text = "Save video file"
        videoLabel.font = .systemFont(ofSize: 16)
        videoRow.addArrangedSubview(videoLabel)
        let hint = UILabel()
        hint.text = "(default: off)"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .tertiaryLabel
        videoRow.addArrangedSubview(hint)
        videoRow.addArrangedSubview(UIView())
        saveVideoToggle.addTarget(self, action: #selector(saveVideoToggled), for: .valueChanged)
        videoRow.addArrangedSubview(saveVideoToggle)
        card1Stack.addArrangedSubview(videoRow)

        NSLayoutConstraint.activate([
            card1Stack.topAnchor.constraint(equalTo: card1.topAnchor, constant: 4),
            card1Stack.bottomAnchor.constraint(equalTo: card1.bottomAnchor, constant: -4),
            card1Stack.leadingAnchor.constraint(equalTo: card1.leadingAnchor, constant: 16),
            card1Stack.trailingAnchor.constraint(equalTo: card1.trailingAnchor, constant: -16)
        ])
        recordingStack.addArrangedSubview(card1)

        // ── UDP Streaming ──
        recordingStack.addArrangedSubview(sectionHeader("UDP STREAMING"))

        let card2 = cardView()
        let card2Stack = UIStackView()
        card2Stack.axis = .vertical
        card2Stack.spacing = 0
        card2Stack.translatesAutoresizingMaskIntoConstraints = false
        card2.addSubview(card2Stack)

        hostField.borderStyle = .none
        hostField.font = .systemFont(ofSize: 16)
        hostField.textAlignment = .right
        hostField.textColor = .secondaryLabel
        hostField.placeholder = "100.99.98.5"
        hostField.keyboardType = .URL
        hostField.autocapitalizationType = .none
        hostField.autocorrectionType = .no
        hostField.addTarget(self, action: #selector(hostChanged), for: .editingChanged)
        hostField.addTarget(self, action: #selector(hostEditingDidEnd), for: .editingDidEnd)
        card2Stack.addArrangedSubview(labeledRow("IP / Hostname", hostField))

        hostError.font = .systemFont(ofSize: 11)
        hostError.textColor = .systemRed
        hostError.isHidden = true
        card2Stack.addArrangedSubview(hostError)

        card2Stack.addArrangedSubview(divider())

        portField.borderStyle = .none
        portField.font = .systemFont(ofSize: 16)
        portField.textAlignment = .right
        portField.textColor = .secondaryLabel
        portField.placeholder = "9999"
        portField.keyboardType = .numberPad
        portField.addTarget(self, action: #selector(portChanged), for: .editingChanged)
        portField.addTarget(self, action: #selector(portEditingDidEnd), for: .editingDidEnd)
        card2Stack.addArrangedSubview(labeledRow("Port", portField))

        portError.font = .systemFont(ofSize: 11)
        portError.textColor = .systemRed
        portError.isHidden = true
        card2Stack.addArrangedSubview(portError)

        card2Stack.addArrangedSubview(divider())

        let udpRow = UIStackView()
        udpRow.axis = .horizontal
        udpRow.spacing = 8
        udpRow.alignment = .center
        udpRow.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        udpRow.isLayoutMarginsRelativeArrangement = true
        let udpLabel = UILabel()
        udpLabel.text = "Send via UDP"
        udpLabel.font = .systemFont(ofSize: 16)
        udpRow.addArrangedSubview(udpLabel)
        let udpHint = UILabel()
        udpHint.text = "(default: off)"
        udpHint.font = .systemFont(ofSize: 13)
        udpHint.textColor = .tertiaryLabel
        udpRow.addArrangedSubview(udpHint)
        udpRow.addArrangedSubview(UIView())
        udpToggle.addTarget(self, action: #selector(udpToggled), for: .valueChanged)
        udpRow.addArrangedSubview(udpToggle)
        card2Stack.addArrangedSubview(udpRow)

        NSLayoutConstraint.activate([
            card2Stack.topAnchor.constraint(equalTo: card2.topAnchor, constant: 4),
            card2Stack.bottomAnchor.constraint(equalTo: card2.bottomAnchor, constant: -4),
            card2Stack.leadingAnchor.constraint(equalTo: card2.leadingAnchor, constant: 16),
            card2Stack.trailingAnchor.constraint(equalTo: card2.trailingAnchor, constant: -16)
        ])
        recordingStack.addArrangedSubview(card2)

        // ── UDP Video ──
        recordingStack.addArrangedSubview(sectionHeader("UDP VIDEO (20 FPS JPEG)"))

        let card4 = cardView()
        let card4Stack = UIStackView()
        card4Stack.axis = .vertical
        card4Stack.spacing = 0
        card4Stack.translatesAutoresizingMaskIntoConstraints = false
        card4.addSubview(card4Stack)

        videoHostField.borderStyle = .none
        videoHostField.font = .systemFont(ofSize: 16)
        videoHostField.textAlignment = .right
        videoHostField.textColor = .secondaryLabel
        videoHostField.placeholder = "100.99.98.5"
        videoHostField.keyboardType = .URL
        videoHostField.autocapitalizationType = .none
        videoHostField.autocorrectionType = .no
        videoHostField.addTarget(self, action: #selector(videoHostChanged), for: .editingChanged)
        videoHostField.addTarget(self, action: #selector(videoHostEditingDidEnd), for: .editingDidEnd)
        card4Stack.addArrangedSubview(labeledRow("IP / Hostname", videoHostField))

        videoHostError.font = .systemFont(ofSize: 11)
        videoHostError.textColor = .systemRed
        videoHostError.isHidden = true
        card4Stack.addArrangedSubview(videoHostError)

        card4Stack.addArrangedSubview(divider())

        videoPortField.borderStyle = .none
        videoPortField.font = .systemFont(ofSize: 16)
        videoPortField.textAlignment = .right
        videoPortField.textColor = .secondaryLabel
        videoPortField.placeholder = "9998"
        videoPortField.keyboardType = .numberPad
        videoPortField.addTarget(self, action: #selector(videoPortChanged), for: .editingChanged)
        videoPortField.addTarget(self, action: #selector(videoPortEditingDidEnd), for: .editingDidEnd)
        card4Stack.addArrangedSubview(labeledRow("Port", videoPortField))

        videoPortError.font = .systemFont(ofSize: 11)
        videoPortError.textColor = .systemRed
        videoPortError.isHidden = true
        card4Stack.addArrangedSubview(videoPortError)

        card4Stack.addArrangedSubview(divider())

        let videoUDPRow = UIStackView()
        videoUDPRow.axis = .horizontal
        videoUDPRow.spacing = 8
        videoUDPRow.alignment = .center
        videoUDPRow.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        videoUDPRow.isLayoutMarginsRelativeArrangement = true
        let videoUDPLabel = UILabel()
        videoUDPLabel.text = "Send video via UDP"
        videoUDPLabel.font = .systemFont(ofSize: 16)
        videoUDPRow.addArrangedSubview(videoUDPLabel)
        let videoUDPHint = UILabel()
        videoUDPHint.text = "(default: off)"
        videoUDPHint.font = .systemFont(ofSize: 13)
        videoUDPHint.textColor = .tertiaryLabel
        videoUDPRow.addArrangedSubview(videoUDPHint)
        videoUDPRow.addArrangedSubview(UIView())
        udpVideoToggle.addTarget(self, action: #selector(udpVideoToggled), for: .valueChanged)
        videoUDPRow.addArrangedSubview(udpVideoToggle)
        card4Stack.addArrangedSubview(videoUDPRow)

        NSLayoutConstraint.activate([
            card4Stack.topAnchor.constraint(equalTo: card4.topAnchor, constant: 4),
            card4Stack.bottomAnchor.constraint(equalTo: card4.bottomAnchor, constant: -4),
            card4Stack.leadingAnchor.constraint(equalTo: card4.leadingAnchor, constant: 16),
            card4Stack.trailingAnchor.constraint(equalTo: card4.trailingAnchor, constant: -16)
        ])
        recordingStack.addArrangedSubview(card4)

        // ── Browse Files ──
        recordingStack.addArrangedSubview(sectionHeader("RECORDED FILES"))

        let browseBtn = UIButton(type: .system)
        browseBtn.setTitle("Browse Recordings\u{2026}", for: .normal)
        browseBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        browseBtn.backgroundColor = .systemBlue
        browseBtn.setTitleColor(.white, for: .normal)
        browseBtn.layer.cornerRadius = 10
        browseBtn.layer.cornerCurve = .continuous
        browseBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        browseBtn.addTarget(self, action: #selector(browseFiles), for: .touchUpInside)
        recordingStack.addArrangedSubview(browseBtn)
    }

    // MARK: - WebSocket tab

    private func buildWebSocketTab() {
        // ── WebSocket Config ──
        wsStack.addArrangedSubview(sectionHeader("CONNECTION"))

        let card3 = cardView()
        let card3Stack = UIStackView()
        card3Stack.axis = .vertical
        card3Stack.spacing = 0
        card3Stack.translatesAutoresizingMaskIntoConstraints = false
        card3.addSubview(card3Stack)

        wsURLField.borderStyle = .none
        wsURLField.font = .systemFont(ofSize: 16)
        wsURLField.textAlignment = .right
        wsURLField.textColor = .secondaryLabel
        wsURLField.placeholder = "ws://192.168.1.5:8080"
        wsURLField.keyboardType = .URL
        wsURLField.autocapitalizationType = .none
        wsURLField.autocorrectionType = .no
        wsURLField.addTarget(self, action: #selector(wsURLChanged), for: .editingChanged)
        wsURLField.addTarget(self, action: #selector(wsURLEditingDidEnd), for: .editingDidEnd)
        card3Stack.addArrangedSubview(labeledRow("Server URL", wsURLField))

        wsURLError.font = .systemFont(ofSize: 11)
        wsURLError.textColor = .systemRed
        wsURLError.isHidden = true
        card3Stack.addArrangedSubview(wsURLError)

        card3Stack.addArrangedSubview(divider())

        wsToggle.addTarget(self, action: #selector(wsToggled), for: .valueChanged)
        card3Stack.addArrangedSubview(toggleRow("Enable WebSocket", wsToggle))

        card3Stack.addArrangedSubview(divider())

        let wsVideoLabel = UILabel()
        wsVideoLabel.text = "Stream video"
        wsVideoLabel.font = .systemFont(ofSize: 16)
        let wsVideoHint = UILabel()
        wsVideoHint.text = "(20 fps JPEG)"
        wsVideoHint.font = .systemFont(ofSize: 13)
        wsVideoHint.textColor = .tertiaryLabel
        wsVideoRow.axis = .horizontal
        wsVideoRow.spacing = 8
        wsVideoRow.alignment = .center
        wsVideoRow.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        wsVideoRow.isLayoutMarginsRelativeArrangement = true
        wsVideoRow.addArrangedSubview(wsVideoLabel)
        wsVideoRow.addArrangedSubview(wsVideoHint)
        wsVideoRow.addArrangedSubview(UIView())
        wsVideoToggle.addTarget(self, action: #selector(wsVideoToggled), for: .valueChanged)
        wsVideoRow.addArrangedSubview(wsVideoToggle)
        card3Stack.addArrangedSubview(wsVideoRow)

        NSLayoutConstraint.activate([
            card3Stack.topAnchor.constraint(equalTo: card3.topAnchor, constant: 4),
            card3Stack.bottomAnchor.constraint(equalTo: card3.bottomAnchor, constant: -4),
            card3Stack.leadingAnchor.constraint(equalTo: card3.leadingAnchor, constant: 16),
            card3Stack.trailingAnchor.constraint(equalTo: card3.trailingAnchor, constant: -16)
        ])
        wsStack.addArrangedSubview(card3)

        // ── WS Log ──
        wsStack.addArrangedSubview(sectionHeader("LOG"))

        let logCard = cardView()
        wsLogView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        wsLogView.textColor = .label
        wsLogView.backgroundColor = .systemBackground
        wsLogView.isEditable = false
        wsLogView.isScrollEnabled = true
        wsLogView.translatesAutoresizingMaskIntoConstraints = false
        logCard.addSubview(wsLogView)

        NSLayoutConstraint.activate([
            wsLogView.topAnchor.constraint(equalTo: logCard.topAnchor, constant: 8),
            wsLogView.bottomAnchor.constraint(equalTo: logCard.bottomAnchor, constant: -8),
            wsLogView.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 12),
            wsLogView.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -12),
            wsLogView.heightAnchor.constraint(equalToConstant: 200)
        ])
        wsStack.addArrangedSubview(logCard)
    }

    private func observeWS() {
        recordingManager?.$wsDiag
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                guard let self, !msg.isEmpty else { return }
                let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                wsLogLines.append("[\(ts)] \(msg)")
                if wsLogLines.count > maxLogLines { wsLogLines.removeFirst() }
                wsLogView.text = wsLogLines.joined(separator: "\n")
                let bottom = NSMakeRange(wsLogView.text.count - 1, 1)
                wsLogView.scrollRangeToVisible(bottom)
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private func toggleRow(_ label: String, _ toggle: UISwitch) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        row.isLayoutMarginsRelativeArrangement = true
        let l = UILabel()
        l.text = label
        l.font = .systemFont(ofSize: 16)
        row.addArrangedSubview(l)
        let hint = UILabel()
        hint.text = "(default: on)"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .tertiaryLabel
        row.addArrangedSubview(hint)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(toggle)
        return row
    }

    private func labeledRow(_ label: String, _ field: UITextField) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        row.isLayoutMarginsRelativeArrangement = true
        let l = UILabel()
        l.text = label
        l.font = .systemFont(ofSize: 16)
        l.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(l)
        row.addArrangedSubview(field)
        return row
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabel
        return l
    }

    private func cardView() -> UIView {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 12
        v.layer.cornerCurve = .continuous
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.06
        v.layer.shadowRadius = 8
        v.layer.shadowOffset = CGSize(width: 0, height: 2)
        return v
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    // MARK: - Settings

    private func loadSettings() {
        subjectIDField.text = defaults.string(forKey: kSubjectID) ?? ""
        sessionNoteField.text = defaults.string(forKey: kSessionNote) ?? ""
        saveCSVToggle.isOn = defaults.object(forKey: kSaveCSV) == nil ? true : defaults.bool(forKey: kSaveCSV)
        saveVideoToggle.isOn = defaults.bool(forKey: kSaveVideo)
        hostField.text = defaults.string(forKey: kHost) ?? ""
        portField.text = defaults.string(forKey: kPort) ?? ""
        udpToggle.isOn = defaults.bool(forKey: kUDP)
        if udpToggle.isOn && !validateHostPort(silent: true) {
            udpToggle.isOn = false
            defaults.set(false, forKey: kUDP)
        }

        videoHostField.text = defaults.string(forKey: kVideoHost) ?? ""
        videoPortField.text = defaults.string(forKey: kVideoPort) ?? ""
        udpVideoToggle.isOn = defaults.bool(forKey: kVideoEnabled)
        if udpVideoToggle.isOn && !validateVideoHostPort(silent: true) {
            udpVideoToggle.isOn = false
            defaults.set(false, forKey: kVideoEnabled)
        }

        wsURLField.text = defaults.string(forKey: kWSURL) ?? ""
        wsToggle.isOn = defaults.bool(forKey: kWSEnabled)
        wsVideoToggle.isOn = defaults.bool(forKey: kWSVideo)
        updateWSVideoRowState()
        if wsToggle.isOn && !validateWSURL(silent: true) {
            wsToggle.isOn = false
            defaults.set(false, forKey: kWSEnabled)
            updateWSVideoRowState()
        }
    }

    @objc private func subjectIDChanged() {
        defaults.set(subjectIDField.text ?? "", forKey: kSubjectID)
    }

    @objc private func sessionNoteChanged() {
        defaults.set(sessionNoteField.text ?? "", forKey: kSessionNote)
    }

    @objc private func saveVideoToggled() {
        defaults.set(saveVideoToggle.isOn, forKey: kSaveVideo)
    }

    @objc private func saveCSVToggled() {
        defaults.set(saveCSVToggle.isOn, forKey: kSaveCSV)
    }

    // MARK: - UDP settings

    @objc private func hostChanged() {
        let text = hostField.text ?? ""
        defaults.set(text, forKey: kHost)
        hostError.isHidden = true
    }

    @objc private func hostEditingDidEnd() {
        validateHostPort(silent: false)
    }

    @objc private func portChanged() {
        let text = portField.text ?? ""
        defaults.set(text, forKey: kPort)
        portError.isHidden = true
    }

    @objc private func portEditingDidEnd() {
        validateHostPort(silent: false)
    }

    @objc private func udpToggled() {
        if udpToggle.isOn {
            if validateHostPort(silent: false) {
                defaults.set(true, forKey: kUDP)
                recordingManager?.udpSender.start()
            } else {
                udpToggle.isOn = false
                defaults.set(false, forKey: kUDP)
            }
        } else {
            defaults.set(false, forKey: kUDP)
            recordingManager?.udpSender.stop()
        }
    }

    @discardableResult
    private func validateHostPort(silent: Bool) -> Bool {
        let host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let port = portField.text?.trimmingCharacters(in: .whitespaces) ?? ""

        let hostValid = isValidHost(host)
        let portValid = isValidPort(port)

        if !silent {
            hostError.text = host.isEmpty ? "Required" : (hostValid ? nil : "Invalid IP or hostname")
            hostError.isHidden = hostValid
            portError.text = port.isEmpty ? "Required" : (portValid ? nil : "Port must be 1024\u{2013}65535")
            portError.isHidden = portValid
        }

        return hostValid && portValid
    }

    private func isValidHost(_ host: String) -> Bool {
        if host.isEmpty { return false }
        let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if host.range(of: ipv4Pattern, options: .regularExpression) != nil {
            let parts = host.split(separator: ".")
            return parts.allSatisfy { p in
                guard let n = Int(p), n >= 0, n <= 255 else { return false }
                return String(n) == String(p)
            }
        }
        let hostPattern = #"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$"#
        if host.range(of: hostPattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func isValidPort(_ port: String) -> Bool {
        guard let n = Int(port), n >= 1024, n <= 65535 else { return false }
        return true
    }

    var saveVideo: Bool { saveVideoToggle.isOn }

    // MARK: - UDP Video settings

    @objc private func videoHostChanged() {
        let text = videoHostField.text ?? ""
        defaults.set(text, forKey: kVideoHost)
        videoHostError.isHidden = true
    }

    @objc private func videoHostEditingDidEnd() {
        validateVideoHostPort(silent: false)
    }

    @objc private func videoPortChanged() {
        let text = videoPortField.text ?? ""
        defaults.set(text, forKey: kVideoPort)
        videoPortError.isHidden = true
    }

    @objc private func videoPortEditingDidEnd() {
        validateVideoHostPort(silent: false)
    }

    @objc private func udpVideoToggled() {
        if udpVideoToggle.isOn {
            if validateVideoHostPort(silent: false) {
                defaults.set(true, forKey: kVideoEnabled)
            } else {
                udpVideoToggle.isOn = false
                defaults.set(false, forKey: kVideoEnabled)
            }
        } else {
            defaults.set(false, forKey: kVideoEnabled)
            recordingManager?.udpVideoSender.stop()
        }
    }

    @discardableResult
    private func validateVideoHostPort(silent: Bool) -> Bool {
        let host = videoHostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let port = videoPortField.text?.trimmingCharacters(in: .whitespaces) ?? ""

        let hostValid = isValidHost(host)
        let portValid = isValidPort(port)

        if !silent {
            videoHostError.text = host.isEmpty ? "Required" : (hostValid ? nil : "Invalid IP or hostname")
            videoHostError.isHidden = hostValid
            videoPortError.text = port.isEmpty ? "Required" : (portValid ? nil : "Port must be 1024\u{2013}65535")
            videoPortError.isHidden = portValid
        }

        return hostValid && portValid
    }

    // MARK: - WebSocket settings

    @objc private func wsURLChanged() {
        defaults.set(wsURLField.text ?? "", forKey: kWSURL)
        wsURLError.isHidden = true
    }

    @objc private func wsURLEditingDidEnd() {
        validateWSURL(silent: false)
    }

    @objc private func wsToggled() {
        if wsToggle.isOn {
            if validateWSURL(silent: false) {
                defaults.set(true, forKey: kWSEnabled)
                let url = wsURLField.text ?? ""
                recordingManager?.webSocketSender.configure(urlString: url)
                recordingManager?.webSocketSender.connect()
            } else {
                wsToggle.isOn = false
                defaults.set(false, forKey: kWSEnabled)
            }
        } else {
            defaults.set(false, forKey: kWSEnabled)
            recordingManager?.webSocketSender.disconnect()
        }
        updateWSVideoRowState()
        recordingManager?.reevaluateWSVideo()
    }

    @objc private func wsVideoToggled() {
        defaults.set(wsVideoToggle.isOn, forKey: kWSVideo)
        recordingManager?.webSocketSender.videoEnabled = wsVideoToggle.isOn
        recordingManager?.reevaluateWSVideo()
    }

    @discardableResult
    private func validateWSURL(silent: Bool) -> Bool {
        let text = wsURLField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !text.isEmpty else {
            if !silent { wsURLError.text = "Required"; wsURLError.isHidden = false }
            return false
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              url.host != nil, !url.host!.isEmpty else {
            if !silent { wsURLError.text = "Must be ws:// or wss:// URL"; wsURLError.isHidden = false }
            return false
        }
        wsURLError.isHidden = true
        return true
    }

    private func updateWSVideoRowState() {
        let enabled = wsToggle.isOn
        wsVideoToggle.isEnabled = enabled
        wsVideoRow.alpha = enabled ? 1.0 : 0.4
    }

    // MARK: - UITextFieldDelegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard string.rangeOfCharacter(from: allowed.inverted) == nil else { return false }
        guard let current = textField.text as NSString? else { return true }
        let next = current.replacingCharacters(in: range, with: string)
        return next.utf8.count <= 32
    }

    // MARK: - Browse files

    @objc private func browseFiles() {
        let csvType = UTType(filenameExtension: "csv") ?? .plainText
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [csvType, .mpeg4Movie])
        picker.delegate = self
        present(picker, animated: true)
    }
}

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let name = url.lastPathComponent
        let alert = UIAlertController(title: name, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Share\u{2026}", style: .default) { [weak self] _ in
            self?.shareFile(at: url)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.recordingManager?.deleteRecordedFile(at: url)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func shareFile(at url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(vc, animated: true)
    }
}
