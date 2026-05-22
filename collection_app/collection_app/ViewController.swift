/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The sample app's main view controller.
*/

import UIKit
import RealityKit
import ARKit
import Combine

class ViewController: UIViewController, ARSessionDelegate {

    @IBOutlet var arView: ARView!

    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0]
    let characterAnchor = AnchorEntity()

    // Recording
    let recordingManager = RecordingManager()
    private let recordButton = UIButton(type: .custom)
    private let recLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var latestCameraFrame: ARFrame?

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.session.delegate = self

        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)

        arView.scene.addAnchor(characterAnchor)

        // Load the 3D character
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "robot").sink(
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

        setupOverlay()
        observeRecording()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }

            // Update character position
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition + characterOffset
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation

            if let character = character, character.parent == nil {
                characterAnchor.addChild(character)
            }

            // Feed recording manager
            let camTransform = latestCameraFrame?.camera.transform ?? matrix_identity_float4x4
            let camPixelBuffer = latestCameraFrame?.capturedImage
            recordingManager.recordFrame(bodyAnchor: bodyAnchor,
                                         cameraTransform: camTransform,
                                         cameraPixelBuffer: camPixelBuffer)
        }
    }

    // Capture camera frames for optional video recording and camera pose
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestCameraFrame = frame
    }

    // MARK: - Overlay UI

    private func setupOverlay() {
        // ── Record button — iOS Camera-style ring + circle ──
        recordButton.backgroundColor = .clear
        recordButton.layer.cornerRadius = 36
        recordButton.layer.borderWidth = 5
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        view.addSubview(recordButton)

        // REC label above the button
        recLabel.text = "REC"
        recLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        recLabel.textColor = .white
        recLabel.textAlignment = .center
        recLabel.isHidden = true
        recLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recLabel)

        // ── Settings button ──
        let gearImage = UIImage(systemName: "gearshape.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        settingsButton.setImage(gearImage, for: .normal)
        settingsButton.tintColor = .white
        settingsButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        settingsButton.layer.cornerRadius = 16
        settingsButton.clipsToBounds = true
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        view.addSubview(settingsButton)

        // ── Status label ──
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.numberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Record button
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),

            // REC label
            recLabel.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            recLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -6),

            // Settings button
            settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),

            // Status label
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: recLabel.topAnchor, constant: -8),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])
    }

    private func observeRecording() {
        recordingManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rec in
                guard let self else { return }
                if rec {
                    // Recording state: red filled circle
                    self.recordButton.layer.borderColor = UIColor.systemRed.cgColor
                    self.recordButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
                    self.recLabel.textColor = .systemRed
                    self.recLabel.isHidden = false
                } else {
                    // Idle: white ring, semi-transparent fill
                    self.recordButton.layer.borderColor = UIColor.white.cgColor
                    self.recordButton.backgroundColor = UIColor.white.withAlphaComponent(0.25)
                    self.recLabel.isHidden = true
                }
            }
            .store(in: &cancellables)

        recordingManager.$elapsed.combineLatest(recordingManager.$frameCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsed, count in
                guard let self, self.recordingManager.isRecording else { return }
                let min = Int(elapsed) / 60
                let sec = Int(elapsed) % 60
                self.statusLabel.text = String(format: "  ● REC  %02d:%02d  |  %d frames  ", min, sec, count)
            }
            .store(in: &cancellables)

        recordingManager.onStatusChange = { [weak self] msg in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusLabel.text = "  \(msg)  "
                self.recLabel.isHidden = !self.recordingManager.isRecording
                if !self.recordingManager.isRecording {
                    self.statusLabel.textColor = .systemGreen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.statusLabel.text = ""
                        self.statusLabel.textColor = .white
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        if recordingManager.isRecording {
            let dataID = defaults.string(forKey: "recording_data_id") ?? ""
            let saveVideo = defaults.bool(forKey: "recording_save_video")
            recordingManager.stopRecording(dataID: dataID, saveVideo: saveVideo)
        } else {
            let saveVideo = defaults.bool(forKey: "recording_save_video")
            recordingManager.startRecording(saveVideo: saveVideo)
        }
    }

    @objc private func openSettings() {
        let vc = SettingsViewController()
        vc.recordingManager = recordingManager
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(nav, animated: true)
    }
}
