import SwiftUI

struct CaptureView: View {
    @StateObject var viewModel: CaptureViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Camera preview area
                ZStack {
                    if viewModel.isCameraReady {
                        CameraPreviewView(session: viewModel.cameraSession)
                            .ignoresSafeArea(edges: .top)

                        // Skeleton overlay
                        SkeletonOverlayView(joints: viewModel.currentPoses.first?.joints ?? [:])
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("Camera unavailable")
                                .font(.headline)
                            Text("Check camera permissions in Settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

                // Status bar
                statusBar
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { viewModel.start() }
            .onDisappear { viewModel.stop() }
        }
    }

    private var statusBar: some View {
        HStack {
            statusIndicator
            Spacer()
            Text(viewModel.modeLabel)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(viewModel.isConnected ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

import AVFoundation

struct SkeletonOverlayView: View {
    let joints: [String: JointPoint]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let connections: [(String, String)] = [
                    ("right_wrist", "right_elbow"),
                    ("right_elbow", "right_shoulder"),
                    ("left_wrist", "left_elbow"),
                    ("left_elbow", "left_shoulder"),
                    ("right_shoulder", "neck"),
                    ("left_shoulder", "neck"),
                    ("neck", "root"),
                    ("right_hip", "root"),
                    ("left_hip", "root"),
                    ("right_hip", "right_knee"),
                    ("right_knee", "right_ankle"),
                    ("left_hip", "left_knee"),
                    ("left_knee", "left_ankle"),
                ]

                for (from, to) in connections {
                    guard let fromJoint = joints[from],
                          let toJoint = joints[to],
                          fromJoint.confidence > 0.3,
                          toJoint.confidence > 0.3
                    else { continue }

                    let fromPoint = CGPoint(
                        x: fromJoint.x * size.width,
                        y: fromJoint.y * size.height
                    )
                    let toPoint = CGPoint(
                        x: toJoint.x * size.width,
                        y: toJoint.y * size.height
                    )

                    var path = Path()
                    path.move(to: fromPoint)
                    path.addLine(to: toPoint)
                    context.stroke(path, with: .color(.green), lineWidth: 2)
                }

                for (name, joint) in joints where joint.confidence > 0.3 {
                    let point = CGPoint(
                        x: joint.x * size.width,
                        y: joint.y * size.height
                    )
                    let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(.green))
                }
            }
        }
    }
}
