import Foundation
import Observation

/// Developer switches — both off for App Store builds.
enum AppConfig {
    /// Long-press the Settings gear for test alarms and demos.
    static let showDeveloperTools = false
    /// Gray line on the Wake Up screen comparing step counters.
    static let showStepDiagnostics = false
    /// "Lock apps after I wake up" (Screen Time). Set to false to hide the
    /// whole feature: its Settings section disappears and nothing is locked.
    static let appLockEnabled = true
}

/// App-wide preferences: defaults used when creating a new alarm, plus
/// first-run state (onboarding, first alarm saved) used to gate when the
/// paywall and onboarding flow are allowed to appear.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let vibration = "settings.vibrationEnabled"
        static let defaultSteps = "settings.defaultSteps"
        static let onboarded = "settings.hasCompletedOnboarding"
        static let firstAlarmSaved = "settings.hasSavedFirstAlarm"
    }

    var vibrationEnabled: Bool {
        didSet { defaults.set(vibrationEnabled, forKey: Keys.vibration) }
    }
    /// Prefilled step goal for a brand-new alarm.
    var defaultSteps: Int {
        didSet { defaults.set(defaultSteps, forKey: Keys.defaultSteps) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }
    var hasSavedFirstAlarm: Bool {
        didSet { defaults.set(hasSavedFirstAlarm, forKey: Keys.firstAlarmSaved) }
    }

    private init() {
        vibrationEnabled = defaults.object(forKey: Keys.vibration) as? Bool ?? true
        defaultSteps = defaults.object(forKey: Keys.defaultSteps) as? Int ?? 15
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        hasSavedFirstAlarm = defaults.bool(forKey: Keys.firstAlarmSaved)
    }
}
