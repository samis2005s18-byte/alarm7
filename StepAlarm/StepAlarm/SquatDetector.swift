import Foundation

/// Counts squats from body-pose measurements, one per camera frame.
///
/// Each frame gives `depth`: how high the hips are above the knees, in shin
/// lengths (hip-to-knee height ÷ knee-to-ankle height, see `PoseCamera`).
/// Standing up straight it's about 1; in a squat the thighs go level and it
/// drops toward 0. It works whether the person faces the camera or stands
/// side-on, because both views shrink the thighs' height as the hips go down.
///
/// A squat counts on the way back up: standing → below `downLevel` → above
/// `upLevel` again. The gap between the two levels stops a wobble at the top
/// or bottom from counting twice. Kept free of camera code so it can be tested
/// with simulated frames.
struct SquatDetector {
    struct Frame {
        var time: TimeInterval
        /// nil when the legs can't be seen in this frame.
        var depth: Double?
    }

    /// Counts as standing above this.
    static let upLevel = 0.75
    /// Low enough to count as a squat below this (thighs about 25° from level).
    static let downLevel = 0.45
    /// Fastest believable squat, from standing back to standing.
    static let minRepDuration: TimeInterval = 0.6
    /// Smoothing for the jittery per-frame pose (0…1, higher follows faster).
    static let smoothing = 0.5
    /// After this long without seeing legs, the smoothing starts over.
    static let lostAfter: TimeInterval = 1

    private(set) var count = 0
    private(set) var isDown = false
    /// True once the person has been seen standing — counting starts from there.
    private(set) var hasStood = false
    /// 0 = standing, 1 = low enough for a squat (drives the on-screen meter).
    private(set) var progress = 0.0

    private var smoothed: Double?
    private var lastSeen: TimeInterval = -.infinity
    /// When the current squat started (the last moment fully standing).
    private var repStart: TimeInterval = 0

    /// Returns 1 when this frame finishes a squat, otherwise 0.
    mutating func add(_ frame: Frame) -> Int {
        guard let depth = frame.depth, depth.isFinite else { return 0 }
        if frame.time - lastSeen > Self.lostAfter { smoothed = nil }
        lastSeen = frame.time
        let level = smoothed.map { $0 + Self.smoothing * (depth - $0) } ?? depth
        smoothed = level
        progress = min(1, max(0, (Self.upLevel - level) / (Self.upLevel - Self.downLevel)))

        guard hasStood else {
            if level > Self.upLevel {
                hasStood = true
                repStart = frame.time
            }
            return 0
        }
        if !isDown {
            if level > Self.upLevel { repStart = frame.time }
            if level < Self.downLevel { isDown = true }
            return 0
        }
        guard level > Self.upLevel else { return 0 }
        isDown = false
        let duration = frame.time - repStart
        repStart = frame.time
        guard duration >= Self.minRepDuration else { return 0 }
        count += 1
        return 1
    }
}
