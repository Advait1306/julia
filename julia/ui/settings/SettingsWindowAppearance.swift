import AppKit
import SwiftUI

/// Settings ignores SwiftUI's windowStyle, so hide only the native title text.
/// The titlebar, traffic lights, and window dragging stay managed by macOS.
struct SettingsWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> TitleVisibilityView { TitleVisibilityView() }

    func updateNSView(_ view: TitleVisibilityView, context: Context) {
        view.window?.titleVisibility = .hidden
    }

    final class TitleVisibilityView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titleVisibility = .hidden
        }
    }
}
