import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftUI

/// "Lock apps after I wake up", set per alarm on the Add Alarm page: once
/// that alarm is walked off, the apps chosen for it stay locked (Screen Time
/// shield) for the chosen time, then unlock by themselves via the
/// AppLockMonitor extension.
///
/// Apple only lets the user pick apps in its own picker; the app gets
/// private tokens (it never learns which apps they are) that it can show
/// with their real icon and name, and lock.
@MainActor @Observable
final class AppLocker {
    static let shared = AppLocker()

    /// Minutes the apps stay locked after waking.
    static let durations = [10, 15, 30, 60]
    static let defaultMinutes = 15

    /// One alarm's app lock: which apps, and for how long.
    struct Plan: Codable, Equatable {
        var selection: FamilyActivitySelection
        var minutes: Int

        var hasApps: Bool {
            !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let plans = "appLock.plans"
        static let lockedUntil = "appLock.lockedUntil"
    }

    /// Alarm ID -> its app lock.
    private var plans: [String: Plan] {
        didSet {
            if let data = try? JSONEncoder().encode(plans) {
                defaults.set(data, forKey: Keys.plans)
            }
        }
    }
    /// When the current lock ends, or nil if nothing is locked.
    private(set) var lockedUntil: Date?

    var isAuthorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }

    var isLocked: Bool { lockedUntil.map { $0 > .now } ?? false }

    private init() {
        if let data = defaults.data(forKey: Keys.plans),
           let saved = try? JSONDecoder().decode([String: Plan].self, from: data) {
            plans = saved
        } else {
            plans = [:]
        }
        lockedUntil = defaults.object(forKey: Keys.lockedUntil) as? Date
    }

    func plan(for alarmID: UUID) -> Plan? {
        plans[alarmID.uuidString]
    }

    /// Saves (or with nil, removes) an alarm's app lock.
    func setPlan(_ plan: Plan?, for alarmID: UUID) {
        plans[alarmID.uuidString] = plan
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
    func lockAfterWaking(alarmID: UUID) {
        guard AppConfig.appLockEnabled, isAuthorized, let plan = plan(for: alarmID), plan.hasApps else { return }
        let selection = plan.selection

        let store = ManagedSettingsStore(named: .alarm7AppLock)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        let now = Date()
        let end = now.addingTimeInterval(Double(plan.minutes * 60))
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

/// "Lock apps after I wake up" on the Add Alarm page: pick apps (shown with
/// their real icons) and how long they stay locked after this alarm.
struct AppLockAlarmSection: View {
    @Binding var isOn: Bool
    @Binding var selection: FamilyActivitySelection
    @Binding var minutes: Int
    @State private var showPicker = false
    @State private var permissionDenied = false

    private var hasApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: { on in Task { await setOn(on) } })) {
                Label("Lock apps after I wake up", systemImage: "lock.fill")
            }
            .tint(Theme.neutralActive)

            if isOn {
                Button {
                    Theme.tap()
                    showPicker = true
                } label: {
                    chosenAppsRow
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(hasApps ? "\(chosenCount) apps chosen. Add or remove apps" : "Choose apps to lock")
                Picker(selection: $minutes) {
                    ForEach(AppLocker.durations, id: \.self) { Text("\($0) min").tag($0) }
                } label: {
                    Label("Apps open again after", systemImage: "hourglass")
                }
            }
        } footer: {
            if permissionDenied {
                Text("Alarm7 needs Screen Time access to lock apps. Turn it on in the Settings app under Screen Time.")
                    .foregroundStyle(Theme.accent)
            } else if isOn {
                Text("After you walk off this alarm, these apps stay locked for the time you choose, then open again by themselves. Tip: search for Instagram, TikTok or Facebook, or open the Social group.")
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
    }

    /// Apps first, then categories (e.g. "Social") — these are what the row's
    /// icon stack draws from.
    private enum Chosen: Hashable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)
    }

    private var chosen: [Chosen] {
        selection.applicationTokens.map(Chosen.app) + selection.categoryTokens.map(Chosen.category)
    }

    private var chosenCount: Int { chosen.count + selection.webDomainTokens.count }

    private static let visibleIcons = 3
    private static let iconSize: CGFloat = 34

    /// One tappable row: the first few chosen apps as overlapping real icons
    /// (Instagram, TikTok, Snapchat…), "•••" when there are more, and a "+"
    /// that says more can be added. Tapping anywhere opens Apple's picker.
    private var chosenAppsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: -10) {
                if hasApps {
                    ForEach(chosen.prefix(Self.visibleIcons), id: \.self) { item in
                        chosenIcon(item)
                    }
                    if chosenCount > Self.visibleIcons {
                        iconBubble { Image(systemName: "ellipsis").font(.subheadline.weight(.bold)) }
                    }
                }
                iconBubble { Image(systemName: "plus").font(.subheadline.weight(.bold)) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(hasApps ? "\(chosenCount) \(chosenCount == 1 ? "app" : "apps") to lock" : "Choose apps to lock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(hasApps ? "Tap to add or remove" : "Instagram, TikTok, Snapchat…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textDisabled)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func chosenIcon(_ item: Chosen) -> some View {
        Group {
            switch item {
            case .app(let token): Label(token)
            case .category(let token): Label(token)
            }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: Self.iconSize * 0.8))
        .frame(width: Self.iconSize, height: Self.iconSize)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
    }

    private func iconBubble(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .foregroundStyle(Theme.textPrimary)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(Color(.tertiarySystemFill), in: Circle())
            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
    }

    private func setOn(_ on: Bool) async {
        guard on else {
            isOn = false
            return
        }
        if !AppLocker.shared.isAuthorized {
            guard await AppLocker.shared.requestAuthorization() else {
                permissionDenied = true
                return
            }
        }
        permissionDenied = false
        isOn = true
        if !hasApps { showPicker = true }
    }
}
