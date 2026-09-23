import AlarmKit
import SwiftUI

/// Everything AlarmKit can't hand back to us later when an alarm fires: its
/// step goal, label, and whether it's allowed to re-ring after Stop.
struct AlarmRingSettings: Codable {
    var stepGoal: Int
    var label: String
    var snoozeEnabled: Bool
    var vibrationEnabled: Bool
    var hour: Int
    var minute: Int
    /// Optional so settings saved by earlier versions still load.
    var emergencyStop: Bool?
}

/// Remembers each scheduled alarm's ring settings and which "re-ring"
/// alarms are pending.
enum AlarmGoals {
    private static let settingsKey = "stepalarm.ringSettings"
    private static let reRingKey = "stepalarm.reRings"

    static func set(_ settings: AlarmRingSettings, for id: UUID) {
        var all = load()
        all[id.uuidString] = settings
        save(all)
    }

    static func settings(for id: UUID) -> AlarmRingSettings? {
        load()[id.uuidString]
    }

    static func goal(for id: UUID) -> Int? {
        settings(for: id)?.stepGoal
    }

    static var reRingIDs: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: reRingKey) ?? []).compactMap(UUID.init) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: reRingKey) }
    }

    // MARK: Backup rings
    //
    // Every alarm is followed by pre-scheduled backup rings. They only get
    // cancelled once the steps are walked, so dismissing the system alert
    // (its X / Stop button) can't end the alarm on its own.

    private static let backupsKey = "stepalarm.backups"          // parent ID -> backup IDs
    private static let ringWindowsKey = "stepalarm.ringWindows"  // parent ID -> [start, end]

    static func backups(for parent: UUID) -> [UUID] {
        (backupMap()[parent.uuidString] ?? []).compactMap(UUID.init)
    }

    static func setBackups(_ ids: [UUID], for parent: UUID) {
        var map = backupMap()
        map[parent.uuidString] = ids.isEmpty ? nil : ids.map(\.uuidString)
        UserDefaults.standard.set(map, forKey: backupsKey)
    }

    /// The alarm a backup (or re-ring) belongs to.
    static func parent(of id: UUID) -> UUID? {
        backupMap().first { $0.value.contains(id.uuidString) }.flatMap { UUID(uuidString: $0.key) }
    }

    /// From the first ring until the last backup, the alarm counts as "ringing".
    static func setRingWindow(start: Date, end: Date, for parent: UUID) {
        var windows = ringWindows()
        windows[parent.uuidString] = [start.timeIntervalSince1970, end.timeIntervalSince1970]
        UserDefaults.standard.set(windows, forKey: ringWindowsKey)
    }

    static func clearRingWindow(for parent: UUID) {
        var windows = ringWindows()
        windows[parent.uuidString] = nil
        UserDefaults.standard.set(windows, forKey: ringWindowsKey)
    }

    static func isRinging(_ parent: UUID, now: Date = .now) -> Bool {
        guard let window = ringWindows()[parent.uuidString], window.count == 2 else { return false }
        let t = now.timeIntervalSince1970
        return t >= window[0] && t <= window[1]
    }

    /// An alarm that has started ringing and hasn't been walked off yet.
    static func ringingParent(now: Date = .now) -> UUID? {
        ringWindows().keys.compactMap(UUID.init).first { isRinging($0, now: now) }
    }

    private static func backupMap() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: backupsKey) as? [String: [String]] ?? [:]
    }

    private static func ringWindows() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: ringWindowsKey) as? [String: [Double]] ?? [:]
    }

    private static func load() -> [String: AlarmRingSettings] {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode([String: AlarmRingSettings].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ all: [String: AlarmRingSettings]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}

/// Wrapper around AlarmManager: authorization, scheduling, cancelling, and
/// the "re-ring" that fires if someone taps the system Stop button without
/// doing their steps (unless that alarm has snooze turned off).
///
/// NOTE: written without a macOS/Xcode toolchain to compile against the real
/// AlarmKit SDK. If Xcode disagrees with a name here (e.g. the
/// `AlarmConfiguration.alarm(...)` factory), trust Xcode's jump-to-definition.
@Observable
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private(set) var isAuthorized = false
    private(set) var lastError: String?

    /// Seconds before the alarm rings again after Stop is tapped without walking.
    static let reRingDelay: TimeInterval = 20
    /// Backup rings after each alarm: one every `backupInterval`, `backupCount` times.
    static let backupCount = 10
    static let backupInterval: TimeInterval = 60

    private static let weekdays: [Locale.Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    private init() {}

    func requestAuthorizationIfNeeded() async {
        do {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                isAuthorized = true
            case .notDetermined:
                let state = try await AlarmManager.shared.requestAuthorization()
                isAuthorized = (state == .authorized)
            default:
                isAuthorized = false
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Scheduling

    /// Schedules a saved alarm: once (next occurrence of hour:minute) or
    /// weekly on the chosen days.
    func schedule(_ item: AlarmItem) async {
        await cancelBackups(of: item.id)
        let time = Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute)
        let repeats: Alarm.Schedule.Relative.Recurrence =
            item.days.isEmpty ? .never : .weekly(item.days.sorted().map { Self.weekdays[$0] })
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: repeats))
        await submit(
            id: item.id, schedule: schedule, steps: item.steps, label: item.label,
            snoozeEnabled: item.snoozeEnabled, vibrationEnabled: item.vibrationEnabled,
            hour: item.hour, minute: item.minute, emergencyStop: item.emergencyStop
        )
        await scheduleBackups(for: item)
    }

    /// Test alarm: fires N seconds from now with a 15-step goal.
    func scheduleTestAlarm(secondsFromNow: TimeInterval = 120) async {
        let id = UUID()
        let fire = Date().addingTimeInterval(secondsFromNow)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fire)
        let hour = comps.hour ?? 0, minute = comps.minute ?? 0
        await submit(
            id: id, schedule: .fixed(fire), steps: 15, label: "", snoozeEnabled: true, vibrationEnabled: true,
            hour: hour, minute: minute
        )
        await scheduleBackups(
            parent: id, firstRing: fire, steps: 15, label: "", vibrationEnabled: true, hour: hour, minute: minute
        )
    }

    /// Queues the backup rings for an alarm's next occurrence.
    func scheduleBackups(for item: AlarmItem) async {
        guard let next = item.nextRingDate() else { return }
        await scheduleBackups(
            parent: item.id, firstRing: next, steps: item.steps, label: item.label,
            vibrationEnabled: item.vibrationEnabled, hour: item.hour, minute: item.minute,
            emergencyStop: item.emergencyStop
        )
    }

    private func scheduleBackups(
        parent: UUID, firstRing: Date, steps: Int, label: String, vibrationEnabled: Bool, hour: Int, minute: Int,
        emergencyStop: Bool = false
    ) async {
        await cancelBackups(of: parent)
        var ids: [UUID] = []
        for k in 1...Self.backupCount {
            let id = UUID()
            ids.append(id)
            await submit(
                id: id, schedule: .fixed(firstRing.addingTimeInterval(Double(k) * Self.backupInterval)),
                steps: steps, label: label, snoozeEnabled: true, vibrationEnabled: vibrationEnabled,
                hour: hour, minute: minute, emergencyStop: emergencyStop
            )
        }
        AlarmGoals.setBackups(ids, for: parent)
        let end = firstRing.addingTimeInterval(Double(Self.backupCount + 1) * Self.backupInterval)
        AlarmGoals.setRingWindow(start: firstRing, end: end, for: parent)
    }

    /// Removes an alarm's queued backup rings.
    func cancelBackups(of parent: UUID) async {
        for id in AlarmGoals.backups(for: parent) {
            try? await AlarmManager.shared.stop(id: id)
            try? await AlarmManager.shared.cancel(id: id)
        }
        AlarmGoals.setBackups([], for: parent)
        AlarmGoals.clearRingWindow(for: parent)
    }

    /// Steps walked: silence this alarm and everything queued to ring it again.
    func finishRinging(alarmID: UUID) async {
        let parent = AlarmGoals.parent(of: alarmID) ?? alarmID
        // Re-rings are listed among the parent's backups, so this silences
        // them too — without touching other alarms' re-rings.
        let silenced = Set(AlarmGoals.backups(for: parent))
        await stopAlarm(alarmID)
        await stopAlarm(parent)
        await cancelBackups(of: parent)
        AlarmGoals.reRingIDs.removeAll { silenced.contains($0) || $0 == alarmID }
    }

    /// Rings again shortly after the system Stop button was tapped.
    func scheduleReRing(
        parent: UUID, steps: Int, label: String, vibrationEnabled: Bool, hour: Int, minute: Int, emergencyStop: Bool
    ) async {
        let id = UUID()
        AlarmGoals.reRingIDs.append(id)
        AlarmGoals.setBackups(AlarmGoals.backups(for: parent) + [id], for: parent)
        let fire = Date().addingTimeInterval(Self.reRingDelay)
        await submit(
            id: id, schedule: .fixed(fire), steps: steps, label: label, snoozeEnabled: true,
            vibrationEnabled: vibrationEnabled, hour: hour, minute: minute, emergencyStop: emergencyStop
        )
    }

    private func submit(
        id: UUID, schedule: Alarm.Schedule, steps: Int, label: String, snoozeEnabled: Bool, vibrationEnabled: Bool,
        hour: Int, minute: Int, emergencyStop: Bool = false
    ) async {
        AlarmGoals.set(
            AlarmRingSettings(
                stepGoal: steps, label: label, snoozeEnabled: snoozeEnabled, vibrationEnabled: vibrationEnabled,
                hour: hour, minute: minute, emergencyStop: emergencyStop
            ),
            for: id
        )

        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let walkButton = AlarmButton(text: "Walk", textColor: .white, systemImageName: "figure.walk")

        let stepsText = "\(steps) \(steps == 1 ? "step" : "steps")"
        let title = label.isEmpty ? "Wake up! Walk \(stepsText)" : "\(label) — walk \(stepsText)"
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: walkButton,
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes<StepAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: StepAlarmMetadata(stepGoal: steps),
            tintColor: Theme.accent
        )

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id),
            secondaryIntent: WalkToStopIntent(alarmID: id)
        )

        do {
            try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Stopping

    /// Silences a ringing alarm. A repeating alarm keeps its schedule.
    func stopAlarm(_ id: UUID) async {
        try? await AlarmManager.shared.stop(id: id)
    }

    /// Removes an alarm entirely (used for deletes / switching off).
    func cancel(_ id: UUID) async {
        try? await AlarmManager.shared.stop(id: id)
        try? await AlarmManager.shared.cancel(id: id)
        await cancelBackups(of: id)
    }

    /// Silences and removes every pending re-ring alarm.
    func cancelReRings() async {
        for id in AlarmGoals.reRingIDs {
            await cancel(id)
        }
        AlarmGoals.reRingIDs = []
    }

    // MARK: - Queries

    /// IDs AlarmKit currently knows about (scheduled or ringing), or nil if
    /// the query failed.
    func systemAlarmIDs() -> Set<UUID>? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return Set(alarms.map(\.id))
    }

    /// Calls `onRing` whenever an alarm starts ringing while the app is open,
    /// so the Wake Up screen can take over instead of only the system banner.
    func watchForRinging(_ onRing: @escaping @MainActor (UUID) -> Void) async {
        for await alarms in AlarmManager.shared.alarmUpdates {
            if let ringing = alarms.first(where: { $0.state == .alerting }) {
                await onRing(ringing.id)
            }
        }
    }

    /// The alarm that is ringing right now, if any.
    func alertingAlarmID() -> UUID? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first(where: { $0.state == .alerting })?.id
    }
}
