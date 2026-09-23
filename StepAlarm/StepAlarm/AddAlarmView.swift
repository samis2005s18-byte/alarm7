import SwiftUI

/// "Add Alarm" / "Edit Alarm" sheet: time wheel, then every other setting
/// laid out as a native grouped list directly underneath it — no dead gap
/// in between, and every row carries its own icon.
struct AddAlarmView: View {
    let alarm: AlarmItem
    let title: String
    var onCancel: () -> Void
    var onSave: (AlarmItem) -> Void
    /// Set only when editing a saved alarm — shows the Delete Alarm button.
    var onDelete: (() -> Void)?

    @State private var time: Date
    @State private var steps: Double
    @State private var days: Set<Int>   // 0 = Sunday … 6 = Saturday
    @State private var vibrationEnabled: Bool
    @State private var emergencyStop: Bool
    @State private var showPaywall = false

    private var isPro: Bool { SubscriptionStore.shared.hasFullAccess }
    private static let freeStepLimit = 15
    private static let proStepLimit = 30
    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    init(alarm: AlarmItem, title: String,
         onCancel: @escaping () -> Void, onSave: @escaping (AlarmItem) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.alarm = alarm
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _time = State(initialValue: alarm.date)
        _steps = State(initialValue: Double(alarm.steps))
        _days = State(initialValue: alarm.days)
        _vibrationEnabled = State(initialValue: alarm.vibrationEnabled)
        _emergencyStop = State(initialValue: alarm.emergencyStop)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, Theme.Spacing.sm)

            header
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)

            timePicker

            List {
                stepsSection
                repeatSection
                extrasSection
                emergencySection
                if let onDelete {
                    Section {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Alarm", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
    }

    // MARK: - Header & time

    private var header: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Cancel")
                Spacer()
                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 40, height: 40)
                        .background(Theme.textPrimary, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Save alarm")
            }
        }
    }

    /// The wheel follows the device's own 12/24-hour setting (no forced
    /// locale) and stays fully native/plain — no accent tint on it at all,
    /// so red stays reserved for the moments that actually matter.
    private var timePicker: some View {
        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label {
                        Text("Steps to dismiss")
                    } icon: {
                        Image("WalkingIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 20)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        if !isPro && Int(steps) >= Self.freeStepLimit {
                            Image(systemName: "lock.fill").font(.caption)
                        }
                        Text("\(Int(steps)) \(Int(steps) == 1 ? "step" : "steps")")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

                Slider(value: $steps, in: 1...Double(Self.proStepLimit), step: 1)
                    .tint(Theme.neutralActive)
                    .onChange(of: steps) { _, newValue in
                        Theme.tap()
                        enforceStepLimit(newValue)
                    }

                HStack(spacing: Theme.Spacing.sm) {
                    presetChip(10)
                    presetChip(20)
                    presetChip(30)
                }

                Text("\(Int(steps)) steps ≈ \(Int(steps)) sec of walking")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private func presetChip(_ value: Int) -> some View {
        let locked = !isPro && value > Self.freeStepLimit
        let selected = Int(steps) == value
        return Button {
            if locked {
                showPaywall = true
            } else {
                Theme.tap()
                steps = Double(value)
            }
        } label: {
            HStack(spacing: 4) {
                if locked { Image(systemName: "lock.fill").font(.caption2) }
                Text("\(value)")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget - 8)
            .background(selected ? Theme.textPrimary : Theme.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func enforceStepLimit(_ value: Double) {
        guard !isPro, value > Double(Self.freeStepLimit) else { return }
        steps = Double(Self.freeStepLimit)
        showPaywall = true
    }

    // MARK: - Repeat

    /// Repeat is Pro-only: free alarms always ring once, then turn
    /// themselves off (the Wake Up screen offers a one-tap "set again for
    /// tomorrow" instead). Every control here is locked behind the paywall
    /// for free users rather than silently allowing it.
    private var repeatSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label("Repeat", systemImage: "repeat")
                    Spacer()
                    if !isPro {
                        Image(systemName: "lock.fill").font(.caption)
                    }
                    Text(isPro ? AlarmItem.repeatSummary(days) : "Once")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<7, id: \.self) { dayCircle($0) }
                }

                HStack(spacing: Theme.Spacing.sm) {
                    quickChip("Weekdays") { days = [1, 2, 3, 4, 5] }
                    quickChip("Weekends") { days = [0, 6] }
                    quickChip("Every day") { days = Set(0..<7) }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        } footer: {
            if !isPro {
                Text("Repeat schedules are a Pro feature. Upgrade to have alarms repeat automatically.")
            }
        }
    }

    private func dayCircle(_ i: Int) -> some View {
        let selected = days.contains(i)
        return Button {
            guard isPro else { showPaywall = true; return }
            Theme.tap()
            if selected { days.remove(i) } else { days.insert(i) }
        } label: {
            Text(Self.dayLetters[i])
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget)
                .background(selected ? Theme.textPrimary : Theme.surface, in: Circle())
                .opacity(isPro ? 1 : 0.5)
        }
        .buttonStyle(.pressable)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: selected)
        .frame(maxWidth: .infinity)
    }

    private func quickChip(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button {
            guard isPro else { showPaywall = true; return }
            Theme.tap()
            action()
        } label: {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(minHeight: 32)
                .background(Theme.surface, in: Capsule())
                .opacity(isPro ? 1 : 0.5)
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Vibration

    private var extrasSection: some View {
        Section {
            Toggle(isOn: $vibrationEnabled) {
                Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
            }
            .tint(Theme.neutralActive)
            .onChange(of: vibrationEnabled) { _, _ in Theme.tap() }
        } footer: {
            Text("No snooze: tapping Stop rings the alarm again until you walk.")
        }
    }

    // MARK: - Emergency stop

    private var emergencySection: some View {
        Section {
            Toggle(isOn: $emergencyStop) {
                Label("Emergency stop", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.accent)
            }
            .tint(Theme.accent)
            .onChange(of: emergencyStop) { _, _ in Theme.tap() }
        } footer: {
            Text("Caution: this lets you turn off the alarm without walking by holding a button for 10 seconds. Only turn it on if you might not be able to walk, for example because of an injury.")
                .foregroundStyle(Theme.accent)
        }
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var updated = alarm
        updated.hour = parts.hour ?? alarm.hour
        updated.minute = parts.minute ?? alarm.minute
        updated.steps = Int(steps)
        updated.days = isPro ? days : []
        updated.emergencyStop = emergencyStop
        updated.snoozeEnabled = true
        updated.vibrationEnabled = vibrationEnabled
        updated.isOn = true
        Theme.success()
        onSave(updated)
    }
}

#Preview {
    AddAlarmView(alarm: .new(), title: "Add Alarm", onCancel: {}, onSave: { _ in })
}
