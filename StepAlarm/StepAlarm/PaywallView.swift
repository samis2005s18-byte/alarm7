import StoreKit
import SwiftUI

/// Subscription page: Yearly $29.99 and Monthly $4.99 (prices come from the
/// App Store; the fallbacks below only show while they load).
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
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 8)

                    Text(store.isPro ? "You're Alarm7 Pro" : "Alarm7 Pro")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    VStack(alignment: .leading, spacing: 14) {
                        feature("Unlimited alarms (3 free)")
                        feature("Step goals up to 30 (15 free)")
                        feature("Repeat schedules — daily, weekdays, custom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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

    private func feature(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.textPrimary)
        }
        .font(.body)
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
