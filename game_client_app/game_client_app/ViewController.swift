import UIKit
import RealityKit
import ARKit
import Combine

class ViewController: UIViewController, ARSessionDelegate {

    @IBOutlet var arView: ARView!

    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0]
    let characterAnchor = AnchorEntity()

    let mlManager = MLModelManager()
    let udpClient = UDPClient()
    private var frameCounter = 0
    private let inferenceInterval = 6

    // Send feedback UI
    private let sendIndicator = UIView()
    private let packetLabel = UILabel()
    private let statusBar = UIView()
    private var packetCount = 0

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.session.delegate = self

        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)

        arView.scene.addAnchor(characterAnchor)

        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
            }, receiveValue: { (character: Entity) in
                if let character = character as? BodyTrackedEntity {
                    character.scale = [1.0, 1.0, 1.0]
                    self.character = character
                    cancellable?.cancel()
                } else {
                    print("Error: Unable to load model as BodyTrackedEntity")
                }
            }
        )

        setupOverlayUI()
        setupUDPCallbacks()
        loadSavedSettings()
    }

    // MARK: - Overlay UI

    private func setupOverlayUI() {
        setupSettingsButton()
        setupStatusBar()
        setupSendIndicator()
    }

    private func setupSettingsButton() {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        btn.layer.cornerRadius = 22
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(btn)

        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupStatusBar() {
        statusBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        statusBar.layer.cornerRadius = 12
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(stack)

        // Connection dot
        sendIndicator.backgroundColor = .systemGray
        sendIndicator.layer.cornerRadius = 5
        sendIndicator.widthAnchor.constraint(equalToConstant: 10).isActive = true
        sendIndicator.heightAnchor.constraint(equalToConstant: 10).isActive = true

        // Packet label
        packetLabel.text = "0"
        packetLabel.textColor = .white
        packetLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        let icon = UIImageView(image: UIImage(systemName: "paperplane.fill"))
        icon.tintColor = .white.withAlphaComponent(0.7)
        icon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        icon.contentMode = .scaleAspectFit

        stack.addArrangedSubview(sendIndicator)
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(packetLabel)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.topAnchor.constraint(equalTo: statusBar.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -14),
        ])
    }

    private func setupSendIndicator() {
        // The sendIndicator is already created and added to the status bar.
        // This method exists for clarity; the indicator dot lives in the status bar stack.
    }

    private func setupUDPCallbacks() {
        udpClient.onSend = { [weak self] in
            guard let self = self else { return }
            self.packetCount += 1
            self.packetLabel.text = "\(self.packetCount)"
            self.flashSendIndicator()
        }
        udpClient.onConnectionChange = { [weak self] connected in
            self?.sendIndicator.backgroundColor = connected ? .systemGreen : .systemRed
        }
    }

    private func flashSendIndicator() {
        sendIndicator.backgroundColor = .systemYellow
        sendIndicator.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            self.sendIndicator.backgroundColor = .systemGreen
            self.sendIndicator.transform = .identity
        })
    }

    private func loadSavedSettings() {
        let host = UserDefaults.standard.string(forKey: "udp_host") ?? "100.99.98.5"
        let portText = UserDefaults.standard.string(forKey: "udp_port") ?? "8888"
        let port = UInt16(portText) ?? 8888
        let url = UserDefaults.standard.string(forKey: "model_url") ?? ""

        udpClient.configure(host: host, port: port)
        udpClient.connect()

        if !url.isEmpty, let modelURL = URL(string: url) {
            mlManager.downloadModel(from: modelURL) { result in
                switch result {
                case .success(let name):
                    print("Model auto-loaded: \(name)")
                case .failure(let error):
                    print("Model auto-load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        settingsVC.delegate = self
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }

            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition + characterOffset
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation

            if let character = character, character.parent == nil {
                characterAnchor.addChild(character)
            }

            if mlManager.isModelLoaded {
                frameCounter += 1
                if frameCounter % inferenceInterval == 0 {
                    runInference(on: bodyAnchor)
                }
            }
        }
    }

    // MARK: - CoreML Inference

    private func runInference(on bodyAnchor: ARBodyAnchor) {
        let transforms = bodyAnchor.skeleton.jointModelTransforms
        let positions: [SIMD3<Float>] = transforms.map { simd_make_float3($0.columns.3) }

        mlManager.predict(jointPositions: positions) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let array):
                if let array = array, let data = self.mlManager.serializePrediction(array) {
                    self.udpClient.send(data)
                }
            case .failure(let error):
                print("Inference error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - SettingsViewControllerDelegate

extension ViewController: SettingsViewControllerDelegate {
    func settingsDidUpdate(host: String, port: UInt16, modelURL: String?) {
        udpClient.configure(host: host, port: port)
        udpClient.connect()
        packetCount = 0
        packetLabel.text = "0"

        if let urlStr = modelURL, let url = URL(string: urlStr) {
            mlManager.downloadModel(from: url) { _ in }
        }
    }

    func settingsDidRequestDownload(url: URL) {
        if let nav = presentedViewController as? UINavigationController,
           let settings = nav.topViewController as? SettingsViewController {
            mlManager.downloadModel(from: url) { result in
                switch result {
                case .success(let name):
                    settings.showDownloadResult(success: true, message: "Loaded: \(name)")
                case .failure(let error):
                    settings.showDownloadResult(success: false, message: "Failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
