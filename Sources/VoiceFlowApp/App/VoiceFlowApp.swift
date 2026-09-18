import SwiftUI
import KeyboardShortcuts

@available(macOS 14.0, *)
@main
struct VoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppDelegate.sharedAppModel)
                .frame(minWidth: 520, minHeight: 480)
        }
    }
}
