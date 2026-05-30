import UIKit
import Vision

/// Overlay view that draws hand skeleton joints as circles and connections as lines.
/// Displays on top of ARView camera feed.
final class HandSkeletonOverlayView: UIView {

    /// Per-hand joint data from Vision.
    struct HandData {
        enum Chirality { case left, right }

        let chirality: Chirality
        /// 21 joints in Vision order (0–20), in view coordinates.
        var points: [CGPoint?]
    }

    var hands: [HandData] = [] {
        didSet { setNeedsDisplay() }
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Joint index mapping

    static let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    private static let jointIndexMap: [VNHumanHandPoseObservation.JointName: Int] = {
        Dictionary(uniqueKeysWithValues: zip(jointOrder, 0...))
    }()

    static func indexForJoint(_ name: VNHumanHandPoseObservation.JointName) -> Int {
        jointIndexMap[name] ?? -1
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard !hands.isEmpty else { return }

        let ctx = UIGraphicsGetCurrentContext()
        for hand in hands {
            drawHand(hand, ctx: ctx)
        }
    }

    /// Colors for each finger group (0=wrist, 1=thumb, 2=index, 3=middle, 4=ring, 5=little).
    private static let fingerColors: [UIColor] = [
        UIColor.white,                                                   // 0 wrist
        UIColor(white: 0.25, alpha: 1.0),                                // 1 thumb (dark gray)
        UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0),         // 2 index (red)
        UIColor(red: 0.25, green: 0.85, blue: 0.35, alpha: 1.0),        // 3 middle (green)
        UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1.0),          // 4 ring (orange)
        UIColor(red: 0.9, green: 0.3, blue: 0.9, alpha: 1.0),           // 5 little (magenta)
    ]

    /// Returns finger group index for a joint index:
    /// 0=wrist, 1=thumb(1-4), 2=index(5-8), 3=middle(9-12), 4=ring(13-16), 5=little(17-20).
    private static let jointGroup: [Int] = {
        var g = [0]  // wrist
        g += Array(repeating: 1, count: 4)   // thumb:  1-4
        g += Array(repeating: 2, count: 4)   // index:  5-8
        g += Array(repeating: 3, count: 4)   // middle: 9-12
        g += Array(repeating: 4, count: 4)   // ring:   13-16
        g += Array(repeating: 5, count: 4)   // little: 17-20
        return g
    }()

    private func drawHand(_ hand: HandData, ctx: CGContext?) {
        let joints = hand.points
        guard joints.count == 21 else { return }

        let jointRadius: CGFloat = 5
        let lineWidth: CGFloat = 2.5

        // ── Connections: per-finger color, wrist-to-finger uses finger color ──
        let connections: [(Int, Int)] = [
            // Thumb
            (0, 1), (1, 2), (2, 3), (3, 4),
            // Index
            (0, 5), (5, 6), (6, 7), (7, 8),
            // Middle
            (0, 9), (9, 10), (10, 11), (11, 12),
            // Ring
            (0, 13), (13, 14), (14, 15), (15, 16),
            // Little
            (0, 17), (17, 18), (18, 19), (19, 20),
        ]

        for (a, b) in connections {
            guard let pa = joints[a], let pb = joints[b] else { continue }
            let group = Self.jointGroup[b]  // use finger's color
            let c = Self.fingerColors[group]
            ctx?.setStrokeColor(c.withAlphaComponent(0.7).cgColor)
            ctx?.setLineWidth(lineWidth)
            ctx?.move(to: pa)
            ctx?.addLine(to: pb)
            ctx?.strokePath()
        }

        // Knuckle line (light gray, lower alpha)
        ctx?.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        ctx?.setLineWidth(1.5)
        let knuckles = [5, 9, 13, 17]
        for i in 0..<(knuckles.count - 1) {
            guard let pa = joints[knuckles[i]], let pb = joints[knuckles[i + 1]] else { continue }
            ctx?.move(to: pa)
            ctx?.addLine(to: pb)
        }
        ctx?.strokePath()

        // ── Joint dots with white outline, filled with finger color ──
        for (i, pt) in joints.enumerated() {
            guard let p = pt else { continue }
            let group = Self.jointGroup[i]
            let fillColor = Self.fingerColors[group]
            let rect = CGRect(x: p.x - jointRadius, y: p.y - jointRadius,
                              width: jointRadius * 2, height: jointRadius * 2)

            // White outline
            ctx?.setFillColor(UIColor.white.cgColor)
            ctx?.fillEllipse(in: rect.insetBy(dx: -1.5, dy: -1.5))

            // Finger color fill
            ctx?.setFillColor(fillColor.cgColor)
            ctx?.fillEllipse(in: rect)
        }
    }
}
