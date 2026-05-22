import UIKit
import UniformTypeIdentifiers

final class SettingsViewController: UIViewController {

    private let dataIDField = UITextField()
    private let saveVideoToggle = UISwitch()

    var recordingManager: RecordingManager?

    private let defaults = UserDefaults.standard
    private let kDataID = "recording_data_id"
    private let kSaveVideo = "recording_save_video"

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
    }

    @objc private func dataIDChanged() {
        defaults.set(dataIDField.text ?? "", forKey: kDataID)
    }

    @objc private func saveVideoToggled() {
        defaults.set(saveVideoToggle.isOn, forKey: kSaveVideo)
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
