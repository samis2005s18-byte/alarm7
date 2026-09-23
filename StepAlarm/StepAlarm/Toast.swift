import SwiftUI

/// Lightweight, auto-dismissing confirmation banner (e.g. "Alarm set for
/// 7h 12m from now"). One shared modifier so every screen shows these the
/// same way.
struct ToastMessage: Equatable {
    var text: String
    var systemImage: String = "checkmark.circle.fill"
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Label(message.text, systemImage: message.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .background(.black.opacity(0.9), in: Capsule())
                    .padding(.bottom, Theme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.easeOut(duration: 0.25)) { self.message = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: message)
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
