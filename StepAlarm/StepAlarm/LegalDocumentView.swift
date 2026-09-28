import SwiftUI

/// Terms of Use and Privacy Policy, shown in-app so both links Apple
/// requires on the paywall resolve to real content without needing any
/// external hosting.
struct LegalDocumentView: View {
    var title: String
    var content: String
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(LocalizedStringKey(content))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

enum LegalText {
    static let terms = """
    **Alarm7 Terms of Use**

    Last updated: September 27, 2026

    These Terms of Use ("Terms") are an agreement between you and Sami ("we," "us," "our"), the developer of Alarm7 ("the app"). By downloading or using the app, you agree to these Terms. If you don't agree, don't use the app.

    **1. The App**

    Alarm7 is an alarm clock app that turns off only after you walk a set number of steps, counted using your device's motion sensor. With an Alarm7 Premium subscription, it can also lock apps you choose for a while after you wake up ("App Lock").

    **2. Eligibility**

    You must be at least 13 years old to use the app. If you are under the age of majority where you live, you may use the app only with the involvement of a parent or guardian, who agrees to these Terms on your behalf.

    **3. License**

    We give you a personal, non-transferable, non-exclusive license to use the app on Apple devices you own or control, as allowed by Apple's App Store Terms and Apple's Licensed Application End User License Agreement (apple.com/legal/internet-services/itunes/dev/stdeula). You may not copy, modify, reverse engineer, resell, or distribute the app.

    **4. Free Features and Alarm7 Premium**

    Alarm7 is free to download, and every alarm feature is free, including unlimited alarms, step goals, repeat days, and Emergency stop.

    App Lock is the only paid feature. It needs an Alarm7 Premium subscription:

    • Plans: Monthly or Yearly. The price for your country is shown in the app before you buy.
    • Payment: charged to your Apple ID when you confirm the purchase.
    • Auto-renewal: your subscription renews automatically for the same length and price unless you turn off auto-renew at least 24 hours before the end of the current period. Your Apple ID is charged within 24 hours before each renewal.
    • Cancelling: manage or cancel anytime in Settings > [your name] > Subscriptions. Cancelling stops future renewals; you keep Premium until the end of the period you already paid for.
    • Price changes: if the price changes, Apple will tell you first and, where required, ask you to agree before you are charged the new price.
    • Refunds: all payments are handled by Apple, and refunds are decided by Apple under its policies. You can request one at reportaproblem.apple.com.
    • Restoring: use "Restore Purchases" in the app to get Premium back on a new or reset device signed in with the same Apple ID.
    • When Premium ends: App Lock stops locking apps. Your alarms and every free feature keep working.

    **5. App Lock**

    App Lock uses Apple's Screen Time and needs your permission to work. After you walk off an alarm that has App Lock turned on, the apps you chose stay locked for the time you picked (1 minute to 1 hour), then open again by themselves.

    • Locking and unlocking are done by iOS. Because of iOS, battery, or device settings, apps may sometimes unlock a little early or late, or not lock at all.
    • Don't lock apps you may need in an emergency. Alarm7 never blocks emergency calls.
    • You can always remove App Lock by turning off Screen Time access for Alarm7 in the Settings app, or by deleting Alarm7.
    • App Lock is a self-control tool, not a parental control, and isn't meant to manage someone else's device.

    **6. Alarm Reliability**

    We work hard to make Alarm7 reliable, but no alarm app can be guaranteed to work every time. Alarms may fail or be delayed because of device settings, low battery, a powered-off device, software updates, silent mode, Focus modes, permissions being turned off, or other things outside our control. Do not rely on Alarm7 as your only alarm for anything important, such as work, travel, exams, medical needs, or taking medication. We are not responsible for any loss caused by an alarm not ringing, ringing late, or not turning off.

    **7. Safety**

    Alarm7 requires you to get up and walk. You are responsible for walking safely. Turn on a light, watch for stairs and obstacles, and don't walk if you feel dizzy, unwell, or unsteady. Don't use Alarm7 if walking right after waking up is unsafe for you because of a health condition, disability, or injury. Alarm7 is not a medical or fitness device and does not give medical advice. Step counts may not be exact.

    **8. Acceptable Use**

    You agree not to misuse the app, interfere with how it works, or use it for anything illegal.

    **9. Ownership**

    The app, its name, design, code, and content belong to us. These Terms don't give you any ownership rights.

    **10. Disclaimer of Warranties**

    The app is provided "as is" and "as available," without warranties of any kind, to the fullest extent allowed by law. We don't promise the app will be error-free, uninterrupted, or meet every need.

    **11. Limitation of Liability**

    To the fullest extent allowed by law, we are not liable for any indirect, incidental, special, or consequential damages, including missed appointments, lost income, or injury from walking, arising from your use of the app. Our total liability to you for any claim will not be more than the amount, if any, you paid for Alarm7 Premium in the 12 months before the claim. Some places don't allow these limits, so they may not fully apply to you.

    **12. Apple**

    These Terms are between you and us, not Apple. Apple is not responsible for the app or its content, and has no obligation to provide support or maintenance for it. If the app fails to meet any warranty, you may notify Apple for a refund of the purchase price, if any, and Apple has no other warranty obligation. Apple is not responsible for any claims relating to the app, including product liability, legal compliance, or intellectual property claims. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you. You confirm you are not in a country under a U.S. government embargo and are not on any U.S. government list of prohibited or restricted parties.

    **13. Ending Use**

    You can stop using the app anytime by deleting it. Deleting the app does not cancel a subscription; cancel it in Settings > [your name] > Subscriptions. We may stop offering or updating the app at any time.

    **14. Changes to These Terms**

    We may update these Terms. The latest version will always be on this page with a new "Last updated" date. Continuing to use the app means you accept the updated Terms.

    **15. Governing Law**

    These Terms are governed by the laws of the Province of Ontario and the federal laws of Canada that apply there. Nothing in these Terms takes away any consumer protection rights you have under the laws of where you live.

    **16. General**

    If any part of these Terms is found unenforceable, the rest stays in effect. These Terms, together with our Privacy Policy, are the entire agreement between you and us about the app.

    **17. Contact**

    Questions? Email sami@veehealth.ca
    """

    static let privacy = """
    **Alarm7 Privacy Policy**

    Last updated: September 27, 2026

    Alarm7 ("the app") is built by Sami ("we," "us"). This policy explains how the app handles your information.

    **Information We Collect**

    We do not collect, store, or share any personal information. Alarm7 has no accounts, no ads, no analytics, and no tracking. Nothing you do in the app is sent to us.

    **Motion & Step Data**

    Alarm7 uses your device's motion sensor to count steps so it can turn off your alarm. This data is processed only on your device and is never sent to us or anyone else.

    **App Lock (Screen Time)**

    If you use App Lock ("Lock apps after you wake up"), Alarm7 asks for Apple's Screen Time permission and uses it to lock the apps you choose. Apple never tells Alarm7 which apps you picked or how you use them. The app only receives private codes from Apple that it can use to show and lock those apps, and these codes stay on your device. Alarm7 does not see your Screen Time reports, browsing, or app usage. You can turn off Screen Time access for Alarm7 anytime in the Settings app.

    **Alarms & Settings**

    Your alarms, step goals, and settings are stored only on your device. If you delete the app, this data is deleted too.

    **Notifications & Alarms**

    Alarm7 uses Apple's alarm and notification features only to ring your alarms. We do not send marketing messages.

    **Purchases**

    Alarm7 Premium subscriptions are processed entirely by Apple. We never see or receive your payment details, name, email, or Apple ID. The app only asks Apple whether your subscription is active, and that answer stays on your device. Apple handles your purchase under Apple's own Privacy Policy (apple.com/privacy).

    **Third Parties**

    Alarm7 does not use any third-party services that collect your data.

    **Children's Privacy**

    Alarm7 does not knowingly collect information from anyone, including children under 13.

    **Your Choices**

    You can turn off Motion & Fitness, Alarms, Screen Time, or notification access anytime in your iPhone Settings. Some features won't work without them: step-based alarm dismissal needs Motion & Fitness, and App Lock needs Screen Time.

    **Your Rights**

    Because we don't collect personal information, we don't hold any data about you. If you have questions about your privacy rights, including under Canadian privacy law, contact us.

    **Changes to This Policy**

    If we update this policy, we'll post the new version here with a new "Last updated" date.

    **Contact Us**

    Email sami@veehealth.ca
    """
}

#Preview {
    LegalDocumentView(title: "Terms of Use", content: LegalText.terms, onClose: {})
}
