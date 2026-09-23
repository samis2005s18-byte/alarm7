import ActivityKit

/// Must be added to BOTH the app target and the widget extension target's
/// membership in Xcode — both need to see the identical type, or you'll
/// get a mismatched-activity-type failure at runtime instead of a build
/// error, which is much more confusing to debug.
struct StepAlarmActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepCount: Int
        var stepGoal: Int
    }

    var alarmID: String
}
