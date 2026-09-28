import CoreMotion
import StoreKit
import SwiftUI
import UIKit

/// Settings: alarm defaults, permission status, Pro/restore, and support.
struct SettingsView: View {
    var onClose: () -> Void
    var onShowPaywall: () -> Void

    private var settings = AppSettings.shared
    private var scheduler = AlarmScheduler.shared
    private var subscriptions = SubscriptionStore.shared
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showManageSubscription = false

    init(onClose: @escaping () -> Void, onShowPaywall: @escaping () -> Void) {
        self.onClose = onClose
        self.onShowPaywall = onShowPaywall
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(
                        value: Binding(get: { settings.defaultSteps }, set: { settings.defaultSteps = $0 }),
                        in: 1...(subscriptions.hasFullAccess ? 30 : 15)
                    ) {
                        Label {
                            Text("Default steps: \(settings.defaultSteps)")
                        } icon: {
                            Image("WalkingIcon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 15)
                        }
                    }

                    Toggle(isOn: Binding(get: { settings.vibrationEnabled }, set: { settings.vibrationEnabled = $0 })) {
                        Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .tint(Theme.neutralActive)
                } header: {
                    Text("Defaults")
                } footer: {
                    Text(settings.vibrationEnabled
                         ? "Vibration is on for every alarm. Turn it off here if you don't want it."
                         : "Vibration is off for every alarm. Turn it on here any time.")
                }

                Section {
                    permissionRow("Alarms", systemImage: "alarm", granted: scheduler.isAuthorized)
                    permissionRow(
                        "Motion & Fitness", systemImage: "figure.walk.motion",
                        granted: CMPedometer.authorizationStatus() == .authorized
                    )
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings App", systemImage: "gearshape")
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Both are required for alarms to ring reliably and count real steps.")
                }

                if SubscriptionStore.proVisible {
                    Section("Subscription") {
                        if !SubscriptionStore.purchasesEnabled {
                            HStack {
                                Label("Alarm7 Premium", systemImage: "crown.fill")
                                Spacer()
                                Text("Coming soon")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        } else if subscriptions.isPro {
                            Label("Alarm7 Premium is active", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.textPrimary)
                            Button { showManageSubscription = true } label: {
                                Label("Manage or Cancel Subscription", systemImage: "creditcard")
                            }
                        } else {
                            Button { onShowPaywall() } label: {
                                Label("Get Premium: Lock apps", systemImage: "crown.fill")
                            }
                        }
                        if SubscriptionStore.purchasesEnabled {
                            Button {
                                Task { await subscriptions.restore() }
                            } label: {
                                Label("Restore Purchases", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                Section("Support") {
                    if let url = URL(string: "mailto:sami@veehealth.ca") {
                        Link(destination: url) {
                            Label("Contact Support", systemImage: "envelope")
                        }
                    }
                    Button { showTerms = true } label: {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    Button { showPrivacy = true } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .sheet(isPresented: $showTerms) {
                LegalDocumentView(title: "Terms of Use", content: LegalText.terms) { showTerms = false }
            }
            .sheet(isPresented: $showPrivacy) {
                LegalDocumentView(title: "Privacy Policy", content: LegalText.privacy) { showPrivacy = false }
            }
        }
    }

    private func permissionRow(_ title: String, systemImage: String, granted: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(granted ? "Allowed" : "Not allowed")
                .font(.subheadline)
                .foregroundStyle(granted ? Theme.textSecondary : Theme.accent)
        }
    }
}

#Preview {
    SettingsView(onClose: {}, onShowPaywall: {})
}
