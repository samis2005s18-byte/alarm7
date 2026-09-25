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

    Last updated: September 24, 2026

    These Terms of Use ("Terms") are an agreement between you and Sami ("we," "us," "our"), the developer of Alarm7 ("the app"). By downloading or using the app, you agree to these Terms. If you don't agree, don't use the app.

    **1. The App**

    Alarm7 is an alarm clock app that turns off only after you walk a set number of steps, counted using your device's motion sensor.

    **2. Eligibility**

    You must be at least 13 years old to use the app. If you are under the age of majority where you live, you may use the app only with the involvement of a parent or guardian, who agrees to these Terms on your behalf.

    **3. License**

    We give you a personal, non-transferable, non-exclusive license to use the app on Apple devices you own or control, as allowed by Apple's App Store Terms. You may not copy, modify, reverse engineer, resell, or distribute the app.

    **4. Price**

    Alarm7 is currently free, and there is nothing to buy in the app. If we add paid features in the future, we will update these Terms first, and anything you pay for will be processed by Apple and clearly shown in the app before you buy it.

    **5. Alarm Reliability**

    We work hard to make Alarm7 reliable, but no alarm app can be guaranteed to work every time. Alarms may fail or be delayed because of device settings, low battery, a powered-off device, software updates, silent mode, Focus modes, permissions being turned off, or other things outside our control. Do not rely on Alarm7 as your only alarm for anything important, such as work, travel, exams, medical needs, or taking medication. We are not responsible for any loss caused by an alarm not ringing, ringing late, or not turning off.

    **6. Safety**

    Alarm7 requires you to get up and walk. You are responsible for walking safely. Turn on a light, watch for stairs and obstacles, and don't walk if you feel dizzy, unwell, or unsteady. Don't use Alarm7 if walking right after waking up is unsafe for you because of a health condition, disability, or injury. Alarm7 is not a medical or fitness device and does not give medical advice. Step counts may not be exact.

    **7. Acceptable Use**

    You agree not to misuse the app, interfere with how it works, or use it for anything illegal.

    **8. Ownership**

    The app, its name, design, code, and content belong to us. These Terms don't give you any ownership rights.

    **9. Disclaimer of Warranties**

    The app is provided "as is" and "as available," without warranties of any kind, to the fullest extent allowed by law. We don't promise the app will be error-free, uninterrupted, or meet every need.

    **10. Limitation of Liability**

    To the fullest extent allowed by law, we are not liable for any indirect, incidental, special, or consequential damages, including missed appointments, lost income, or injury from walking, arising from your use of the app. Our total liability to you for any claim will not be more than the amount, if any, you paid for the app in the 12 months before the claim. Some places don't allow these limits, so they may not fully apply to you.

    **11. Apple**

    These Terms are between you and us, not Apple. Apple is not responsible for the app or its content, and has no obligation to provide support or maintenance for it. If the app fails to meet any warranty, you may notify Apple for a refund of the purchase price, and Apple has no other warranty obligation. Apple is not responsible for any claims relating to the app, including product liability, legal compliance, or intellectual property claims. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you. You confirm you are not in a country under a U.S. government embargo and are not on any U.S. government list of prohibited or restricted parties.

    **12. Ending Use**

    You can stop using the app anytime by deleting it. We may stop offering or updating the app at any time.

    **13. Changes to These Terms**

    We may update these Terms. The latest version will always be on this page with a new "Last updated" date. Continuing to use the app means you accept the updated Terms.

    **14. Governing Law**

    These Terms are governed by the laws of the Province of Ontario and the federal laws of Canada that apply there. Nothing in these Terms takes away any consumer protection rights you have under the laws of where you live.

    **15. General**

    If any part of these Terms is found unenforceable, the rest stays in effect. These Terms, together with our Privacy Policy, are the entire agreement between you and us about the app.

    **16. Contact**

    Questions? Email sami@veehealth.ca
    """

    static let privacy = """
    **Alarm7 Privacy Policy**

    Last updated: September 24, 2026

    Alarm7 ("the app") is built by Sami ("we," "us"). This policy explains how the app handles your information.

    **Information We Collect**

    We do not collect, store, or share any personal information. Alarm7 has no accounts, no ads, no analytics, and no tracking.

    **Motion & Step Data**

    Alarm7 uses your device's motion sensor to count steps so it can turn off your alarm. This data is processed only on your device and is never sent to us or anyone else.

    **App Locking (Screen Time)**

    If you use "Lock apps after I wake up", Alarm7 uses Apple's Screen Time to lock the apps you choose. Apple never tells Alarm7 which apps you picked; the app only receives private codes it can use to show and lock them, and these stay on your device.

    **Alarms & Settings**

    Your alarms, step goals, and settings are stored only on your device. If you delete the app, this data is deleted too.

    **Notifications & Alarms**

    Alarm7 uses Apple's alarm and notification features only to ring your alarms. We do not send marketing messages.

    **Purchases**

    Alarm7 does not currently offer in-app purchases. If we add them in the future, they will be processed entirely by Apple. We would never see or receive your payment details, name, or Apple ID, and this policy will be updated before any such change.

    **Third Parties**

    Alarm7 does not use any third-party services that collect your data.

    **Children's Privacy**

    Alarm7 does not knowingly collect information from anyone, including children under 13.

    **Your Choices**

    You can turn off Motion & Fitness access, alarm permissions, or notifications anytime in your iPhone Settings. Some features, like step-based alarm dismissal, won't work without them.

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
