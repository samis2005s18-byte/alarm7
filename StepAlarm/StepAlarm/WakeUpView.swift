import SwiftUI

/// Presentational "Wake Up!" screen: clock, step-progress ring, and a
/// grouped block of instructions — no more floating pieces with dead space
/// between them.
struct WakeUpView: View {
    var now: Date = .now
    var stepCount: Int
    var stepGoal: Int
    var isMoving: Bool = false
    var isComplete: Bool = false
    var label: String = ""
    var statusText: String = "Start walking…"
    var statusIcon: String? = nil
    var errorMessage: String? = nil
    /// Free tier only — offered once, right after a one-time alarm rings.
    var repeatOffer: RepeatOffer? = nil
    /// Small gray line showing what the phone detects (temporary, for tuning).
    var diagnostics: String = ""
    /// Shown only for alarms with Emergency stop turned on.
    var onEmergencyStop: (() -> Void)? = nil

    struct RepeatOffer {
        var nextTime: Date
        var onSetAgain: () -> Void
        var onShowPaywall: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 60, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isComplete ? Theme.textPrimary : .white)
                if !label.isEmpty {
                    Text(label)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isComplete ? Theme.textSecondary : .white.opacity(0.7))
                }
            }
            .padding(.top, Theme.Spacing.xl)

            Spacer(minLength: Theme.Spacing.lg)

            if isComplete {
                completedContent
            } else {
                ringContent
            }

            Spacer(minLength: Theme.Spacing.lg)

            Group {
                if !isComplete, let onEmergencyStop {
                    HoldToStopButton(onComplete: onEmergencyStop)
                } else {
                    Text(isComplete ? "" : diagnostics)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((isComplete ? Theme.background : .black).ignoresSafeArea())
        .animation(.easeOut(duration: 0.3), value: isComplete)
    }

    // MARK: - Ringing state

    private var ringContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("Wake Up!")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)

            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: min(1, Double(stepCount) / Double(max(stepGoal, 1))))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.45, bounce: 0.2), value: stepCount)
                VStack(spacing: 6) {
                    Text("\(stepCount)")
                        .font(.system(size: 84, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .scaleEffect(isMoving ? 1.05 : 1)
                        .animation(.spring(duration: 0.3, bounce: 0.4), value: stepCount)
                    Text("of \(stepGoal) steps")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 260, height: 260)
            .padding(.horizontal, Theme.Spacing.lg)

            Image("WalkingIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 54)
                .foregroundStyle(.white)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Get up and walk to turn off the alarm")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Group {
                    if errorMessage == nil, let statusIcon {
                        Label(statusText, systemImage: statusIcon)
                    } else {
                        Text(errorMessage ?? statusText)
                    }
                }
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(errorMessage != nil ? Theme.accent : .white.opacity(0.7))
                    .animation(.easeOut(duration: 0.2), value: statusText)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    // MARK: - Completed state

    private var completedContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.textPrimary)
            Text("Good morning")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            if let offer = repeatOffer {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Set again for tomorrow at \(offer.nextTime, format: .dateTime.hour().minute())?")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)

                    Button(action: offer.onSetAgain) {
                        Text("Yes")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm + 2)
                            .background(Theme.textPrimary, in: Capsule())
                    }
                    .buttonStyle(.pressable)

                    Button(action: offer.onShowPaywall) {
                        Label("Make it repeat automatically with Pro", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// "Can't walk? Hold to stop" — must be held for the full 10 seconds, so it's
/// there for people who can't walk but too slow to be an easy way out.
private struct HoldToStopButton: View {
    var onComplete: () -> Void
    @State private var progress = 0.0

    private static let holdDuration: TimeInterval = 10

    var body: some View {
        Label("Can't walk? Hold for 10 seconds to stop", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm + 4)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.accent.opacity(0.3))
                        .frame(width: geo.size.width * progress)
                }
            }
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 60) {
                onComplete()
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .accessibilityHint("Touch and hold for 10 seconds to turn off the alarm without walking")
    }
}

/// The live version: reads the walk session (real or demo) and refreshes
/// the clock / "moving" status once a second.
struct WakeUpScreen: View {
    private var session = WalkSession.shared
    @State private var showPaywall = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            WakeUpView(
                now: context.date,
                stepCount: session.steps,
                stepGoal: session.goal,
                isMoving: session.lastStepDate.map { context.date.timeIntervalSince($0) < 3 } ?? false,
                isComplete: session.isComplete,
                label: session.label,
                statusText: session.progressStatus,
                statusIcon: session.progressIcon,
                errorMessage: session.motionMessage,
                repeatOffer: repeatOffer,
                diagnostics: session.diagnostics,
                onEmergencyStop: session.emergencyStopAllowed ? { session.emergencyStop() } : nil
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
    }

    /// Only for a real (non-demo) alarm dismissal while on the free tier —
    /// free alarms are always one-time, so this is the moment to offer
    /// re-enabling it for tomorrow with a single tap.
    private var repeatOffer: WakeUpView.RepeatOffer? {
        guard session.isComplete, !session.isDemo, let id = session.completedAlarmID,
              !SubscriptionStore.shared.hasFullAccess
        else { return nil }
        let nextTime = Calendar.current.date(
            bySettingHour: session.completedAlarmHour, minute: session.completedAlarmMinute, second: 0, of: .now
        ) ?? .now
        return WakeUpView.RepeatOffer(
            nextTime: nextTime,
            onSetAgain: {
                Task {
                    // Reschedule must land before finishNow() flips isActive
                    // false, or ContentView's resulting refreshFromSystem()
                    // could see the alarm as "not live yet" and immediately
                    // flip it back off.
                    await AlarmStore.shared.setEnabled(id, true)
                    session.finishNow()
                }
            },
            onShowPaywall: { showPaywall = true }
        )
    }
}

#Preview {
    WakeUpView(stepCount: 8, stepGoal: 15)
}
