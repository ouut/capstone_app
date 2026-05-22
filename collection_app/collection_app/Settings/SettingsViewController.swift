import UIKit
import UniformTypeIdentifiers

final class SettingsViewController: UIViewController {

    private let dataIDField = UITextField()
    private let saveVideoToggle = UISwitch()
    private let hostField = UITextField()
    private let portField = UITextField()
    private let udpToggle = UISwitch()
    private let hostError = UILabel()
    private let portError = UILabel()

    var recordingManager: RecordingManager?

    private let defaults = UserDefaults.standard
    private let kDataID = "recording_data_id"
    private let kSaveVideo = "recording_save_video"
    private let kHost = "udp_host"
    private let kPort = "udp_port"
    private let kUDP = "udp_enabled"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        title = "Settings"
        setupUI()
        loadSettings()
    }

    private func setupUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        // ── Section: Recording Config ──
        stack.addArrangedSubview(sectionHeader("RECORDING CONFIG"))

        let card1 = cardView()
        let card1Stack = UIStackView()
        card1Stack.axis = .vertical
        card1Stack.spacing = 0
        card1Stack.translatesAutoresizingMaskIntoConstraints = false
        card1.addSubview(card1Stack)

        // Data ID row
        let idRow = UIStackView()
        idRow.axis = .horizontal
        idRow.spacing = 12
        idRow.alignment = .center
        idRow.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        idRow.isLayoutMarginsRelativeArrangement = true

        let idLabel = UILabel()
        idLabel.text = "Data ID"
        idLabel.font = .systemFont(ofSize: 16)
        idLabel.setContentHuggingPriority(.required, for: .horizontal)
        idRow.addArrangedSubview(idLabel)

        dataIDField.borderStyle = .none
        dataIDField.font = .systemFont(ofSize: 16)
        dataIDField.textAlignment = .right
        dataIDField.textColor = .secondaryLabel
        dataIDField.placeholder = "yyyy-MM-dd-HHmmss"
        dataIDField.addTarget(self, action: #selector(dataIDChanged), for: .editingChanged)
        idRow.addArrangedSubview(dataIDField)
        card1Stack.addArrangedSubview(idRow)

        card1Stack.addArrangedSubview(divider())

        // Save video row
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
        stack.addArrangedSubview(card1)

        // ── Section: UDP Streaming ──
        stack.addArrangedSubview(sectionHeader("UDP STREAMING"))

        let card2 = cardView()
        let card2Stack = UIStackView()
        card2Stack.axis = .vertical
        card2Stack.spacing = 0
        card2Stack.translatesAutoresizingMaskIntoConstraints = false
        card2.addSubview(card2Stack)

        // Host row
        hostField.borderStyle = .none
        hostField.font = .systemFont(ofSize: 16)
        hostField.textAlignment = .right
        hostField.textColor = .secondaryLabel
        hostField.placeholder = "192.168.1.100"
        hostField.keyboardType = .URL
        hostField.autocapitalizationType = .none
        hostField.autocorrectionType = .no
        hostField.addTarget(self, action: #selector(hostChanged), for: .editingChanged)
        hostField.addTarget(self, action: #selector(hostEditingDidEnd), for: .editingDidEnd)
        card2Stack.addArrangedSubview(labeledRow("IP / Hostname", hostField))

        // Host error
        hostError.font = .systemFont(ofSize: 11)
        hostError.textColor = .systemRed
        hostError.isHidden = true
        hostError.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        hostError.isLayoutMarginsRelativeArrangement = true
        card2Stack.addArrangedSubview(hostError)

        card2Stack.addArrangedSubview(divider())

        // Port row
        portField.borderStyle = .none
        portField.font = .systemFont(ofSize: 16)
        portField.textAlignment = .right
        portField.textColor = .secondaryLabel
        portField.placeholder = "9999"
        portField.keyboardType = .numberPad
        portField.addTarget(self, action: #selector(portChanged), for: .editingChanged)
        portField.addTarget(self, action: #selector(portEditingDidEnd), for: .editingDidEnd)
        card2Stack.addArrangedSubview(labeledRow("Port", portField))

        // Port error
        portError.font = .systemFont(ofSize: 11)
        portError.textColor = .systemRed
        portError.isHidden = true
        portError.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        portError.isLayoutMarginsRelativeArrangement = true
        card2Stack.addArrangedSubview(portError)

        card2Stack.addArrangedSubview(divider())

        // UDP toggle row
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
        stack.addArrangedSubview(card2)

        // ── Section: Browse Files ──
        stack.addArrangedSubview(sectionHeader("RECORDED FILES"))

        let browseBtn = UIButton(type: .system)
        browseBtn.setTitle("Browse Recordings\u{2026}", for: .normal)
        browseBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        browseBtn.backgroundColor = .systemBlue
        browseBtn.setTitleColor(.white, for: .normal)
        browseBtn.layer.cornerRadius = 10
        browseBtn.layer.cornerCurve = .continuous
        browseBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        browseBtn.addTarget(self, action: #selector(browseFiles), for: .touchUpInside)
        stack.addArrangedSubview(browseBtn)

        // Layout
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])
    }

    // MARK: - Helpers

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
        let now = Date()
        let defaultID = dateFormatter.string(from: now)
        dataIDField.text = defaults.string(forKey: kDataID) ?? defaultID
        saveVideoToggle.isOn = defaults.bool(forKey: kSaveVideo)
        hostField.text = defaults.string(forKey: kHost) ?? ""
        portField.text = defaults.string(forKey: kPort) ?? ""
        udpToggle.isOn = defaults.bool(forKey: kUDP)
        // If host/port are invalid and UDP was on, force off
        if udpToggle.isOn && !validateHostPort(silent: true) {
            udpToggle.isOn = false
            defaults.set(false, forKey: kUDP)
        }
    }

    @objc private func dataIDChanged() {
        defaults.set(dataIDField.text ?? "", forKey: kDataID)
    }

    @objc private func saveVideoToggled() {
        defaults.set(saveVideoToggle.isOn, forKey: kSaveVideo)
    }

    // MARK: - UDP settings

    @objc private func hostChanged() {
        let text = hostField.text ?? ""
        defaults.set(text, forKey: kHost)
        // Only clear error, don't validate while typing
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
        // IPv4: 1.2.3.4
        let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if host.range(of: ipv4Pattern, options: .regularExpression) != nil {
            let parts = host.split(separator: ".")
            return parts.allSatisfy { p in
                guard let n = Int(p), n >= 0, n <= 255 else { return false }
                return String(n) == String(p)  // reject "01" style
            }
        }
        // Hostname: a-z, 0-9, hyphen, dots, at least one dot
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

    var dataID: String { dataIDField.text ?? dateFormatter.string(from: Date()) }
    var saveVideo: Bool { saveVideoToggle.isOn }

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

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()
