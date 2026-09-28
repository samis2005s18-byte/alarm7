import StoreKit
import SwiftUI

/// Premium page: unlocks App Lock (the only paid feature). Yearly $29.99 and
/// Monthly $4.99 (prices come from the App Store; the fallbacks below only
/// show while they load).
struct PaywallView: View {
    var onClose: () -> Void

    private var store = SubscriptionStore.shared
    @State private var selectedID = SubscriptionStore.yearlyID
    @State private var showTerms = false
    @State private var showPrivacy = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.pressable)
                Spacer()
            }
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    SampleAppIcons(size: 60)
                        .padding(.top, 8)

                    VStack(spacing: Theme.Spacing.sm) {
                        Text(store.isPro ? "You're Premium" : "Alarm7 Premium")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Wake up, then stay off your phone.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        feature("lock.fill", "Lock any apps you choose: TikTok, Instagram, Snapchat and more")
                        feature("hourglass", "Keep them locked for 10 minutes to 2 hours after you wake up")
                        feature("lock.open.fill", "They open again by themselves when the time is up")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    freeForEveryone

                    if store.isPro {
                        Text("Thanks for subscribing. Manage your plan in Settings > Apple ID > Subscriptions.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        VStack(spacing: 12) {
                            planCard(
                                id: SubscriptionStore.yearlyID,
                                title: "Yearly",
                                price: store.yearly?.displayPrice ?? "$29.99",
                                period: "per year",
                                badge: savingsBadge
                            )
                            planCard(
                                id: SubscriptionStore.monthlyID,
                                title: "Monthly",
                                price: store.monthly?.displayPrice ?? "$4.99",
                                period: "per month",
                                badge: nil
                            )
                        }
                    }

                    if SubscriptionStore.purchasesEnabled, let message = store.errorMessage {
                        Text(message)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.bottom, 16)
            }

            if !store.isPro {
                Text("Auto-renews until cancelled. Cancel anytime in Settings.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 8)

                Button {
                    guard SubscriptionStore.purchasesEnabled else { return }
                    guard let product = selectedProduct else {
                        Task { await store.loadProducts() }
                        return
                    }
                    Task { await store.purchase(product) }
                } label: {
                    Group {
                        if !SubscriptionStore.purchasesEnabled {
                            Label("Coming soon", systemImage: "lock.fill")
                                .font(.headline)
                        } else if store.isBusy {
                            ProgressView().tint(Theme.background)
                        } else {
                            Text(selectedProduct == nil ? "Retry loading plans" : "Continue")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.textPrimary, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(store.isBusy || !SubscriptionStore.purchasesEnabled)

                Button("Restore Purchases") {
                    guard SubscriptionStore.purchasesEnabled else { return }
                    Task { await store.restore() }
                }
                    .buttonStyle(.pressable)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)

                HStack(spacing: 6) {
                    Button("Terms of Use") { showTerms = true }
                    Text("·")
                    Button("Privacy Policy") { showPrivacy = true }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)

                Text("Payment is charged to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings > Apple ID > Subscriptions.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if SubscriptionStore.purchasesEnabled { await store.start() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { onClose() }
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentView(title: "Terms of Use", content: LegalText.terms) { showTerms = false }
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(title: "Privacy Policy", content: LegalText.privacy) { showPrivacy = false }
        }
    }

    // MARK: - Pieces

    private var selectedProduct: Product? {
        selectedID == SubscriptionStore.yearlyID ? store.yearly : store.monthly
    }

    /// "SAVE 50%" computed from the real prices once both plans have loaded.
    private var savingsBadge: String {
        guard let monthly = store.monthly, let yearly = store.yearly else { return "BEST VALUE" }
        let full = Double(truncating: monthly.price as NSDecimalNumber) * 12
        let paid = Double(truncating: yearly.price as NSDecimalNumber)
        guard full > 0, paid < full else { return "BEST VALUE" }
        return "SAVE \(Int(((1 - paid / full) * 100).rounded()))%"
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.textPrimary)
        }
        .font(.body)
    }

    /// Makes it plain that Premium is only App Lock: the alarm itself costs nothing.
    private var freeForEveryone: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("Free for everyone", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Unlimited alarms, up to 30 steps, repeat days and every other alarm feature. You only pay if you want App Lock.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func planCard(id: String, title: String, price: String, period: String, badge: String?) -> some View {
        let selected = selectedID == id
        return Button {
            Theme.tap()
            selectedID = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white, in: Capsule())
                        }
                    }
                    Text("\(price) \(period)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(selected ? Theme.textPrimary : Theme.cardStroke, lineWidth: selected ? 2 : 1)
            )
            .animation(.spring(duration: 0.3, bounce: 0.2), value: selected)
        }
        .buttonStyle(.pressable)
    }
}

#Preview {
    PaywallView(onClose: {})
}
