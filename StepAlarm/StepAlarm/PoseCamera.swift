import AVFoundation
import SwiftUI
import Vision

/// One body found in a camera frame.
struct BodyPose {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    /// Joint positions from 0 to 1 in the upright, mirrored camera picture
    /// (x to the right, y down) — the same picture the preview shows.
    var joints: [Joint: CGPoint]
    /// How high the hips are above the knees (see `SquatDetector`), or nil
    /// if the legs aren't visible.
    var depth: Double?

    /// The lines drawn over the body on the squat screen.
    static let bones: [(Joint, Joint)] = [
        (.nose, .neck),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    /// Hip height above the knee divided by the shin's height, averaged over
    /// the legs that can be seen. If the feet are out of view, the upper body
    /// is used as the ruler instead.
    static func depth(of joints: [Joint: CGPoint]) -> Double? {
        var values: [Double] = []
        for (hip, knee, ankle, shoulder) in [
            (Joint.leftHip, Joint.leftKnee, Joint.leftAnkle, Joint.leftShoulder),
            (Joint.rightHip, Joint.rightKnee, Joint.rightAnkle, Joint.rightShoulder),
        ] {
            guard let h = joints[hip], let k = joints[knee] else { continue }
            let thigh = Double(k.y - h.y)
            if let a = joints[ankle], a.y - k.y > 0.03 {
                values.append(thigh / Double(a.y - k.y))
            } else if let s = joints[shoulder], h.y - s.y > 0.05 {
                // Standing, the thigh is about as tall as 85% of the upper body.
                values.append(thigh / (Double(h.y - s.y) * 0.85))
            }
        }
        guard !values.isEmpty else { return nil }
        return min(2, max(-1, values.reduce(0, +) / Double(values.count)))
    }
}

/// The front camera plus Apple's on-device body-pose detection. Frames are
/// looked at in memory only — nothing is recorded, saved, or sent anywhere.
final class PoseCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Called on the main thread for each analysed frame (nil = nobody found),
    /// with the frame's time in seconds.
    var onPose: ((BodyPose?, TimeInterval) -> Void)?

    /// Width ÷ height of the upright picture (1280×720 turned to portrait).
    static let pictureAspect: CGFloat = 720.0 / 1280.0
    /// Body detection runs at most this often (plenty for squats, easy on battery).
    private static let framesPerSecond: Double = 15

    private let queue = DispatchQueue(label: "alarm7.posecamera")
    private let request = VNDetectHumanBodyPoseRequest()
    private var isConfigured = false
    private var lastAnalysis: TimeInterval = 0

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    /// Asks for camera access if it hasn't been decided yet.
    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        queue.async { [self] in
            if !isConfigured { isConfigured = configure() }
            if isConfigured && !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // No microphone is used, so leave the alarm sound's audio setup alone.
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        // Upright and mirrored, exactly like the preview, so the joints
        // line up with what's on screen.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= 1 / Self.framesPerSecond else { return }
        lastAnalysis = now

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        var pose: BodyPose?
        if (try? handler.perform([request])) != nil,
           let observation = Self.largest(request.results ?? []),
           let points = try? observation.recognizedPoints(.all) {
            var joints: [BodyPose.Joint: CGPoint] = [:]
            for (name, point) in points where point.confidence > 0.3 {
                // Vision measures y from the bottom; the screen measures from the top.
                joints[name] = CGPoint(x: point.location.x, y: 1 - point.location.y)
            }
            if joints.count >= 4 {
                pose = BodyPose(joints: joints, depth: BodyPose.depth(of: joints))
            }
        }
        DispatchQueue.main.async { [weak self] in self?.onPose?(pose, now) }
    }

    /// With more than one person in view, follow the biggest (closest) one.
    private static func largest(_ observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { size(of: $0) < size(of: $1) }
    }

    private static func size(of observation: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? observation.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }),
              !points.isEmpty else { return 0 }
        let xs = points.map(\.location.x), ys = points.map(\.location.y)
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }
}

/// The live front-camera picture, filling its frame (edges cropped).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

/// Where a 0…1 picture point lands on screen when the picture fills `size`
/// the same way `CameraPreview` does (aspect fill, centred).
func previewPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
    let height = max(size.width / PoseCamera.pictureAspect, size.height)
    let width = height * PoseCamera.pictureAspect
    return CGPoint(
        x: (size.width - width) / 2 + point.x * width,
        y: (size.height - height) / 2 + point.y * height
    )
}
