import DeviceActivity
import ManagedSettings

/// Names shared by the app (which locks the chosen apps) and the
/// AppLockMonitor extension (which unlocks them when the time is up, even if
/// Alarm7 isn't running).
extension ManagedSettingsStore.Name {
    static let alarm7AppLock = Self("alarm7.appLock")
}

extension DeviceActivityName {
    static let alarm7AppLock = Self("alarm7.appLock")
}
