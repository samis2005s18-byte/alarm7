# Step Alarm — Phase 1

This is the "make it ring" phase. Nothing else has been built yet — no step
counting, no settings, no alarm list. That's intentional per the build brief.

## Why this is source files, not a `.xcodeproj`

This was written on Windows with no Xcode, no macOS, and no physical iPhone
attached. Hand-crafting an Xcode `.pbxproj` file blind is a good way to hand
you a corrupted project, and there's no way to compile-check any of this
from here anyway — AlarmKit and CMPedometer both require a real device per
Apple's own docs, so a simulator wouldn't have proven anything either.
Instead: create the project yourself in Xcode (takes 30 seconds) and drop
these files in.

## Setup

1. On your Mac, open Xcode 26 → **File → New → Project → iOS → App**.
   - Product Name: `StepAlarm`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Include Tests" if you want, doesn't matter for Phase 1.
2. Set the deployment target to **iOS 26.0** (project settings → General →
   Minimum Deployments).
3. Delete the auto-generated `ContentView.swift` and `StepAlarmApp.swift`
   Xcode created, then drag in every file from this folder's `StepAlarm/`
   subdirectory:
   - `StepAlarmApp.swift`
   - `ContentView.swift`
   - `AlarmScheduler.swift`
   - `AlarmMetadata.swift`
   - `StopIntent.swift`
   - `LiveActivityController.swift`
   - `Theme.swift`, `AlarmStore.swift`, `WalkSession.swift`,
     `WakeUpView.swift`, `AddAlarmView.swift`
   - `PaywallView.swift`, `SubscriptionStore.swift`
   - `AppSettings.swift`, `SettingsView.swift`, `Toast.swift`
   - `LegalDocumentView.swift`

4. Permission strings — an `Info.plist` with the three required keys is
   already included in this folder (`StepAlarm/Info.plist`). Easiest path:
   drag it in alongside the other files, then in the target's **Build
   Settings** search "Info.plist" and set:
   - `Generate Info.plist File` → `No`
   - `Info.plist File` → `StepAlarm/Info.plist` (the path to the file you
     just added)

   If you'd rather keep Xcode's auto-generated Info.plist instead, skip
   dragging the file in and add these three keys by hand in the target →
   **Info** tab:
   - `NSAlarmKitUsageDescription` → "Step Alarm needs alarm access to wake
     you up." (verify the exact key via Xcode's autocomplete — start typing
     "Alarm")
   - `NSMotionUsageDescription` → "Step Alarm counts your steps to turn the
     alarm off."
   - `NSSupportsLiveActivities` → `YES`

5. **Signing & Capabilities** tab → select your existing Apple Developer
   team. Do not create a new identifier — use what's already provisioned.
   While here, click **+ Capability** and search "Alarm" — if AlarmKit
   ships as an explicit capability (adds its own entitlement) rather than
   just an Info.plist key, add it now. I can't confirm which from this
   environment; Xcode's capability list is the ground truth.
6. StoreKit testing (for the paywall) — `StepAlarm/StepAlarm.storekit` is
   included with both products (`alarm7.pro.monthly` $4.99,
   `alarm7.pro.yearly` $29.99) already defined, so the paywall can load
   real `Product` objects and complete test purchases without any App
   Store Connect setup. Drag it in, then **Product → Scheme → Edit
   Scheme → Run → Options → StoreKit Configuration** → select it. (Real
   App Store Connect products with these same IDs still need to be created
   before you can ship/TestFlight — the local file is only for on-device
   testing.)
7. App icon and Wake Up screen walking icon — both are already wired up as
   a real asset catalog at `StepAlarm/StepAlarm/Assets.xcassets/`
   (`AppIcon.appiconset` with the 1024×1024 marketing icon, `WalkingIcon.imageset`
   already set to **Render As: Template Image** so `.foregroundStyle` tints
   it in code). Just drag the whole `Assets.xcassets` folder in alongside
   the other files — no manual "New Image Set" steps needed. If Xcode's
   own template project already generated its own `Assets.xcassets`,
   delete that one first so there's only one in the target.
9. Build target: your physical iPhone (not simulator — AlarmKit and
   CMPedometer don't work there). Run.

## Setup — Live Activity validation (added per the design spec)

The design spec's Screen 3 needs a live step counter on the Lock Screen
without unlocking. That requires a **Widget Extension** target — Live
Activity UI can't live in the main app target.

7. **File → New → Target → Widget Extension.** Name it `StepAlarmWidget`.
   When Xcode asks, check "Include Live Activity" (or if it scaffolds a
   `TestAppAttributes.swift` / default widget files, delete those — we
   have our own).
8. Drag in from this folder's `StepAlarmWidget/` subdirectory:
   - `StepAlarmWidgetLiveActivity.swift`
   - `StepAlarmWidgetBundle.swift` (Xcode's template likely already made
     one of these — delete the template's version, keep this one)
9. Drag in `Shared/StepAlarmActivityAttributes.swift` and **check both
   target membership boxes** (StepAlarm app AND StepAlarmWidget extension)
   in the File Inspector on the right. This is the easy step to miss — if
   you skip it, expect "cannot find type in scope" or a silent runtime
   mismatch instead of a clean build error.
10. On the **main app target** (not the widget target): **Info** tab → add
    `NSSupportsLiveActivities` = **YES**. Without this, `Activity.request`
    throws immediately.
11. Also on the main app target: **Signing & Capabilities**, make sure the
    widget extension target is signed with the same team.

## A note on how AlarmKit actually renders the alert

The brief describes Phase 1 as needing "Full-screen alert UI with one Stop
button." With AlarmKit, you don't draw that screen yourself — the system
renders a Clock-app-style full-screen alert based on the
`AlarmPresentation.Alert` you configure (title + stop button), and it draws
over the lock screen / whatever app is foregrounded, independent of your
app's UI. `AlarmScheduler.swift` configures that presentation; there's no
separate SwiftUI view for the ringing state in this codebase.

## Confidence flag

I don't have a Mac in this environment to compile against the real AlarmKit
SDK, so I can't guarantee every type/method name here is exactly right —
this is a very new framework (iOS 26 / WWDC 2025) with limited footprint in
what I was trained on. The architecture is right: authorize once, build an
`AlarmAttributes`/`AlarmPresentation.Alert`, call
`AlarmManager.shared.schedule(id:configuration:)`, silence via an
in-process `LiveActivityIntent`. If Xcode's autocomplete disagrees with an
exact name (e.g. whether `AlarmConfiguration` nests under `AlarmManager`),
trust Xcode — jump to definition on `AlarmManager` and adjust. Apple's
official AlarmKit sample project and the WWDC25 "Wake up to the AlarmKit
API" session are the ground truth if anything doesn't compile.

## Phase 1 gate — all four must pass on a real iPhone

Tap "Set alarm 2 minutes from now," then within that window:

1. Lock the phone — alarm still rings at T+2min.
2. Force-quit the app from the app switcher — alarm still rings.
3. Turn on Silent mode — alarm still rings audibly.
4. Turn on a Focus mode — alarm still rings.

If any of these fail, that's the signal something fell back to a
notification-style path instead of a true AlarmKit-scheduled alarm — fix it
before moving to Phase 2 (step counting). Don't build UI or settings yet.

Once all four pass, let me know and I'll build Phase 2 (standalone
CMPedometer step counter screen).

## The hard technical question — validate this now too, not after Phase 1

The design spec calls for a live-updating step counter directly on the
Lock Screen, without unlocking or opening the app, driven by a Live
Activity attached to the alarm. This is the single riskiest unknown in
the whole project, and it needs a real-device answer before any of the
black/white/red UI gets built. There are two separate things to prove,
tested separately on purpose so a failure tells you which half broke:

**Test A — "counter-only."** Tap "Test A" in the app, then **lock the
phone immediately.** Watch the Lock Screen for the full 30 seconds.
- If the number visibly counts 1, 2, 3... up to 15 once per second: the
  core mechanism works.
- If it appears but freezes the moment you lock the phone: the update
  loop is getting suspended in the background. That means the real
  implementation must drive updates from CMPedometer's own step-delivery
  callback (which is designed to wake a suspended app for a physical
  event) instead of a timer loop — a fixable, known pattern, just
  different code than what's here now.
- If no Live Activity appears on the Lock Screen at all: check that
  `NSSupportsLiveActivities` is set, and that Settings → StepAlarm → Live
  Activities is enabled.

**Test B — "alarm + Live Activity together."** Tap "Test B." This
schedules the real AlarmKit test alarm for 30 seconds out AND starts the
same counter. Lock the phone. When the alarm fires:
- Does the live counter stay visible / update while the AlarmKit alert is
  ringing, or does AlarmKit's own full-screen alert cover it entirely?
- Does anything visually conflict or glitch?

**If both come back positive:** the design as written (live count on
Lock Screen, no unlock needed) is buildable — proceed with Phase 2/3 as
planned, feeding real CMPedometer data into this same Live Activity
mechanism instead of the timer loop.

**If it doesn't work:** the spec's own documented fallback applies — the
alarm screen shows a single "start walking" prompt, tapping it opens the
app, and the counter runs there instead of on the Lock Screen. Tell me
which result you got and I'll build whichever path is real.

### Confidence flag on this part specifically

Plain ActivityKit Live Activities updating ~once/sec from an in-process
loop is well-documented, stable API since iOS 16.1 — I'm confident in
`StepAlarmWidgetLiveActivity.swift` and the ActivityKit calls themselves.
What I'm genuinely unsure about is the *AlarmKit* side: whether an
AlarmKit-fired alarm is itself backed by a Live Activity you attach
custom content to, or whether (as built here) it's a fully independent
Live Activity that merely happens to fire alongside the alarm. Test B is
designed to surface that difference empirically, because I can't verify
it by reading documentation alone.

## How the app works now (walk to dismiss)

1. **+** (or the empty-state button) adds an alarm: time (follows your
   device's 12h/24h setting), steps to dismiss, repeat days, label, sound,
   vibration, snooze — laid out as a grouped list under the time wheel. The
   toggle schedules/cancels the real AlarmKit alarm; tap a row to edit;
   swipe a row left to delete.
2. **Free tier:** up to 3 alarms, capped at 15 steps, no repeat (every free
   alarm is one-time — it turns itself off after ringing). The Repeat
   section, and steps above 15, show a lock icon and open the paywall.
3. **Pro:** unlimited alarms, up to 30 steps, full repeat (every day,
   weekdays, custom days). If a Pro subscription lapses, any repeating
   alarms quietly become one-time instead of being deleted.
4. When it rings, the system alert has **Stop** and **Walk**.
   - **Walk** opens the app on the Wake Up screen. Real steps are counted
     (CMPedometer); reaching the goal silences the alarm, with a "Good
     morning" screen after.
   - **Stop** silences it, then (unless that alarm's Snooze is off) it
     **rings again 20 seconds later** until the steps are done.
   - A "Can't walk? Hold to skip" control on the Wake Up screen lets someone
     dismiss the alarm without walking if held for 10 seconds — an
     accessibility/emergency out, not a way to casually skip.
5. If the app is opened while an alarm is ringing, it jumps straight to the
   Wake Up screen.
6. After a **free-tier** one-time alarm is dismissed, the "Good morning"
   screen offers "Set again for tomorrow at [time]?" with a one-tap Yes, plus
   a small "Make it repeat automatically with Pro" link to the paywall.
7. Settings (gear icon): default step goal, vibration, snooze-by-default,
   permission status with a link to the Settings app, Pro/restore, support
   and legal links.

### Quick test plan (real iPhone)

1. Long-press the **gear icon** → Tests → "Try the Wake Up screen" — steps
   count up by themselves, ends on "Good morning".
2. Tests → "Ring a 15-step alarm in 15 seconds", lock the phone.
3. When it rings: tap **Stop** → it should ring again after ~20s (unless
   you turned Snooze off for that alarm, in which case it should stay off).
4. Tap **Walk**, walk the required steps → alarm stops, "Good morning"
   screen appears; if this was a free one-time alarm, the "Set again for
   tomorrow?" offer should also appear.
5. Hold "Can't walk? Hold to skip" for the full 10 seconds mid-ring —
   confirm it dismisses the alarm.
6. Add a 4th alarm on the free tier — confirm the paywall opens instead.
   Try setting steps above 15, and try tapping Repeat — both should show a
   lock and open the paywall on the free tier.
7. Add a real alarm 2 minutes ahead; toggle it off/on; swipe to delete it.
8. Try both light and dark mode (Settings app → Developer / Display &
   Brightness) — every screen should adapt correctly now, not just dark.

Not built: the Lock Screen Live Activity is still only the Test A/B demo —
it does not show your real step count during an alarm. Onboarding screens
and the full paywall visual redesign (headline, free trial, fixed bottom
button) from the later polish pass were also not built — the paywall works
and enforces the real limits, but its layout is from an earlier pass.
