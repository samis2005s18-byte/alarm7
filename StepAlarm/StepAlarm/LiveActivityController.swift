import ActivityKit
import Foundation

/// Throwaway Phase-1 validation, per the design spec: proves (or disproves)
/// whether a Live Activity's Lock Screen content can be updated roughly
/// once per second while the app is backgrounded/locked. This is the
/// single highest-risk unknown in the design spec — do not build the real
/// black/white/red ringing screen until this comes back positive on a
/// real device.
///
/// Two separate tests, on purpose:
///   - startCounterOnlyTest: a plain Live Activity, nothing to do with
///     AlarmKit. Proves whether Lock Screen live-updates work at all.
///   - startCombinedWithAlarmTest: the same, fired alongside an actual
///     AlarmKit alarm. Proves whether the two coexist, or whether
///     AlarmKit's own full-screen alert takes over and hides this.
///
/// A third thing this will reveal almost as a side effect: whether a
/// plain `Task.sleep` loop keeps running once iOS suspends the app in the
/// background. If the counter freezes the moment you lock the phone, that
/// tells us updates need to be driven by CoreMotion's own step-delivery
/// callback instead (which is designed to briefly wake a suspended app),
/// not by a timer loop sitting in the app process.
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<StepAlarmActivityAttributes>?
    private var tickTask: Task<Void, Never>?
    private(set) var lastError: String?
    private(set) var statusMessage: String = "Idle"

    private init() {}

    /// Test A. Tap this, then lock the phone immediately, and watch the
    /// Lock Screen: does "n / 15" actually count up once per second, or
    /// does it freeze as soon as the screen locks?
    func startCounterOnlyTest(stepGoal: Int = 15, durationSeconds: Int = 30) {
        startTicking(stepGoal: stepGoal, durationSeconds: durationSeconds)
    }

    /// Test B. Schedules the same Phase-1 AlarmKit test alarm AND starts
    /// the counter-only test at the same moment, so you can observe
    /// whether the live count is visible while the AlarmKit alert is
    /// actually ringing on the Lock Screen.
    func startCombinedWithAlarmTest(stepGoal: Int = 15, alarmSecondsFromNow: TimeInterval = 30) async {
        await AlarmScheduler.shared.scheduleTestAlarm(secondsFromNow: alarmSecondsFromNow)
        startTicking(stepGoal: stepGoal, durationSeconds: Int(alarmSecondsFromNow) + 30)
    }

    private func startTicking(stepGoal: Int, durationSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities not enabled — check Settings > Alarm7 > Live Activities."
            return
        }

        let attributes = StepAlarmActivityAttributes(alarmID: UUID().uuidString)
        let initialState = StepAlarmActivityAttributes.ContentState(stepCount: 0, stepGoal: stepGoal)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            lastError = nil
            statusMessage = "Live Activity started — lock the phone now."
        } catch {
            lastError = error.localizedDescription
            return
        }

        tickTask?.cancel()
        tickTask = Task { [weak self] in
            guard let self else { return }
            for tick in 1...durationSeconds {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let activity = self.activity else { return }
                let newState = StepAlarmActivityAttributes.ContentState(
                    stepCount: min(tick, stepGoal),
                    stepGoal: stepGoal
                )
                await activity.update(.init(state: newState, staleDate: nil))
                self.statusMessage = "Tick \(tick): sent stepCount=\(min(tick, stepGoal))"
            }
        }
    }

    func endTest() {
        tickTask?.cancel()
        Task {
            await activity?.end(nil, dismissalPolicy: .immediate)
            activity = nil
            statusMessage = "Ended"
        }
    }
}
