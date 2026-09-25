import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftUI

/// "Lock apps after I wake up": once an alarm is walked off, the apps the
/// user chose stay locked (Screen Time shield) for the chosen time, then
/// unlock by themselves via the AppLockMonitor extension.
///
/// Apple only lets the user pick apps in its own picker; the app gets
/// private tokens (it never learns which apps they are) that it can show
/// with their real icon and name, and lock.
@MainActor @Observable
final class AppLocker {
    static let shared = AppLocker()

    /// Minutes the apps stay locked after waking.
    static let durations = [10, 15, 30, 60]

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "appLock.enabled"
        static let selection = "appLock.selection"
        static let minutes = "appLock.minutes"
        static let lockedUntil = "appLock.lockedUntil"
    }

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    var selection: FamilyActivitySelection {
        didSet {
            if let data = try? JSONEncoder().encode(selection) {
                defaults.set(data, forKey: Keys.selection)
            }
        }
    }
    var minutes: Int {
        didSet { defaults.set(minutes, forKey: Keys.minutes) }
    }
    /// When the current lock ends, or nil if nothing is locked.
    private(set) var lockedUntil: Date?

    var isAuthorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

    var hasApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    var isLocked: Bool { lockedUntil.map { $0 > .now } ?? false }

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        minutes = defaults.object(forKey: Keys.minutes) as? Int ?? 15
        if let data = defaults.data(forKey: Keys.selection),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
        lockedUntil = defaults.object(forKey: Keys.lockedUntil) as? Date
    }

    /// Shows Apple's one-time Screen Time permission prompt (Face ID).
    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            return false
        }
        return isAuthorized
    }

    /// Called right after an alarm is walked off (or emergency-stopped).
    func lockAfterWaking() {
        guard AppConfig.appLockEnabled, isEnabled, isAuthorized, hasApps else { return }

        let store = ManagedSettingsStore(named: .alarm7AppLock)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        let now = Date()
        let end = now.addingTimeInterval(Double(minutes * 60))
        lockedUntil = end
        defaults.set(end, forKey: Keys.lockedUntil)

        // The extension unlocks the apps when this window ends. Apple needs
        // the window to be at least 15 minutes long, so a shorter lock
        // starts the window a little in the past.
        let start = min(now, end.addingTimeInterval(-15 * 60))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(parts, from: start),
            intervalEnd: Calendar.current.dateComponents(parts, from: end),
            repeats: false
        )
        let center = DeviceActivityCenter()
        center.stopMonitoring([.alarm7AppLock])
        try? center.startMonitoring(.alarm7AppLock, during: schedule)
    }

    /// Backup for the extension: whenever Alarm7 opens after the lock time
    /// has passed, make sure the apps are unlocked.
    func unlockIfExpired() {
        guard let lockedUntil, lockedUntil <= .now else { return }
        ManagedSettingsStore(named: .alarm7AppLock).clearAllSettings()
        DeviceActivityCenter().stopMonitoring([.alarm7AppLock])
        self.lockedUntil = nil
        defaults.removeObject(forKey: Keys.lockedUntil)
    }
}

/// The "Lock apps" section in Settings.
struct AppLockSection: View {
    private var locker = AppLocker.shared
    @State private var showPicker = false
    @State private var permissionDenied = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { locker.isEnabled }, set: { on in Task { await setEnabled(on) } })) {
                Label("Lock apps after I wake up", systemImage: "lock.fill")
            }
            .tint(Theme.neutralActive)

            if locker.isEnabled {
                ForEach(Array(locker.selection.applicationTokens), id: \.self) { token in
                    Label(token)
                }
                ForEach(Array(locker.selection.categoryTokens), id: \.self) { token in
                    Label(token)
                }
                Button { showPicker = true } label: {
                    Label(locker.hasApps ? "Add or remove apps" : "Add apps", systemImage: "plus.circle.fill")
                }

                Picker(selection: Binding(get: { locker.minutes }, set: { locker.minutes = $0 })) {
                    ForEach(AppLocker.durations, id: \.self) { Text("\($0) min").tag($0) }
                } label: {
                    Label("Keep them locked for", systemImage: "hourglass")
                }

                if let until = locker.lockedUntil, locker.isLocked {
                    Label("Locked until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Lock apps")
        } footer: {
            if permissionDenied {
                Text("Alarm7 needs Screen Time access to lock apps. Turn it on in the Settings app under Screen Time.")
                    .foregroundStyle(Theme.accent)
            } else {
                Text("After you walk off your alarm, these apps stay locked for the time you choose, then unlock by themselves. Tip: tap Add apps and search for Instagram, Snapchat or TikTok.")
            }
        }
        .familyActivityPicker(
            isPresented: $showPicker,
            selection: Binding(get: { locker.selection }, set: { locker.selection = $0 })
        )
    }

    private func setEnabled(_ on: Bool) async {
        guard on else {
            locker.isEnabled = false
            return
        }
        if !locker.isAuthorized {
            guard await locker.requestAuthorization() else {
                permissionDenied = true
                return
            }
        }
        permissionDenied = false
        locker.isEnabled = true
        if !locker.hasApps { showPicker = true }
    }
}
