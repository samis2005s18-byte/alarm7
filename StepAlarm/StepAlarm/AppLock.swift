import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftUI
import UIKit

/// "Lock apps after you wake up", set per alarm on the Add Alarm page: once
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
    /// The stops on the lock-time slider (1 minute to 1 hour).
    static let durations = [1, 5, 10, 15, 20, 30, 45, 60]
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
        guard AppConfig.appLockEnabled, SubscriptionStore.shared.hasPremium, isAuthorized, let plan = plan(for: alarmID), plan.hasApps else { return }
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

/// "Lock apps after you wake up" on the Add Alarm page. It's the one Premium
/// feature: sample icons show what it does, turning it on asks free users to
/// upgrade first, then asks for Screen Time access and opens Apple's picker.
struct AppLockAlarmSection: View {
    @Binding var isOn: Bool
    @Binding var selection: FamilyActivitySelection
    @Binding var minutes: Int
    @State private var showPicker = false
    @State private var showPaywall = false
    /// Turning on is waiting for the user to finish on the Premium page.
    @State private var turnOnAfterPaywall = false
    @State private var permissionDenied = false

    private var hasPremium: Bool { SubscriptionStore.shared.hasPremium }

    private var hasApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: { on in Task { await setOn(on) } })) {
                Label("Lock apps after you wake up", systemImage: "lock.fill")
            }
            .tint(Theme.neutralActive)

            Button {
                Theme.tap()
                if isOn { showPicker = true } else { Task { await setOn(true) } }
            } label: {
                chosenAppsRow
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(hasApps ? "\(chosenCount) apps chosen. Add or remove apps" : "Choose apps to lock")

            durationBar
        } header: {
            if !hasPremium { PremiumBadge() }
        } footer: {
            if permissionDenied {
                Text("Alarm7 needs Screen Time access to lock apps. Turn it on in the Settings app under Screen Time.")
                    .foregroundStyle(Theme.accent)
            } else if !hasPremium {
                Text("App Lock is Premium: lock any apps you choose for 1 minute to 1 hour after you wake up. Everything else in Alarm7 is free.")
            } else if isOn {
                Text("After you walk off this alarm, these apps stay locked for the time you choose, then open again by themselves. Tip: search for Instagram, TikTok or Snapchat, or open the Social group.")
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .sheet(isPresented: $showPaywall, onDismiss: {
            guard turnOnAfterPaywall else { return }
            turnOnAfterPaywall = false
            if hasPremium { Task { await setOn(true) } }
        }) {
            PaywallView { showPaywall = false }
        }
    }

    // MARK: - Chosen apps

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

    /// One tappable row. Before any apps are picked it shows sample icons
    /// (Instagram, TikTok, Snapchat) so it's clear what this does; after,
    /// the first few chosen apps as overlapping real icons, "•••" when there
    /// are more, and a "+". Tapping opens Apple's picker (or turns it on).
    private var chosenAppsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isOn && hasApps {
                HStack(spacing: -10) {
                    ForEach(chosen.prefix(Self.visibleIcons), id: \.self) { item in
                        chosenIcon(item)
                    }
                    if chosenCount > Self.visibleIcons {
                        iconBubble { Image(systemName: "ellipsis").font(.subheadline.weight(.bold)) }
                    }
                    iconBubble { Image(systemName: "plus").font(.subheadline.weight(.bold)) }
                }
            } else {
                SampleAppIcons(size: Self.iconSize)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isOn && hasApps
                     ? "\(chosenCount) \(chosenCount == 1 ? "app" : "apps") to lock"
                     : "Choose apps to lock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(isOn && hasApps ? "Tap to add or remove" : "TikTok, Instagram or any app you choose")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)
            Image(systemName: hasPremium ? "chevron.right" : "lock.fill")
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

    // MARK: - How long

    /// A slider from 1 minute to 1 hour, always shown, with the chosen time
    /// in big type above it and a sentence saying exactly how long it will be.
    private var durationBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("How long to lock", systemImage: "hourglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Self.shortText(minutes))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: minutes)
            }

            Slider(value: durationIndex, in: 0...Double(AppLocker.durations.count - 1), step: 1) {
                Text("How long to lock")
            } minimumValueLabel: {
                Text("1 min").font(.caption2).foregroundStyle(Theme.textSecondary)
            } maximumValueLabel: {
                Text("1 hr").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.textPrimary)
            .accessibilityValue(Self.durationText(minutes))

            Text("Apps stay locked for \(Self.durationText(minutes)) after you walk off this alarm.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// The slider moves through `AppLocker.durations` one stop at a time.
    private var durationIndex: Binding<Double> {
        Binding(
            get: {
                let stops = AppLocker.durations
                let nearest = stops.indices.min { abs(stops[$0] - minutes) < abs(stops[$1] - minutes) } ?? 0
                return Double(nearest)
            },
            set: { index in
                let value = AppLocker.durations[Int(index.rounded())]
                if value != minutes {
                    Theme.tap()
                    minutes = value
                }
            }
        )
    }

    /// "30 min", "1 hr", "1 hr 30 min" for the big number.
    static func shortText(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// "1 minute", "30 minutes", "1 hour", "1 hour 30 minutes" for sentences.
    static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        let minuteText = "\(rest) \(rest == 1 ? "minute" : "minutes")"
        if hours == 0 { return minuteText }
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        return rest == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    // MARK: - Turning on

    private func setOn(_ on: Bool) async {
        guard on else {
            isOn = false
            return
        }
        guard hasPremium else {
            turnOnAfterPaywall = true
            showPaywall = true
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

/// "PREMIUM ONLY" tag at the top of the one paid feature.
struct PremiumBadge: View {
    var body: some View {
        Label("PREMIUM ONLY", systemImage: "crown.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(red: 1, green: 0.8, blue: 0.2), in: Capsule())
            .fixedSize()
    }
}

/// Instagram, TikTok and Snapchat tiles that show what App Lock is for before
/// any real apps are picked: the real logo pictures when
/// `AppConfig.showRealAppLogos` is on and the picture is in Assets, otherwise
/// drawn look-alikes in their colors.
struct SampleAppIcons: View {
    var size: CGFloat

    private struct Sample: Identifiable {
        let id: String
        let asset: String
        let colors: [Color]
        let symbol: String
        let symbolColor: Color
    }

    private static let samples = [
        Sample(id: "Instagram", asset: "LogoInstagram",
               colors: [Color(red: 0.51, green: 0.23, blue: 0.71), Color(red: 0.99, green: 0.11, blue: 0.11),
                        Color(red: 0.99, green: 0.69, blue: 0.27)],
               symbol: "camera", symbolColor: .white),
        Sample(id: "TikTok", asset: "LogoTikTok", colors: [.black, Color(white: 0.12)], symbol: "music.note", symbolColor: .white),
        Sample(id: "Snapchat", asset: "LogoSnapchat", colors: [Color(red: 1, green: 0.99, blue: 0)], symbol: "bubble.left.fill",
               symbolColor: .black),
    ]

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Self.samples) { sample in
                tile(sample)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ sample: Sample) -> some View {
        if AppConfig.showRealAppLogos, let logo = UIImage(named: sample.asset) {
            Image(uiImage: logo)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: sample.colors, startPoint: .bottomLeading, endPoint: .topTrailing)
                .overlay(
                    Image(systemName: sample.symbol)
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(sample.symbolColor)
                )
        }
    }
}
