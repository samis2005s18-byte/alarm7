import AlarmKit

/// Custom data attached to a scheduled alarm. AlarmKit requires this to be
/// Codable/Hashable/Sendable — conforming to `AlarmMetadata` gets you that.
struct StepAlarmMetadata: AlarmMetadata {
    let stepGoal: Int
}
