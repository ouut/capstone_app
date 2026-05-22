import UIKit

final class SettingsViewController: UIViewController {

    private let dataIDField = UITextField()
    private let saveVideoToggle = UISwitch()
    private let fileListCard = UIView()
    private let fileListStack = UIStackView()
    private let fileListEmpty = UILabel()

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFileList()
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

        // ── Section: Recorded Files ──
        stack.addArrangedSubview(sectionHeader("RECORDED FILES"))

        fileListCard.backgroundColor = .systemBackground
        fileListCard.layer.cornerRadius = 12
        fileListCard.layer.cornerCurve = .continuous
        fileListCard.layer.shadowColor = UIColor.black.cgColor
        fileListCard.layer.shadowOpacity = 0.06
        fileListCard.layer.shadowRadius = 8
        fileListCard.layer.shadowOffset = CGSize(width: 0, height: 2)
        fileListCard.isHidden = true
        stack.addArrangedSubview(fileListCard)

        fileListStack.axis = .vertical
        fileListStack.spacing = 0
        fileListStack.translatesAutoresizingMaskIntoConstraints = false
        fileListCard.addSubview(fileListStack)

        fileListEmpty.text = "No recordings yet"
        fileListEmpty.font = .systemFont(ofSize: 14)
        fileListEmpty.textColor = .secondaryLabel
        fileListEmpty.textAlignment = .center
        fileListEmpty.isHidden = true
        stack.addArrangedSubview(fileListEmpty)

        NSLayoutConstraint.activate([
            fileListStack.topAnchor.constraint(equalTo: fileListCard.topAnchor, constant: 8),
            fileListStack.bottomAnchor.constraint(equalTo: fileListCard.bottomAnchor, constant: -8),
            fileListStack.leadingAnchor.constraint(equalTo: fileListCard.leadingAnchor, constant: 16),
            fileListStack.trailingAnchor.constraint(equalTo: fileListCard.trailingAnchor, constant: -16)
        ])

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

    // MARK: - File list

    private func refreshFileList() {
        guard let files = recordingManager?.listRecordedFiles() else { return }
        fileListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if files.isEmpty {
            fileListCard.isHidden = true
            fileListEmpty.isHidden = false
            return
        }

        fileListCard.isHidden = false
        fileListEmpty.isHidden = true

        for (i, file) in files.enumerated() {
            let row = makeFileRow(file)
            fileListStack.addArrangedSubview(row)
            if i < files.count - 1 {
                fileListStack.addArrangedSubview(divider())
            }
        }
    }

    private func makeFileRow(_ file: RecordedFile) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        row.isLayoutMarginsRelativeArrangement = true

        let icon = UIImageView(image: UIImage(systemName: file.isCSV ? "tablecells" : "film"))
        icon.tintColor = file.isCSV ? .systemGreen : .systemBlue
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        row.addArrangedSubview(icon)

        let labelStack = UIStackView()
        labelStack.axis = .vertical
        labelStack.spacing = 2
        let nameLabel = UILabel()
        nameLabel.text = file.name
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        let infoLabel = UILabel()
        let sizeStr = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        infoLabel.text = "\(dateDisplayFormatter.string(from: file.date))  \(sizeStr)"
        infoLabel.font = .systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(nameLabel)
        labelStack.addArrangedSubview(infoLabel)
        row.addArrangedSubview(labelStack)

        row.addArrangedSubview(UIView())

        let shareBtn = UIButton(type: .system)
        shareBtn.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareBtn.widthAnchor.constraint(equalToConstant: 32).isActive = true
        shareBtn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        shareBtn.addAction(UIAction { [weak self] _ in self?.shareFile(file) }, for: .touchUpInside)
        row.addArrangedSubview(shareBtn)

        // Context menu for delete
        let interaction = UIContextMenuInteraction(delegate: self)
        row.addInteraction(interaction)
        row.accessibilityValue = file.url.path

        return row
    }

    private func shareFile(_ file: RecordedFile) {
        let vc = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(vc, animated: true)
    }

    private func confirmDelete(_ file: RecordedFile, sourceView: UIView) {
        let alert = UIAlertController(title: "Delete \"\(file.name)\"?", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.recordingManager?.deleteRecordedFile(at: file.url)
            self?.refreshFileList()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }
        present(alert, animated: true)
    }
}

extension SettingsViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let row = interaction.view,
              let path = row.accessibilityValue,
              let files = recordingManager?.listRecordedFiles(),
              let file = files.first(where: { $0.url.path == path }) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.recordingManager?.deleteRecordedFile(at: file.url)
                self?.refreshFileList()
            }
            return UIMenu(children: [delete])
        }
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private let dateDisplayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd  HH:mm"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()
