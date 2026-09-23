import SwiftUI

@main
struct StepAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // App-wide tint: without this, anything that doesn't set its
                // own color (menu pickers, toolbar buttons, links) falls
                // back to iOS system blue, which is exactly the stray color
                // this app is trying to avoid outside the step ring.
                .tint(Theme.neutralActive)
                // The app's look is black everywhere, whatever the phone's
                // Light/Dark setting.
                .preferredColorScheme(.dark)
        }
    }
}
