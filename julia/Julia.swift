import SwiftUI

@main struct Julia: App {
    @StateObject private var audioManager = Audio()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
        }
    }
}
