import UIKit

protocol SettingsViewControllerDelegate: AnyObject {
    func settingsDidUpdate(host: String, port: UInt16, modelURL: String?)
    func settingsDidRequestDownload(url: URL)
}

class SettingsViewController: UIViewController {

    weak var delegate: SettingsViewControllerDelegate?

    // MARK: - UI Elements
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let hostField = UITextField()
    private let hostError = UILabel()
    private let portField = UITextField()
    private let portError = UILabel()
    private let connectionDot = UIView()

    private let urlField = UITextField()
    private let urlError = UILabel()
    private let downloadButton = UIButton(type: .system)
    private let modelDot = UIView()

    private let statusLabel = UILabel()
    private var modelLoaded = false

    // MARK: - Keys
    private enum Keys {
        static let host = "udp_host", port = "udp_port", url = "model_url"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismissSelf))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(save))

        setupScrollView()
        setupUDPSection()
        setupModelSection()
        setupStatusArea()
        loadDefaults()
        addTextFieldTargets()
    }

    // MARK: - Scroll Setup
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.layoutMarginsGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    // MARK: - UDP Section
    private func setupUDPSection() {
        let card = makeCard()
        let cardStack = card.subviews.first as! UIStackView

        let header = makeSectionHeader(icon: "antenna.radiowaves.left.and.right", title: "UDP Server")

        func makeRow(label: String, field: UITextField, error: UILabel, placeholder: String, keyboard: UIKeyboardType) -> UIView {
            let row = UIStackView()
            row.axis = .vertical
            row.spacing = 4

            let lbl = UILabel()
            lbl.text = label
            lbl.font = .preferredFont(forTextStyle: .caption1)
            lbl.textColor = .secondaryLabel

            field.placeholder = placeholder
            field.borderStyle = .roundedRect
            field.keyboardType = keyboard
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
            field.layer.cornerRadius = 8
            field.layer.borderWidth = 1
            field.layer.borderColor = UIColor.clear.cgColor

            error.font = .preferredFont(forTextStyle: .caption2)
            error.textColor = .systemRed
            error.isHidden = true

            row.addArrangedSubview(lbl)
            row.addArrangedSubview(field)
            row.addArrangedSubview(error)
            return row
        }

        hostField.placeholder = "100.99.98.5"
        hostField.keyboardType = .decimalPad
        portField.placeholder = "8888"
        portField.keyboardType = .numberPad

        let connRow = UIStackView()
        connRow.axis = .horizontal
        connRow.spacing = 6
        connRow.alignment = .center
        connectionDot.backgroundColor = .systemGray
        connectionDot.layer.cornerRadius = 4
        connectionDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        connectionDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let connLabel = UILabel()
        connLabel.text = "Connection"
        connLabel.font = .preferredFont(forTextStyle: .caption2)
        connLabel.textColor = .secondaryLabel
        connRow.addArrangedSubview(connectionDot)
        connRow.addArrangedSubview(connLabel)

        cardStack.addArrangedSubview(header)
        cardStack.addArrangedSubview(makeRow(label: "IP Address", field: hostField, error: hostError, placeholder: "100.99.98.5", keyboard: .decimalPad))
        cardStack.addArrangedSubview(makeRow(label: "Port", field: portField, error: portError, placeholder: "8888", keyboard: .numberPad))
        cardStack.addArrangedSubview(connRow)

        contentStack.addArrangedSubview(card)
    }

    // MARK: - Model Section
    private func setupModelSection() {
        let card = makeCard()
        let cardStack = card.subviews.first as! UIStackView

        let header = makeSectionHeader(icon: "brain.head.profile", title: "CoreML Model")

        let urlLabel = UILabel()
        urlLabel.text = "Model URL"
        urlLabel.font = .preferredFont(forTextStyle: .caption1)
        urlLabel.textColor = .secondaryLabel

        urlField.placeholder = "https://example.com/model.mlmodel"
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        urlField.borderStyle = .roundedRect
        urlField.layer.cornerRadius = 8
        urlField.layer.borderWidth = 1
        urlField.layer.borderColor = UIColor.clear.cgColor

        urlError.font = .preferredFont(forTextStyle: .caption2)
        urlError.textColor = .systemRed
        urlError.isHidden = true

        downloadButton.setTitle("Download & Load", for: .normal)
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = .white
        downloadButton.backgroundColor = .systemIndigo
        downloadButton.layer.cornerRadius = 10
        downloadButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        downloadButton.addTarget(self, action: #selector(downloadModel), for: .touchUpInside)

        let statusRow = UIStackView()
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        modelDot.backgroundColor = .systemGray
        modelDot.layer.cornerRadius = 4
        modelDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        modelDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let modelLabel = UILabel()
        modelLabel.text = "Model"
        modelLabel.font = .preferredFont(forTextStyle: .caption2)
        modelLabel.textColor = .secondaryLabel
        statusRow.addArrangedSubview(modelDot)
        statusRow.addArrangedSubview(modelLabel)

        cardStack.addArrangedSubview(header)
        cardStack.addArrangedSubview(urlLabel)
        cardStack.addArrangedSubview(urlField)
        cardStack.addArrangedSubview(urlError)
        cardStack.addArrangedSubview(downloadButton)
        cardStack.addArrangedSubview(statusRow)

        contentStack.addArrangedSubview(card)
    }

    // MARK: - Status
    private func setupStatusArea() {
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        contentStack.addArrangedSubview(statusLabel)

        // Mock mode note
        let note = UILabel()
        note.numberOfLines = 0
        note.font = .preferredFont(forTextStyle: .caption2)
        note.textColor = .tertiaryLabel
        note.textAlignment = .center
        note.text = "Without a model, the app uses mock predictions so you can test the UDP pipeline end-to-end."
        contentStack.addArrangedSubview(note)
    }

    // MARK: - Helpers
    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func makeSectionHeader(icon: String, title: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let iv = UIImageView(image: UIImage(systemName: icon))
        iv.tintColor = .systemIndigo
        iv.contentMode = .scaleAspectFit
        iv.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let lbl = UILabel()
        lbl.text = title
        lbl.font = .systemFont(ofSize: 17, weight: .semibold)

        row.addArrangedSubview(iv)
        row.addArrangedSubview(lbl)
        return row
    }

    private func addTextFieldTargets() {
        [hostField, portField, urlField].forEach { f in
            f.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        }
    }

    // MARK: - Validation
    private func isValidIP(_ str: String) -> Bool {
        if str.isEmpty { return false }
        var sin = sockaddr_in()
        return str.withCString { inet_pton(AF_INET, $0, &sin.sin_addr) } == 1
    }

    private func isValidPort(_ str: String) -> Bool {
        guard let p = Int(str), (1...65535).contains(p) else { return false }
        return true
    }

    private func isValidURL(_ str: String) -> Bool {
        guard !str.isEmpty, let url = URL(string: str) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    @objc private func textFieldChanged() {
        // Live validation on the host field
        let host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let port = portField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let url = urlField.text?.trimmingCharacters(in: .whitespaces) ?? ""

        if !host.isEmpty {
            let valid = isValidIP(host)
            hostField.layer.borderColor = valid ? UIColor.systemGreen.cgColor : UIColor.systemRed.cgColor
            hostError.text = valid ? nil : "Invalid IP address — use format like 100.99.98.5"
            hostError.isHidden = valid
        } else {
            hostField.layer.borderColor = UIColor.clear.cgColor
            hostError.isHidden = true
        }

        if !port.isEmpty {
            let valid = isValidPort(port)
            portField.layer.borderColor = valid ? UIColor.systemGreen.cgColor : UIColor.systemRed.cgColor
            portError.text = valid ? nil : "Port must be 1–65535"
            portError.isHidden = valid
        } else {
            portField.layer.borderColor = UIColor.clear.cgColor
            portError.isHidden = true
        }

        if !url.isEmpty {
            let valid = isValidURL(url)
            urlField.layer.borderColor = valid ? UIColor.systemGreen.cgColor : UIColor.systemRed.cgColor
            urlError.text = valid ? nil : "Must start with http:// or https://"
            urlError.isHidden = valid
        } else {
            urlField.layer.borderColor = UIColor.clear.cgColor
            urlError.isHidden = true
        }

        connectionDot.backgroundColor = (isValidIP(host) && isValidPort(port)) ? .systemGreen : .systemGray
    }

    // MARK: - Data
    private func loadDefaults() {
        hostField.text = UserDefaults.standard.string(forKey: Keys.host) ?? "100.99.98.5"
        portField.text = UserDefaults.standard.string(forKey: Keys.port) ?? "8888"
        urlField.text = UserDefaults.standard.string(forKey: Keys.url) ?? ""
        textFieldChanged()
    }

    @objc private func save() {
        let host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let portText = portField.text?.trimmingCharacters(in: .whitespaces) ?? "8888"
        let port = UInt16(portText) ?? 8888
        let url = urlField.text?.trimmingCharacters(in: .whitespaces) ?? ""

        guard isValidIP(host) else {
            shake(hostField)
            hostError.text = "Enter a valid IP address"
            hostError.isHidden = false
            return
        }
        guard isValidPort(portText) else {
            shake(portField)
            portError.text = "Port must be 1–65535"
            portError.isHidden = false
            return
        }
        if !url.isEmpty, !isValidURL(url) {
            shake(urlField)
            urlError.text = "URL must start with http:// or https://"
            urlError.isHidden = false
            return
        }

        UserDefaults.standard.set(host, forKey: Keys.host)
        UserDefaults.standard.set(portText, forKey: Keys.port)
        UserDefaults.standard.set(url, forKey: Keys.url)

        delegate?.settingsDidUpdate(host: host, port: port, modelURL: url.isEmpty ? nil : url)
        dismiss(animated: true)
    }

    private func shake(_ view: UIView) {
        let anim = CABasicAnimation(keyPath: "position")
        anim.duration = 0.06
        anim.repeatCount = 3
        anim.autoreverses = true
        anim.fromValue = NSValue(cgPoint: CGPoint(x: view.center.x - 8, y: view.center.y))
        anim.toValue = NSValue(cgPoint: CGPoint(x: view.center.x + 8, y: view.center.y))
        view.layer.add(anim, forKey: "shake")
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func downloadModel() {
        guard let text = urlField.text?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty,
              let url = URL(string: text) else {
            shake(urlField)
            urlError.text = "Enter a valid URL"
            urlError.isHidden = false
            return
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            shake(urlField)
            urlError.text = "URL must start with http:// or https://"
            urlError.isHidden = false
            return
        }

        statusLabel.text = "Downloading…"
        statusLabel.textColor = .systemBlue
        downloadButton.isEnabled = false
        downloadButton.alpha = 0.5

        delegate?.settingsDidRequestDownload(url: url)
    }

    func showDownloadResult(success: Bool, message: String) {
        downloadButton.isEnabled = true
        downloadButton.alpha = 1.0
        statusLabel.text = message
        statusLabel.textColor = success ? .systemGreen : .systemRed
        modelDot.backgroundColor = success ? .systemGreen : .systemRed
        modelLoaded = success
    }
}
