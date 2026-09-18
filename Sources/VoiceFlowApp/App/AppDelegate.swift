import Cocoa
import SwiftUI
import KeyboardShortcuts

@available(macOS 14.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var hotkeyMonitor: Any?
    private let appModel = AppModel()
    private var settingsWindow: NSWindow?
    static weak var shared: AppDelegate?
    
    static var sharedAppModel: AppModel {
        return (NSApp.delegate as? AppDelegate)?.appModel ?? AppModel()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        print("🚀 VoiceFlowApp: applicationDidFinishLaunching START")
        
        // Activate app FIRST before creating status items
        NSApp.activate(ignoringOtherApps: true)
        
        print("🔧 Setting up menu bar...")
        setupMenuBar()
        
        print("🔧 Setting up hotkeys...")
        setupGlobalHotkeys()
        
        print("🔧 Registering notifications...")
        registerForNotifications()
        
        // NOW set accessory policy after UI is ready
        // If accessibility or mic permission is not granted yet, open Settings so user can grant it immediately
        let mic = PermissionService.shared.checkMicrophonePermission()
        let ax = PermissionService.shared.checkAccessibilityPermission()
        if !mic || !ax {
            showSettings()
        }
        
        print("✅ VoiceFlowApp: applicationDidFinishLaunching COMPLETE")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 VoiceFlowApp: applicationWillTerminate")
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupMenuBar() {
        print("🔧 setupMenuBar() called")
        menuBarController = MenuBarController(appModel: appModel) { [weak self] in
            self?.showSettings()
        }
        menuBarController?.setup()
        print("✅ setupMenuBar() complete")
    }

    func showSettings() {
        let settingsWindow = settingsWindow ?? makeSettingsWindow()
        self.settingsWindow = settingsWindow
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow() -> NSWindow {
        let settingsView = SettingsView().environmentObject(appModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: settingsView)
        window.title = "VoiceFlow Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 840, height: 600)
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
    
    private func setupGlobalHotkeys() {
        print("🔧 setupGlobalHotkeys() called")
        let settings = SettingsStore.shared
        print("🔑 Starting hotkey monitoring (mode: \(settings.hotkeyMode), defaults: \(settings.useDefaultHotkeys))")
        HotkeyService.shared.startMonitoring(
            mode: settings.hotkeyMode,
            useDefaults: settings.useDefaultHotkeys,
            pushToTalkKeyDown: { [weak self] in
                self?.appModel.startPushToTalk()
            },
            pushToTalkKeyUp: { [weak self] in
                self?.appModel.stopPushToTalk()
            },
            continuousToggle: { [weak self] in
                self?.appModel.toggleContinuous()
            }
        )
        print("✅ Hotkey monitoring started successfully")
    }
    
    private func registerForNotifications() {
        print("📬 Registering notifications...")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartRecording),
            name: .startDictation,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopRecording),
            name: .stopDictation,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCancelRecording),
            name: .cancelDictation,
            object: nil
        )
        print("✅ Notifications registered")
    }
    
    @objc private func handleStartRecording(_ notification: Notification) {
        print("📬 Notification: startRecording")
        Task { @MainActor in
            appModel.startRecording()
        }
    }
    
    @objc private func handleStopRecording(_ notification: Notification) {
        print("📬 Notification: stopRecording")
        Task { @MainActor in
            appModel.stopRecording()
        }
    }
    
    @objc private func handleCancelRecording(_ notification: Notification) {
        print("📬 Notification: cancelRecording")
        Task { @MainActor in
            appModel.cancelRecording()
        }
    }
}

extension Notification.Name {
    static let startDictation = Notification.Name("VoiceFlowApp.startDictation")
    static let stopDictation = Notification.Name("VoiceFlowApp.stopDictation")
    static let cancelDictation = Notification.Name("VoiceFlowApp.cancelDictation")
}
