import AVFoundation
import SwiftUI

/// The squat version of the Wake Up screen: the front camera fills the
/// screen, white lines trace the body (like fitness games do), and a big
/// "7/15" counts the squats.
struct SquatWakeView: View {
    var cameraSession: AVCaptureSession
    var pose: BodyPose?
    var count: Int
    var goal: Int
    /// 0 = standing, 1 = low enough to count.
    var depth: Double
    var now: Date = .now
    var label: String = ""
    var statusText: String
    var errorMessage: String? = nil
    var onEmergencyStop: (() -> Void)? = nil
    /// Only for the try-out from the Add Alarm page.
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cameraSession)
                .ignoresSafeArea()
            BodyLines(pose: pose, isLowEnough: depth >= 1)
                .ignoresSafeArea()
            // Darken top and bottom so the white text stays readable.
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: Theme.Spacing.sm) {
                header
                Spacer()
                footer
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 2) {
            HStack {
                Text(now, format: .dateTime.hour().minute())
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Close")
                }
            }
            .frame(minHeight: 40)

            Text("\(count)/\(goal)")
                .font(.system(size: 76, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3, bounce: 0.4), value: count)
                .shadow(color: .black.opacity(0.5), radius: 8)
            Text(label.isEmpty ? "squats to turn off the alarm" : label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            depthMeter

            Text(errorMessage ?? statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(errorMessage != nil ? Theme.accent : .white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.black.opacity(0.45), in: Capsule())
                .animation(.easeOut(duration: 0.2), value: statusText)

            if let onEmergencyStop {
                HoldToStopButton(title: "Can't squat? Hold for 10 seconds to stop", onComplete: onEmergencyStop)
                    .frame(minHeight: Theme.minTapTarget)
            }
        }
    }

    /// Fills up as you go down; turns green once you're low enough.
    private var depthMeter: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Low")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(depth >= 1 ? Color.green : .white)
                        .frame(width: geo.size.width * depth)
                        .animation(.easeOut(duration: 0.15), value: depth)
                }
            }
            .frame(height: 10)
        }
        .accessibilityHidden(true)
    }
}

/// White lines joining the shoulders, arms, hips and legs — green while
/// you're low enough for the squat to count.
private struct BodyLines: View {
    var pose: BodyPose?
    var isLowEnough: Bool

    /// A dot on every joint that a line touches (not eyes and ears).
    static let dotJoints = Set(BodyPose.bones.flatMap { [$0.0, $0.1] })

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let color: Color = isLowEnough ? .green : .white
            var lines = Path()
            for (from, to) in BodyPose.bones {
                guard let a = pose.joints[from], let b = pose.joints[to] else { continue }
                lines.move(to: previewPoint(a, in: size))
                lines.addLine(to: previewPoint(b, in: size))
            }
            var glow = context
            glow.addFilter(.shadow(color: .black.opacity(0.6), radius: 4))
            glow.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            for joint in BodyLines.dotJoints {
                guard let point = pose.joints[joint] else { continue }
                let p = previewPoint(point, in: size)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
