import AppIntents
import AlarmKit

/// Runs in-process (no UI) when the alarm's system Stop button is tapped.
/// Stopping without walking isn't allowed to "win" by default: the alarm is
/// silenced now and rings again after `AlarmScheduler.reRingDelay` seconds
/// — unless that alarm has Snooze turned off, in which case Stop silences it
/// for good (a stricter, no-snooze alarm). Walking the steps is what really
/// ends it either way — that silences the alarm directly and never goes
/// through this intent.
///
/// NOTE: exact protocol requirements for AlarmKit's button intents
/// (`LiveActivityIntent`) come from Apple's WWDC25 AlarmKit session and
/// sample code; verify against Xcode 26's jump-to-definition.
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"

    @Parameter(title: "alarmID")
    var alarmIDString: String

    init() {}

    init(alarmID: UUID) {
        self.alarmIDString = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmIDString) {
            try? await AlarmManager.shared.stop(id: id)
            let settings = AlarmGoals.settings(for: id)
            if settings?.snoozeEnabled ?? true {
                await AlarmScheduler.shared.scheduleReRing(
                    parent: AlarmGoals.parent(of: id) ?? id,
                    steps: settings?.stepGoal ?? 15,
                    label: settings?.label ?? "",
                    vibrationEnabled: settings?.vibrationEnabled ?? true,
                    hour: settings?.hour ?? 7,
                    minute: settings?.minute ?? 0
                )
            }
        }
        return .result()
    }
}

/// The alarm's "Walk" button: opens the app on the Wake Up screen and starts
/// counting steps for that alarm.
struct WalkToStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Walk to Stop"
    static let openAppWhenRun = true

    @Parameter(title: "alarmID")
    var alarmIDString: String

    init() {}

    init(alarmID: UUID) {
        self.alarmIDString = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmIDString) {
            WalkSession.shared.begin(alarmID: id)
        }
        return .result()
    }
}
