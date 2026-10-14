import SwiftUI

struct GetStartedView: View {
    // Observe the shortcut without running commands during first-time setup.
    @StateObject private var hotkeys = HotkeyManager()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 124))
                .foregroundStyle(hotkeys.rightCommandDown ? Color.green : Color.secondary)
                .accessibilityLabel("Right Command key")
                .accessibilityValue(hotkeys.rightCommandDown ? "Pressed" : "Not pressed")
            Spacer()
            Text("Press the right Command key to activate your assistant")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
        .onAppear { hotkeys.start() }
        .onDisappear { hotkeys.stop() }
    }
}
