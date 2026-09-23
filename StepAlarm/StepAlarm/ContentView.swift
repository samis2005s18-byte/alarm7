import CoreMotion
import SwiftUI
import UIKit

/// Home screen: native large-title list (like Clock's Alarms tab), a
/// "next alarm in…" card, icon-labelled rows, and real swipe-to-delete.
/// The developer test tools still live behind a long-press on the gear icon.
struct ContentView: View {
    private var scheduler = AlarmScheduler.shared
    private var store = AlarmStore.shared
    private var session = WalkSession.shared
    private var settings = AppSettings.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showTests = false
    @State private var sheetAlarm: AlarmItem?
    @State private var toastMessage: ToastMessage?
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            List {
                if !hasPermissions {
                    Section {
                        Button { openSettings() } label: {
                            note("To set alarms, allow Alarms and Motion & Fitness. Tap to open Settings.", isError: true)
                        }
                    }
                }
                if let error = scheduler.lastError {
                    Section { note(error, isError: true) }
                }
                if let text = store.nextAlarmDescription {
                    Section {
                        nextAlarmCard(text)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if store.alarms.isEmpty {
                    Section { emptyState }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.alarms) { alarm in
                            alarmRow(alarm)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteAlarm(alarm.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            for index in offsets { deleteAlarm(store.alarms[index].id) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: store.alarms)
            .navigationTitle("Alarms")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !store.alarms.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Settings")
                        .onLongPressGesture(minimumDuration: 0.6) { showTests = true }
                        Button(action: addAlarm) {
                            Image(systemName: "plus")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Add alarm")
                    }
                }
            }
        }
        .toast($toastMessage)
        .sheet(item: $sheetAlarm) { alarm in
            AddAlarmView(
                alarm: alarm,
                title: store.isSaved(alarm.id) ? "Edit Alarm" : "Add Alarm",
                onCancel: { sheetAlarm = nil },
                onSave: { saved in
                    if blockIfRinging(saved.id) {
                        sheetAlarm = nil
                        return
                    }
                    guard hasPermissions else {
                        sheetAlarm = nil
                        showPermissionAlert = true
                        return
                    }
                    sheetAlarm = nil
                    let isFirstEver = !settings.hasSavedFirstAlarm
                    settings.hasSavedFirstAlarm = true
                    Task {
                        await store.upsert(saved)
                        if let next = saved.nextRingDate() {
                            toastMessage = ToastMessage(text: "Alarm set for " + AlarmItem.countdownText(to: next))
                        }
                    }
                    // The one moment the paywall is allowed to appear
                    // unprompted — right after the very first alarm ever
                    // created, never before it.
                    if isFirstEver && !SubscriptionStore.shared.isPro && SubscriptionStore.purchasesEnabled {
                        showPaywall = true
                    }
                },
                onDelete: store.isSaved(alarm.id) ? {
                    sheetAlarm = nil
                    deleteAlarm(alarm.id)
                } : nil
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false }, onShowPaywall: { showPaywall = true })
        }
        .sheet(isPresented: $showTests) {
            TestsSheet(
                onClose: { showTests = false },
                onDemo: {
                    showTests = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        session.beginDemo()
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .alert("Permissions needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Alarm7 can't set an alarm until both Alarms and Motion & Fitness are allowed. Open Settings, tap Alarm7, and turn both on.")
        }
        .fullScreenCover(isPresented: Binding(get: { session.isActive }, set: { _ in })) {
            WakeUpScreen()
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.hasCompletedOnboarding }, set: { _ in })) {
            OnboardingFlow()
        }
        .task {
            await SubscriptionStore.shared.start()
            // Onboarding owns the first-run permission requests (with its
            // own explanation screens); only re-prime here on later launches.
            if settings.hasCompletedOnboarding {
                await scheduler.requestAuthorizationIfNeeded()
                session.requestMotionPermission()
            }
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            session.refresh()
            Task { await refresh() }
        }
        .onChange(of: session.isActive) { _, active in
            if !active { Task { await store.refreshFromSystem() } }
        }
    }

    /// Sync the list with AlarmKit, downgrade any repeats if Pro has lapsed,
    /// and jump to the walk screen if an alarm is ringing.
    private func refresh() async {
        if settings.hasCompletedOnboarding {
            // Picks up permissions changed in the Settings app.
            await scheduler.requestAuthorizationIfNeeded()
        }
        await store.refreshFromSystem()
        await store.downgradeRepeatingAlarmsIfNeeded()
        session.resumeIfAlarmRinging()
    }

    private func deleteAlarm(_ id: UUID) {
        if blockIfRinging(id) { return }
        Task { await store.delete(id) }
    }

    /// While an alarm is ringing (or waiting to ring again), only walking can
    /// end it — it can't be switched off, edited away, or deleted.
    private func blockIfRinging(_ id: UUID) -> Bool {
        guard AlarmGoals.isRinging(id) else { return false }
        toastMessage = ToastMessage(text: "Walk your steps to turn this alarm off", systemImage: "figure.walk")
        session.resumeIfAlarmRinging()
        return true
    }

    /// Both Alarms and Motion & Fitness must be allowed — without them an
    /// alarm couldn't ring or couldn't be walked off.
    private var hasPermissions: Bool {
        scheduler.isAuthorized && CMPedometer.authorizationStatus() == .authorized
    }

    /// Asks for any permission that hasn't been decided yet, then reports
    /// whether both are allowed.
    private func ensurePermissions() async -> Bool {
        await scheduler.requestAuthorizationIfNeeded()
        if CMPedometer.authorizationStatus() == .notDetermined {
            _ = await session.requestMotionAuthorization()
        }
        return hasPermissions
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// 3 free alarms, unlimited for Pro.
    private func addAlarm() {
        Task {
            guard await ensurePermissions() else {
                showPermissionAlert = true
                return
            }
            if !SubscriptionStore.shared.isPro && store.alarms.count >= AlarmStore.freeAlarmLimit {
                showPaywall = true
            } else {
                sheetAlarm = .new(defaultSteps: settings.defaultSteps)
            }
        }
    }

    // MARK: - Pieces

    private func nextAlarmCard(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "alarm.fill")
                .font(.title3)
                .foregroundStyle(Theme.textPrimary)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "alarm")
                .font(.system(size: 52))
                .foregroundStyle(Theme.textSecondary)
            Text("No alarms yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add an alarm you actually have to get up for.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: addAlarm) {
                Text("Add Alarm")
                    .font(.headline)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.textPrimary, in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl * 2)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func alarmRow(_ alarm: AlarmItem) -> some View {
        Button {
            sheetAlarm = alarm
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alarm.date, format: .dateTime.hour().minute())
                        .font(.system(size: 46, weight: .light))

                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.subheadline.weight(.medium))
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        Label {
                            Text(alarm.stepsText)
                        } icon: {
                            Image("WalkingIcon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 15)
                        }
                        Label(alarm.repeatText, systemImage: "repeat")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(alarm.isOn ? Theme.textPrimary : Theme.textDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                Toggle("", isOn: Binding(
                    get: { alarm.isOn },
                    set: { on in
                        if !on && blockIfRinging(alarm.id) { return }
                        Theme.tap()
                        Task {
                            if on, !(await ensurePermissions()) {
                                showPermissionAlert = true
                                return
                            }
                            await store.setEnabled(alarm.id, on)
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.neutralActive)
            }
            .opacity(alarm.isOn ? 1 : 0.55)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit")
    }

    private func note(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isError ? Theme.accent : Theme.textSecondary)
    }
}

/// Developer test tools (long-press the gear icon to open).
private struct TestsSheet: View {
    var onClose: () -> Void
    var onDemo: () -> Void

    private var scheduler = AlarmScheduler.shared
    private var liveActivity = LiveActivityController.shared

    init(onClose: @escaping () -> Void, onDemo: @escaping () -> Void) {
        self.onClose = onClose
        self.onDemo = onDemo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Test tools")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, Theme.Spacing.sm)

            row("Try the Wake Up screen (simulated steps)", "figure.walk", onDemo)
            row("Ring a 15-step alarm in 15 seconds", "alarm") {
                Task { await scheduler.scheduleTestAlarm(secondsFromNow: 15) }
                onClose()
            }
            row("Lock Screen counter (30s)", "lock") {
                liveActivity.startCounterOnlyTest(stepGoal: 15, durationSeconds: 30)
            }
            row("Alarm + Lock Screen counter", "lock.badge.clock") {
                Task {
                    await liveActivity.startCombinedWithAlarmTest(stepGoal: 15, alarmSecondsFromNow: 30)
                }
            }
            row("End test", "xmark.circle") { liveActivity.endTest() }
            row("Reset onboarding", "arrow.counterclockwise") {
                AppSettings.shared.hasCompletedOnboarding = false
                onClose()
            }

            Text(liveActivity.lastError ?? liveActivity.statusMessage)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.Spacing.sm)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
    }

    private func row(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
        }
        .buttonStyle(.pressable)
    }
}

#Preview {
    ContentView()
}
