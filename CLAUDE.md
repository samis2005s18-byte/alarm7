# Alarm7 (StepAlarm) — project memory

## Who you're working with
- The owner, Sami, is **not a developer**. Explain in plain, simple words, one step at a time, with exact clicks. Don't ask technical questions — pick sensible defaults and say what you chose.
- Sami usually tests on a real iPhone and sends photos/screenshots of problems.
- **Always ask before building or uploading anything** (Codemagic build, TestFlight, App Store). Sami has said: tell me before you build. Commit locally freely; push/build only when Sami says "build"/"push".
- Never type secrets (API keys, private keys, passwords) into websites for Sami, and never sign in to accounts — guide Sami to do those steps. Ask before clicking Save/Submit/Register on Apple or App Store Connect pages.
- Sami's Mac is a 2017 MacBook Pro on macOS 13 — **Xcode cannot be installed**. All builds happen in the cloud (Codemagic).

## The app
Alarm7 is an iPhone alarm that only turns off after the user walks a set number of steps (1–30).
- Bundle ID `sami.amlar`, display name **Alarm7**, iPhone only, iOS 26+ (uses AlarmKit), SwiftUI, Swift 5 mode.
- Widget extension `sami.amlar.StepAlarmWidget` (Live Activity test UI, not used in production).
- App Store Connect app: **Alarm7**, Apple ID 6814536946, SKU `alrm`. Developer team: SAMI ISMAIL (3826F95A25).

### Key behaviour (all in `StepAlarm/StepAlarm/`)
- `AlarmScheduler.swift` — AlarmKit scheduling. Every alarm also schedules **10 backup rings, one per minute**, cancelled only when the steps are walked, so the system X/Stop can't end an alarm. Stop re-rings after 20 s. A "ring window" blocks deleting/turning off a ringing alarm. `watchForRinging` opens the walk screen when an alarm fires while the app is open.
- `StopIntent.swift` — the alert's X opens the app on the walk screen (openAppWhenRun); Walk button does the same.
- `StepDetector.swift` — our own step detection from 50 Hz motion data (vertical bumps in a steady rhythm; rejects shaking by speed, strength, twisting and irregularity; turning around the vertical axis is ignored; resumes after pauses ≤4 s). Tuned with simulations; the first steps show instantly, confirmed steps never go backwards.
- Wake Up screen (`WakeUpView.swift`): until the first step it shows 3 walking tips (hold or pocket, normal pace, shaking doesn't count); for 3 s after StepDetector rejects shaking the status line turns red: "Shaking doesn't count. Walk instead." (`WalkSession.lastShakeDate`).
- `WalkSession.swift` — the walk: feeds StepDetector, finishes the alarm when the goal is reached, optional **Emergency stop** (per alarm, hold 10 s, red caution on Add Alarm page).
- `AlarmSound.swift` — in-app beeping + vibration while walking; keeps retrying until iOS lets it play (fixed "no sound until app killed" bug). Uses the audio background mode.
- `AddAlarmView.swift` — time wheel, big step number with −/+ and 10/15/20/30 chips, repeat days, Emergency stop. Vibration is NOT on this page (Sep 27): one switch in Settings, on by default, applies to every alarm. (Label field removed on purpose.)
- Pro/subscriptions: on `main` (1.0) they are **hidden** (`proVisible = false`, `purchasesEnabled = false`). On `app-lock` (1.1) the app is **fully free except App Lock, which is Premium** (Sep 27: `hasFullAccess` is always true; `hasPremium` gates App Lock; in-app wording says "Premium"; Add Alarm shows a PREMIUM badge, Instagram/TikTok/Snapchat tiles (real logo pictures `LogoInstagram`/`LogoTikTok`/`LogoSnapchat` in Assets when `AppConfig.showRealAppLogos` is on and they exist — not added yet, Sami to send a home-screen screenshot; drawn look-alikes otherwise) and a "PREMIUM ONLY" section header, an always-visible 1 min–1 hr slider (stops in `AppLocker.durations`) with the time in big type and "Apps stay locked for …"; Premium page lists what Premium adds (no "Free for everyone" box — Sami removed it); free users tapping it see the Premium page first). Plans: monthly `alarm7.pro.monthly` $4.99, yearly `alarm7.pro.annual` $29.99, both in the "Alarm7 Pro" group (`alarm7.pro.yearly` was made in a separate group by mistake — don't use it). Terms/Privacy on 1.1 describe the subscription.
- `AppConfig` (in `AppSettings.swift`): `showDeveloperTools` and `showStepDiagnostics` are off for store builds.
- Always dark theme. Permissions required to add alarms: Alarms + Motion & Fitness.
- `PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1). Terms/Privacy text in `LegalDocumentView.swift` say the app is free with nothing to buy.

## Branches (important)
- **`main` = version 1.0**, exactly what was submitted to the App Store (build 17). Only change it if Apple asks for a 1.0 fix.
- **`app-lock` = version 1.1** (MARKETING_VERSION 1.1), for TestFlight testing only.
- If Sami says "go back to 1.0", switch to `main`.

## Version 1.1 — "Lock apps after I wake up" (branch `app-lock`)
- On the **Add Alarm page** (per alarm): switch on, pick apps in Apple's picker (search or open Social), they show with their real icons; choose "Apps open again after" 10/15/30/60 min. Alarms with a lock show 🔒 in the list.
- After the alarm is walked off, the chosen apps are shielded (Screen Time / ManagedSettings); the Good morning screen says "Your apps are locked until …".
- `AppLock.swift` (AppLocker with per-alarm plans + AppLockAlarmSection UI), `StepAlarm/AppLockShared/AppLockNames.swift`, extension `StepAlarm/AppLockMonitor/` (`sami.amlar.AppLockMonitor`, DeviceActivity monitor) unlocks when time's up; the app also unlocks on open if the time passed.
- Apple's DeviceActivity windows must be ≥15 min, so a 10‑min lock starts the window in the past — **not yet verified on a device**.
- Family Controls (Distribution) is approved for the account and **enabled** on `sami.amlar` and `sami.amlar.AppLockMonitor`. Entitlement files: `StepAlarm/StepAlarm/StepAlarm.entitlements`, `StepAlarm/AppLockMonitor/AppLockMonitor.entitlements`.
- Switch to hide the whole feature: `AppConfig.appLockEnabled`.
- Ideas for later: make app locking part of Pro (needs Paid Apps agreement + subscriptions in App Store Connect).

## How building works (no Xcode)
- Code lives in this folder and on GitHub **private** repo `samis2005s18-byte/alarm7` (gh CLI is logged in on this Mac).
- `project.yml` (XcodeGen) generates the Xcode project in the cloud; `codemagic.yaml` workflow "StepAlarm to TestFlight" signs, builds, uploads to TestFlight (`submit_to_testflight: false` — internal testers only).
- Codemagic app: https://codemagic.io/app/6ab3458806173487f637a88b/settings → "Start new build" → choose branch (`main` or `app-lock`). Pushing to `main` or `app-lock` **starts a build automatically** (codemagic.yaml triggers), so only push after Sami says yes.
- Signing: App Store Connect API key integration named "StepAlarm key"; env var `CERTIFICATE_PRIVATE_KEY` in group `signing` (the key file is `~/Documents/StepAlarm-signing/certificate_private_key.txt` — never paste it anywhere yourself).
- Local check before building: `swiftc -parse` on changed files (the Mac's Swift is old, so `#Preview` errors are expected and fine). StepDetector can be tested locally with a small simulation (`swiftc main.swift StepDetector.swift`).
- Build numbers come from Codemagic's `BUILD_NUMBER`.

## App Store status (as of Sept 24, 2026)
- Version 1.0, **build 17**, submitted. Apple asked for more info (screen recording + 6 answers); Sami added the answers to App Review Notes, attached the video, and resubmitted. Waiting for review.
- Privacy policy (Google Doc, must be shared "Anyone with the link"): https://docs.google.com/document/d/1_5QsthejEJ2jFbw_NjQbvZDosow_1cawGzp1qi0uNOs/edit
- Reviewer tip in notes: turn on Emergency stop on the Add Alarm page to test without walking.
- Support email: sami@veehealth.ca
