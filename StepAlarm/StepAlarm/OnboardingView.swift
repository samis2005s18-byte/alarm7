import SwiftUI
import UIKit

/// First-run onboarding: hook, how-it-works, no-snooze, permissions (with
/// real system prompts gated behind an explanation screen, and graceful
/// denial handling). Ends there — creating the first alarm happens in the
/// real Alarm List afterward, using the app's own Add Alarm flow, which is
/// also where the one-time "paywall after your first alarm" trigger lives
/// (see `ContentView`'s add-alarm `onSave`).
///
/// Dark-mode-only by design (this screen doesn't use `Theme` — it's a fixed
/// black/white/red look regardless of the system appearance), matching the
/// approved onboarding mockups.
struct OnboardingFlow: View {
    private enum Page: Int, CaseIterable {
        case hook, howItWorks, noSnooze, permissions
    }

    @State private var page: Page = .hook
    @State private var alarmState: RowState = .idle
    @State private var motionState: RowState = .idle
    @State private var deniedKind: DeniedKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scheduler = AlarmScheduler.shared
    private var session = WalkSession.shared
    private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $page) {
            HookScreen(onSkip: skipToPermissions, onNext: advance)
                .tag(Page.hook)
            HowItWorksScreen(onSkip: skipToPermissions, onNext: advance)
                .tag(Page.howItWorks)
            NoSnoozeScreen(onSkip: skipToPermissions, onNext: advance)
                .tag(Page.noSnooze)
            PermissionsScreen(
                alarmState: alarmState,
                motionState: motionState,
                onAllow: { Task { await requestPermissions() } }
            )
            .tag(Page.permissions)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .sheet(item: $deniedKind) { kind in
            PermissionDeniedScreen(
                text: kind.explanation,
                onOpenSettings: openSettings,
                onContinue: {
                    deniedKind = nil
                    switch kind {
                    case .alarm: Task { await requestMotion() }
                    case .motion: finish()
                    }
                }
            )
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = Page(rawValue: page.rawValue + 1) else { return }
        withAnimation(reduceMotion ? nil : .default) { page = next }
    }

    private func skipToPermissions() {
        withAnimation(reduceMotion ? nil : .default) { page = .permissions }
    }

    // MARK: - Permissions
    //
    // Both rows stay visible on the Permissions screen the whole time — the
    // user sees each one flip from a spinner to a checkmark (or an X) as
    // "Allow Access" actually works through them, rather than being bounced
    // to a blank loading screen.

    private func requestPermissions() async {
        guard alarmState != .granted else { return await requestMotion() }
        alarmState = .requesting
        await scheduler.requestAuthorizationIfNeeded()
        if scheduler.isAuthorized {
            alarmState = .granted
            await requestMotion()
        } else {
            alarmState = .denied
            deniedKind = .alarm
        }
    }

    private func requestMotion() async {
        motionState = .requesting
        let granted = await session.requestMotionAuthorization()
        if granted {
            motionState = .granted
            finish()
        } else {
            motionState = .denied
            deniedKind = .motion
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Both permissions are resolved (granted or the user chose to continue
    /// without them) — the only moment onboarding is marked done, so it
    /// never reappears. Lands the user on the real, empty Alarm List.
    private func finish() {
        settings.hasCompletedOnboarding = true
    }
}

// MARK: - Shared chrome

private struct OnboardingDots: View {
    var current: Int
    var total: Int = 4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == current ? 16 : 6, height: 6)
            }
        }
    }
}

private struct OnboardingButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 24)
    }
}

/// Shared layout for the three simple pages (skip bar, flexible content,
/// page dots, primary button) so spacing/type stay identical across them.
private struct OnboardingPageChrome<Content: View>: View {
    var showSkip: Bool
    var currentPage: Int
    var buttonTitle: String
    var onSkip: () -> Void
    var onButton: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if showSkip {
                    Button("Skip", action: onSkip)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(white: 0.85))
                }
            }
            .frame(height: 20)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingDots(current: currentPage)
                .padding(.bottom, 16)

            OnboardingButton(title: buttonTitle, action: onButton)
                .padding(.bottom, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private func onboardingRow(icon: String, text: String) -> some View {
    onboardingRow(text: text) {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
    }
}

/// Same row, but with the app's own walking-guy asset instead of an SF
/// Symbol — used wherever the copy is literally about walking, so it
/// matches the icon on the Wake Up screen exactly.
private func onboardingWalkRow(text: String) -> some View {
    onboardingRow(text: text) {
        Image("WalkingIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 15, height: 20)
            .foregroundStyle(.white)
    }
}

private func onboardingRow(text: String, @ViewBuilder icon: () -> some View) -> some View {
    HStack(spacing: 14) {
        icon()
            .frame(width: 40, height: 40)
            .background(Color(white: 0.16), in: Circle())
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        Spacer()
    }
    .padding(14)
    .background(Color(red: 0.110, green: 0.110, blue: 0.118), in: RoundedRectangle(cornerRadius: 14))
}

// MARK: - Screen 1: Hook

private struct HookScreen: View {
    var onSkip: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HookIllustration()
                Button("Skip", action: onSkip)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.top, 8)
                    .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200, maxHeight: .infinity)
            .clipped()

            VStack(spacing: 8) {
                Text("Walk to wake up")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("No snooze. No excuses.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.82))
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            OnboardingDots(current: 0)
                .padding(.top, 16)
                .padding(.bottom, 16)

            OnboardingButton(title: "Get Started", action: onNext)
                .padding(.bottom, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// The real red-glow artwork, full-bleed behind the Skip button.
private struct HookIllustration: View {
    var body: some View {
        GeometryReader { geo in
            Image("HookIllustration")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .background(Color.black)
    }
}

// MARK: - Screen 2: How it works

private struct HowItWorksScreen: View {
    var onSkip: () -> Void
    var onNext: () -> Void

    var body: some View {
        OnboardingPageChrome(showSkip: true, currentPage: 1, buttonTitle: "Next", onSkip: onSkip, onButton: onNext) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How it works")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                onboardingRow(icon: "alarm.fill", text: "Set your alarm")
                onboardingRow(icon: "bell.fill", text: "It rings until you move")
                onboardingWalkRow(text: "Walk to turn it off")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Screen 3: No snooze

private struct NoSnoozeScreen: View {
    var onSkip: () -> Void
    var onNext: () -> Void

    var body: some View {
        OnboardingPageChrome(showSkip: true, currentPage: 2, buttonTitle: "Makes sense", onSkip: onSkip, onButton: onNext) {
            VStack(spacing: 24) {
                Spacer(minLength: 12)
                NoSnoozeGraphic()
                Spacer(minLength: 12)
                VStack(spacing: 8) {
                    Text("No snooze")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("That's the point.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.82))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct NoSnoozeGraphic: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.16))
                .frame(width: 220, height: 90)
            Text("Snooze")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
            Rectangle()
                .fill(Color(red: 1, green: 0.231, blue: 0.188))
                .frame(width: 260, height: 5)
                .rotationEffect(.degrees(-32))
        }
    }
}

// MARK: - Screen 4: Permissions

/// Per-row progress as "Allow Access" actually works through each system
/// prompt — the whole point being that the user watches it happen instead
/// of staring at a blank screen.
fileprivate enum RowState: Equatable {
    case idle, requesting, granted, denied
}

fileprivate enum DeniedKind: Identifiable {
    case alarm, motion
    var id: Self { self }

    var explanation: String {
        switch self {
        case .alarm:
            return "Alarm7 needs alarm access to actually wake you up. Without it, your alarms can't ring."
        case .motion:
            return "Alarm7 needs Motion & Fitness access to count your steps. Without it, you can't walk to dismiss an alarm."
        }
    }
}

private struct PermissionsScreen: View {
    var alarmState: RowState
    var motionState: RowState
    var onAllow: () -> Void

    private var isBusy: Bool { alarmState == .requesting || motionState == .requesting }
    private var allGranted: Bool { alarmState == .granted && motionState == .granted }
    private var buttonTitle: String {
        if allGranted { return "All set" }
        if alarmState == .denied || motionState == .denied { return "Try Again" }
        return "Allow Access"
    }

    var body: some View {
        OnboardingPageChrome(showSkip: false, currentPage: 3, buttonTitle: buttonTitle, onSkip: {}, onButton: onAllow) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Two permissions")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 32)

                VStack(spacing: 12) {
                    permissionRow(state: alarmState, text: "Ring your alarms") {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    permissionRow(state: motionState, text: "Count your steps") {
                        Image("WalkingIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 20)
                            .foregroundStyle(.white)
                    }
                }

                Text("Steps stay on your phone.")
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.6))
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .disabled(isBusy || allGranted)
    }

    private func permissionRow(state: RowState, text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 40, height: 40)
                .background(Color(white: 0.16), in: Circle())
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            switch state {
            case .idle:
                EmptyView()
            case .requesting:
                ProgressView().tint(.white)
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color(red: 1, green: 0.231, blue: 0.188))
            }
        }
        .padding(14)
        .background(Color(red: 0.110, green: 0.110, blue: 0.118), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Shown if either permission is denied. Never a dead end — always offers a
/// path to Settings AND a way to keep going without it.
private struct PermissionDeniedScreen: View {
    var text: String
    var onOpenSettings: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(red: 1, green: 0.231, blue: 0.188))
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Spacer()
            OnboardingButton(title: "Open Settings", action: onOpenSettings)
            Button("Continue without it", action: onContinue)
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.82))
                .padding(.top, 4)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    OnboardingFlow()
}
