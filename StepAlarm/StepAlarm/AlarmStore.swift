import Foundation
import Observation

/// One saved alarm. `days` uses 0 = Sunday … 6 = Saturday; empty = ring once.
struct AlarmItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var steps: Int = 15
    var days: Set<Int> = []
    var isOn: Bool = true
    var label: String = ""
    /// If false, tapping the ringing alert's Stop button silences it for
    /// good instead of re-ringing later — a stricter, no-snooze alarm.
    var snoozeEnabled: Bool = true
    /// Gates the app's own haptic ticks during this alarm's Wake Up screen.
    /// (The alarm's actual ring/vibration is controlled by iOS itself —
    /// AlarmKit doesn't expose a per-alarm vibration switch.)
    var vibrationEnabled: Bool = true
    /// Cosmetic only for now — not yet wired into AlarmKit's actual alert
    /// sound. See AddAlarmView's sound row for why.
    var soundName: String = "Default"

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, steps, days, isOn, label, snoozeEnabled, vibrationEnabled, soundName
    }

    init(
        id: UUID = UUID(), hour: Int, minute: Int, steps: Int = 15, days: Set<Int> = [],
        isOn: Bool = true, label: String = "", snoozeEnabled: Bool = true, vibrationEnabled: Bool = true,
        soundName: String = "Default"
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.steps = steps
        self.days = days
        self.isOn = isOn
        self.label = label
        self.snoozeEnabled = snoozeEnabled
        self.vibrationEnabled = vibrationEnabled
        self.soundName = soundName
    }

    /// Custom decode so alarms saved before a field existed still load
    /// instead of throwing and silently wiping the saved list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 15
        days = try c.decodeIfPresent(Set<Int>.self, forKey: .days) ?? []
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        snoozeEnabled = try c.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? true
        vibrationEnabled = try c.decodeIfPresent(Bool.self, forKey: .vibrationEnabled) ?? true
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? "Default"
    }

    static func new(defaultSteps: Int = 15) -> AlarmItem {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return AlarmItem(hour: now.hour ?? 7, minute: now.minute ?? 0, steps: defaultSteps)
    }

    /// Today at this alarm's hour/minute — used only for display and the wheel.
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    var stepsText: String { "\(steps) \(steps == 1 ? "step" : "steps")" }
    var repeatText: String { days.isEmpty ? "Once" : Self.repeatSummary(days) }

    /// The next date/time this alarm will actually ring, or nil if it's off.
    /// `days` is 0 = Sunday … 6 = Saturday, matching `Calendar.component(.weekday, ...) - 1`.
    func nextRingDate(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isOn else { return nil }
        if days.isEmpty {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let candidate = calendar.date(from: comps) else { return nil }
            return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        for dayOffset in 0..<8 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: candidateDay) - 1
            guard days.contains(weekday) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let candidate = calendar.date(from: comps), candidate > now else { continue }
            return candidate
        }
        return nil
    }

    /// "in 7h 12m" — used for the save toast and the list's next-alarm card.
    static func countdownText(to date: Date, from now: Date = .now) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "in under a minute" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        switch (hours, minutes) {
        case (0, 0): return "in under a minute"
        case (0, _): return "in \(minutes)m"
        case (_, 0): return "in \(hours)h"
        default: return "in \(hours)h \(minutes)m"
        }
    }

    var detail: String {
        var text = "Alarm, \(steps) \(steps == 1 ? "step" : "steps")"
        if !days.isEmpty { text += ", " + Self.repeatSummary(days) }
        return text
    }

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// "Never", "Every day", "Tue and Sat", "Mon, Wed and Fri".
    static func repeatSummary(_ days: Set<Int>) -> String {
        let names = days.sorted().map { dayNames[$0] }
        switch names.count {
        case 0: return "Never"
        case 7: return "Every day"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

/// The saved alarm list. Every change is persisted and mirrored into AlarmKit
/// (schedule when on, cancel when off or deleted).
@MainActor @Observable
final class AlarmStore {
    static let shared = AlarmStore()

    /// Free tier: up to this many alarms, all one-time (repeat is Pro-only).
    static let freeAlarmLimit = 3

    private(set) var alarms: [AlarmItem] = []
    private let key = "stepalarm.alarms.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AlarmItem].self, from: data) {
            alarms = saved
        }
    }

    func isSaved(_ id: UUID) -> Bool {
        alarms.contains { $0.id == id }
    }

    func upsert(_ item: AlarmItem) async {
        if let i = alarms.firstIndex(where: { $0.id == item.id }) {
            alarms[i] = item
        } else {
            alarms.append(item)
        }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        save()
        await sync(item)
    }

    func setEnabled(_ id: UUID, _ isOn: Bool) async {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].isOn = isOn
        save()
        await sync(alarms[i])
    }

    func delete(_ id: UUID) async {
        alarms.removeAll { $0.id == id }
        save()
        await AlarmScheduler.shared.cancel(id)
    }

    /// If Pro has lapsed (subscription period actually ended — `isPro`
    /// already stays true until then), repeating alarms turn into one-time
    /// alarms instead of being deleted or quietly continuing to repeat for
    /// free. Call this whenever the app becomes active.
    func downgradeRepeatingAlarmsIfNeeded() async {
        guard !SubscriptionStore.shared.hasFullAccess else { return }
        var toReschedule: [AlarmItem] = []
        for i in alarms.indices where !alarms[i].days.isEmpty {
            alarms[i].days = []
            if alarms[i].isOn { toReschedule.append(alarms[i]) }
        }
        guard !toReschedule.isEmpty else { return }
        save()
        for item in toReschedule {
            await AlarmScheduler.shared.schedule(item)
        }
    }

    /// One-time alarms that already rang are gone from AlarmKit, so flip them
    /// off here; repeating alarms that went missing get scheduled again.
    func refreshFromSystem() async {
        guard let live = AlarmScheduler.shared.systemAlarmIDs() else { return }
        for item in alarms where item.isOn && !live.contains(item.id) {
            if item.days.isEmpty {
                if let i = alarms.firstIndex(where: { $0.id == item.id }) { alarms[i].isOn = false }
            } else {
                await AlarmScheduler.shared.schedule(item)
            }
        }
        // Repeating alarms need their backup rings queued for the next occurrence.
        for item in alarms where item.isOn && !item.days.isEmpty && AlarmGoals.backups(for: item.id).isEmpty {
            await AlarmScheduler.shared.scheduleBackups(for: item)
        }
        save()
    }

    private func sync(_ item: AlarmItem) async {
        if item.isOn {
            await AlarmScheduler.shared.schedule(item)
        } else {
            await AlarmScheduler.shared.cancel(item.id)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Next alarm

    /// "Next alarm in 7h 12m", or nil when nothing is on.
    var nextAlarmDescription: String? {
        guard let next = alarms.compactMap({ $0.nextRingDate() }).min() else { return nil }
        return "Next alarm " + AlarmItem.countdownText(to: next)
    }
}
