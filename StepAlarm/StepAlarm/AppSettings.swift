import Foundation
import Observation

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
