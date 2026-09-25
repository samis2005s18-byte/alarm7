import DeviceActivity
import ManagedSettings

/// Runs in the background when the lock period set by `AppLocker` ends and
/// unlocks the apps, so they open again on time even if Alarm7 is closed.
final class AppLockMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .alarm7AppLock else { return }
        ManagedSettingsStore(named: .alarm7AppLock).clearAllSettings()
    }
}
