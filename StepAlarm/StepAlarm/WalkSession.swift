import CoreMotion
import Observation
import UIKit

/// The "walk to dismiss" logic. While a session is active the Wake Up screen
/// is shown, real steps are counted with CMPedometer, and reaching the goal
/// silences the alarm. `beginDemo` runs the same flow with simulated steps
/// and no alarm, so the screen can be tried without waiting for a ring.
@MainActor @Observable
final class WalkSession {
    static let shared = WalkSession()

    private(set) var isActive = false
    private(set) var isComplete = false
    private(set) var isDemo = false
    private(set) var steps = 0
    private(set) var goal = 15
    private(set) var label = ""
    private(set) var lastStepDate: Date?
    private(set) var motionMessage: String?

    /// Snapshot taken at the moment of completion, for the "Set again for
    /// tomorrow?" offer — `alarmID` itself doesn't survive `close()`.
    private(set) var completedAlarmID: UUID?
    private(set) var completedAlarmHour = 7
    private(set) var completedAlarmMinute = 0

    private var alarmID: UUID?
    private var hour = 7
    private var minute = 0
    private var vibrationEnabled = true
    private var startDate = Date()
    private var demoTask: Task<Void, Never>?
    @ObservationIgnored private let pedometer = CMPedometer()
    /// Tells real walking/running apart from a phone being shaken in place —
    /// only steps taken while iOS says you're on foot are counted.
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    /// The pedometer's own count this session, before walk verification.
    private(set) var rawSteps = 0
    private var detectedActivity = "…"
    @ObservationIgnored private var isOnFoot = false
    /// Pedometer steps waiting for iOS to confirm the user is walking.
    @ObservationIgnored private var heldSteps: [(date: Date, count: Int)] = []

    /// iOS needs several seconds of walking before it reports "walking", so
    /// steps from just before that moment still count.
    private static let recognitionLeadIn: TimeInterval = 15
    private static var canVerifyWalking: Bool { CMMotionActivityManager.isActivityAvailable() }

    private init() {}

    // MARK: - Starting

    /// Called when the alarm's "Walk" button is tapped, or when the app opens
    /// while an alarm is ringing.
    func begin(alarmID: UUID) {
        guard !isActive else { return }
        let settings = AlarmGoals.settings(for: alarmID)
        start(
            alarmID: alarmID, goal: settings?.stepGoal ?? 15, label: settings?.label ?? "",
            vibrationEnabled: settings?.vibrationEnabled ?? true,
            hour: settings?.hour ?? 7, minute: settings?.minute ?? 0, demo: false
        )
    }

    func beginDemo(goal: Int = 15) {
        guard !isActive else { return }
        start(alarmID: nil, goal: goal, label: "", vibrationEnabled: true, hour: 7, minute: 0, demo: true)
    }

    /// If an alarm is ringing while the app comes to the foreground, go
    /// straight to the walking screen.
    func resumeIfAlarmRinging() {
        guard !isActive, let id = AlarmScheduler.shared.alertingAlarmID() ?? AlarmGoals.ringingParent() else { return }
        begin(alarmID: id)
    }

    /// Triggers the Motion & Fitness permission prompt early, not mid-alarm.
    func requestMotionPermission() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { @Sendable _, _ in }
    }

    /// Same prompt, awaitable — used by onboarding, which needs to know
    /// whether access was actually granted before moving on.
    func requestMotionAuthorization() async -> Bool {
        guard CMPedometer.isStepCountingAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { @Sendable _, _ in
                Task { @MainActor in
                    continuation.resume(returning: CMPedometer.authorizationStatus() == .authorized)
                }
            }
        }
    }

    private func start(alarmID: UUID?, goal: Int, label: String, vibrationEnabled: Bool, hour: Int, minute: Int, demo: Bool) {
        self.alarmID = alarmID
        self.goal = goal
        self.label = label
        self.vibrationEnabled = vibrationEnabled
        self.hour = hour
        self.minute = minute
        self.isDemo = demo
        steps = 0
        lastStepDate = nil
        motionMessage = nil
        isComplete = false
        completedAlarmID = nil
        startDate = Date()
        isActive = true
        UIApplication.shared.isIdleTimerDisabled = true

        if demo {
            demoTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let self, !Task.isCancelled else { return }
                    self.apply(count: self.steps + 1, error: nil)
                }
            }
        } else {
            // Tapping "Walk" dismisses the system alarm, so keep it audible here
            // until the steps are done.
            AlarmSound.shared.start()
            startPedometer()
        }
    }

    // MARK: - Counting
    //
    // The pedometer alone also counts a phone being shaken, so its steps are
    // only credited while iOS's live motion detection says the user is on
    // foot. iOS takes a few seconds to recognise walking, so steps from just
    // before that moment are held and credited once it does; if iOS instead
    // says the phone is standing still, the held steps are thrown away.

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else {
            motionMessage = "Step counting isn't available on this device."
            return
        }
        rawSteps = 0
        heldSteps = []
        isOnFoot = false
        detectedActivity = "…"
        pedometer.startUpdates(from: startDate) { @Sendable [weak self] data, error in
            let count = data?.numberOfSteps.intValue
            let message = error?.localizedDescription
            Task { @MainActor in self?.handlePedometerUpdate(rawCount: count, error: message) }
        }
        if Self.canVerifyWalking {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                Task { @MainActor in self?.handleActivity(activity) }
            }
        }
    }

    private func handlePedometerUpdate(rawCount: Int?, error: String?) {
        if let error {
            apply(count: nil, error: error)
            return
        }
        guard let rawCount, rawCount > rawSteps else { return }
        let delta = rawCount - rawSteps
        rawSteps = rawCount
        if !Self.canVerifyWalking || isOnFoot {
            credit(delta)
        } else {
            heldSteps.append((Date(), delta))
        }
    }

    private func handleActivity(_ activity: CMMotionActivity) {
        isOnFoot = activity.walking || activity.running
        detectedActivity = Self.describe(activity)
        if isOnFoot {
            // Credit the steps taken while iOS was still recognising the walk.
            let cutoff = Date().addingTimeInterval(-Self.recognitionLeadIn)
            credit(heldSteps.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.count })
            heldSteps = []
        } else if activity.stationary && activity.confidence != .low {
            heldSteps = []
        }
    }

    private func credit(_ count: Int) {
        guard count > 0 else { return }
        // Never more than the pedometer itself has counted.
        apply(count: min(steps + count, rawSteps), error: nil)
    }

    /// Temporary on-screen diagnostics while walk detection is being tuned.
    var diagnostics: String {
        guard isActive, !isDemo else { return "" }
        return "Detected: \(detectedActivity) · phone steps: \(rawSteps)"
    }

    private static func describe(_ activity: CMMotionActivity) -> String {
        let kind = activity.running ? "running" : activity.walking ? "walking"
            : activity.stationary ? "standing still" : activity.automotive ? "in a vehicle"
            : activity.cycling ? "cycling" : "unknown"
        let confidence = activity.confidence == .high ? "high" : activity.confidence == .medium ? "medium" : "low"
        return "\(kind) (\(confidence))"
    }

    /// Steps taken while the app was suspended (phone locked) are read back
    /// from history when the app returns to the foreground: only steps inside
    /// time ranges iOS recorded as walking or running count.
    func refresh() {
        guard isActive, !isDemo, CMPedometer.isStepCountingAvailable() else { return }
        let sessionStart = startDate
        Task {
            let now = Date()
            let total = await querySteps(from: sessionStart, to: now)
            rawSteps = max(rawSteps, total)
            guard Self.canVerifyWalking else {
                apply(count: total, error: nil)
                return
            }
            // Look back a bit so an activity already in progress at the start is included.
            let activities = await queryActivities(from: sessionStart.addingTimeInterval(-600), to: now)
            var verified = 0
            for interval in Self.onFootIntervals(activities, sessionStart: sessionStart, now: now) {
                verified += await querySteps(from: interval.start, to: interval.end)
            }
            apply(count: min(verified, rawSteps), error: nil)
        }
    }

    /// Merged time ranges (within this session) during which the user was on foot.
    private static func onFootIntervals(_ activities: [CMMotionActivity], sessionStart: Date, now: Date) -> [DateInterval] {
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        var result: [DateInterval] = []
        for (i, activity) in sorted.enumerated() where activity.walking || activity.running {
            let end = i + 1 < sorted.count ? sorted[i + 1].startDate : now
            let start = max(sessionStart, activity.startDate.addingTimeInterval(-recognitionLeadIn))
            guard end > start else { continue }
            if let last = result.last, start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, end))
            } else {
                result.append(DateInterval(start: start, end: end))
            }
        }
        return result
    }

    private func queryActivities(from: Date, to: Date) async -> [CMMotionActivity] {
        await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: from, to: to, to: .main) { activities, _ in
                continuation.resume(returning: activities ?? [])
            }
        }
    }

    private func querySteps(from: Date, to: Date) async -> Int {
        await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: from, to: to) { @Sendable data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
            }
        }
    }

    private func apply(count: Int?, error: String?) {
        guard isActive, !isComplete else { return }
        if let error {
            motionMessage = "Allow Motion & Fitness access in Settings. (\(error))"
        }
        if let count, count > steps {
            motionMessage = nil
            steps = count
            lastStepDate = Date()
            if vibrationEnabled { Theme.tap() }
        }
        if steps >= goal { complete() }
    }

    /// A short line that reacts to progress, shown under the step ring.
    var progressStatus: String {
        if isComplete { return "You're up ☀️" }
        if steps == 0 { return "Start walking…" }
        let ratio = Double(steps) / Double(max(goal, 1))
        return ratio < 0.5 ? "Nice, keep going!" : "Almost there!"
    }

    // MARK: - Finishing

    /// Goal reached: silence the alarm, show the success state briefly, close.
    /// Free-tier alarms are always one-time (repeat is Pro-only), so a real,
    /// non-demo completion gets a longer dwell time here — long enough to
    /// tap "Set again for tomorrow?" on the Wake Up screen before it closes
    /// on its own.
    private func complete() {
        guard !isComplete else { return }
        isComplete = true
        // A backup ring belongs to the saved alarm it re-rings for.
        completedAlarmID = alarmID.map { AlarmGoals.parent(of: $0) ?? $0 }
        completedAlarmHour = hour
        completedAlarmMinute = minute
        Theme.success()
        stopCounting()
        let id = alarmID
        let demo = isDemo
        let showsOffer = !demo && !SubscriptionStore.shared.isPro
        Task {
            if !demo, let id {
                let parent = AlarmGoals.parent(of: id) ?? id
                await AlarmScheduler.shared.finishRinging(alarmID: id)
                // A repeating alarm needs its backup rings queued again for next time.
                if let item = AlarmStore.shared.alarms.first(where: { $0.id == parent }), item.isOn, !item.days.isEmpty {
                    await AlarmScheduler.shared.scheduleBackups(for: item)
                }
            }
            try? await Task.sleep(for: .seconds(showsOffer ? 6 : 2))
            close()
        }
    }

    /// Lets the Wake Up screen close immediately once the user has made a
    /// choice on the "Set again for tomorrow?" offer, instead of waiting
    /// out the rest of the dwell time.
    func finishNow() {
        close()
    }

    private func stopCounting() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        AlarmSound.shared.stop()
        demoTask?.cancel()
        demoTask = nil
    }

    private func close() {
        AlarmSound.shared.stop()
        isActive = false
        isComplete = false
        alarmID = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
