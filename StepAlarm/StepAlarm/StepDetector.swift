import Foundation

/// Counts steps straight from ~50 Hz motion samples, the moment each foot
/// lands, and rejects a phone being shaken.
///
/// A step shows up as one up-and-down bump in *vertical* acceleration
/// (along gravity), in a steady rhythm of roughly 1–3 steps a second.
/// Shaking is usually sideways or twisting, faster, or much harder — so a
/// bump only counts if it's vertical, gentle, low-rotation, and part of a
/// steady rhythm. Counting starts once `rhythmSteps` bumps in a row look
/// like walking; those are then credited at once and every later step
/// counts instantly.
struct StepDetector {
    struct Sample {
        /// Seconds (any fixed origin, e.g. `CMDeviceMotion.timestamp`).
        var time: TimeInterval
        /// User acceleration along gravity, in g (up is positive).
        var vertical: Double
        /// Rotation rate magnitude, in rad/s.
        var rotation: Double
    }

    // Tuning
    static let smoothing = 0.3            // low-pass factor per 50 Hz sample
    static let peakThreshold = 0.06       // g — smallest bump that can be a step
    static let rearmThreshold = 0.0       // g — signal must drop back below this between steps
    static let maxPeak = 1.0              // g — harder jolts are shaking
    static let maxRotation = 4.0          // rad/s averaged over ~0.5 s — more is twisting/shaking
    static let minInterval = 0.3          // s — faster than this (over ~3.3 steps/s) isn't a step
    static let maxInterval = 1.5          // s — slower than this breaks the rhythm
    static let rhythmSteps = 4            // steps in a row before counting starts
    static let maxIntervalRatio = 1.6     // longest/shortest gap allowed while finding the rhythm
    static let maxRhythmDrift = 0.4       // once counting, each gap must stay within ±40% of the average
    static let fastPeaksForShake = 2      // this many too-fast bumps within `fastPeakWindow` = shaking
    static let fastPeakWindow = 2.0       // s

    private(set) var rejectedShakes = 0

    private var smoothed = 0.0
    private var armed = true
    private var inPeak = false
    private var peak = 0.0
    private var peakTime: TimeInterval = 0
    private var recentRotation: [Double] = []
    private var lastStepTime: TimeInterval?
    private var pending = 0
    private var intervals: [Double] = []
    private var counting = false
    private var averageInterval = 0.0
    private var fastPeakTimes: [TimeInterval] = []

    /// Feeds one sample; returns how many steps became newly counted.
    mutating func add(_ sample: Sample) -> Int {
        smoothed += Self.smoothing * (sample.vertical - smoothed)
        recentRotation.append(sample.rotation)
        if recentRotation.count > 25 { recentRotation.removeFirst(recentRotation.count - 25) }

        if inPeak {
            if smoothed > peak {
                peak = smoothed
                peakTime = sample.time
            }
            if smoothed < peak * 0.5 {
                inPeak = false
                armed = false
                return candidate(at: peakTime, amplitude: peak)
            }
            return 0
        }
        if !armed {
            if smoothed < Self.rearmThreshold { armed = true }
            return 0
        }
        if smoothed > Self.peakThreshold {
            inPeak = true
            peak = smoothed
            peakTime = sample.time
        }
        return 0
    }

    private mutating func candidate(at time: TimeInterval, amplitude: Double) -> Int {
        let meanRotation = recentRotation.reduce(0, +) / Double(max(recentRotation.count, 1))
        if amplitude > Self.maxPeak || meanRotation > Self.maxRotation {
            rejectShake()
            return 0
        }
        guard let last = lastStepTime else {
            startRhythm(at: time)
            return 0
        }
        let interval = time - last
        if interval < Self.minInterval {
            // An occasional double bump within one step is normal; a run of
            // them is a phone being shaken.
            fastPeakTimes.append(time)
            fastPeakTimes.removeAll { time - $0 > Self.fastPeakWindow }
            if fastPeakTimes.count >= Self.fastPeaksForShake { rejectShake() }
            return 0
        }
        if interval > Self.maxInterval {
            startRhythm(at: time)
            return 0
        }
        if counting {
            // Real walking keeps a steady beat; a sudden change restarts the rhythm check.
            guard abs(interval - averageInterval) <= averageInterval * Self.maxRhythmDrift else {
                startRhythm(at: time)
                return 0
            }
            lastStepTime = time
            averageInterval += 0.3 * (interval - averageInterval)
            return 1
        }
        lastStepTime = time

        intervals.append(interval)
        pending += 1
        guard pending >= Self.rhythmSteps else { return 0 }
        if let shortest = intervals.min(), let longest = intervals.max(), longest / shortest <= Self.maxIntervalRatio {
            counting = true
            averageInterval = intervals.reduce(0, +) / Double(intervals.count)
            let credited = pending
            pending = 0
            intervals = []
            return credited
        }
        // Not steady yet — slide the window forward.
        intervals.removeFirst()
        pending -= 1
        return 0
    }

    private mutating func startRhythm(at time: TimeInterval) {
        lastStepTime = time
        pending = 1
        intervals = []
        counting = false
    }

    private mutating func rejectShake() {
        rejectedShakes += 1
        lastStepTime = nil
        pending = 0
        intervals = []
        counting = false
        fastPeakTimes = []
    }
}
