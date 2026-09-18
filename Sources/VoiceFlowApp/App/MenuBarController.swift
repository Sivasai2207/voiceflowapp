import Cocoa
import SwiftUI
import OSLog
import Combine

@available(macOS 14.0, *)
final class NonActivatingFirstMousePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 14.0, *)
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

@available(macOS 14.0, *)
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var recordingPanel: NSPanel?
    private var popover: NSPopover?
    private weak var appModel: AppModel?
    private let showSettingsWindow: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "MenuBarController")
    
    init(appModel: AppModel, showSettingsWindow: @escaping () -> Void) {
        self.appModel = appModel
        self.showSettingsWindow = showSettingsWindow
    }
    
    func setup() {
        logger.info("Setting up menu bar controller")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use custom template app logo icon if available, fallback to waveform
            if let markURL = Bundle.module.url(forResource: "AppLogoMark", withExtension: "png"),
               let img = NSImage(contentsOf: markURL) {
                img.size = NSSize(width: 18, height: 16)
                img.isTemplate = true
                button.image = img
            } else if let img = NSImage(contentsOfFile: "/Users/sivasai/Projects/VoiceFlowApp/Sources/VoiceFlowApp/Resources/AppLogoMark.png") {
                img.size = NSSize(width: 18, height: 16)
                img.isTemplate = true
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceFlow")
                button.image?.isTemplate = true
            }
            
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            logger.info("Status item created successfully")
        } else {
            logger.error("Failed to create status item button")
        }
        
        setupPopover()
        setupRecordingPanel()
        observeRecordingState()
    }
    
    private func setupPopover() {
        guard let appModel else { return }
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.animates = true
        
        let menuBarView = MenuBarView(
            openSettings: { [weak self] in
                self?.popover?.performClose(nil)
                self?.openSettings()
            }
        ).environmentObject(appModel)
        
        popover.contentViewController = NSHostingController(rootView: menuBarView)
        self.popover = popover
    }
    
    private func setupRecordingPanel() {
        let panel = NonActivatingFirstMousePanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 74),
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        
        guard let appModel else {
            logger.error("Cannot create recording HUD without an app model")
            return
        }

        let hudView = WisprFlowHUD().environmentObject(appModel)
        let hostingView = FirstMouseHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 310, height: 74)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        
        panel.contentView = hostingView
        self.recordingPanel = panel
    }
    
    private func observeRecordingState() {
        guard let appModel else { return }

        Publishers.CombineLatest(appModel.$isRecording, appModel.$isProcessing)
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording, isProcessing in
                if isRecording || isProcessing {
                    self?.showRecordingHUD()
                } else {
                    self?.hideRecordingHUD()
                }
            }
            .store(in: &cancellables)
    }
    
    func showRecordingHUD(at screenPoint: CGPoint? = nil) {
        // Honor user setting to show HUD
        guard SettingsStore.shared.showHUD else { return }
        guard let panel = recordingPanel else { return }
        
        // Bottom-center of the screen above Dock (exact Wispr Flow placement)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = panel.frame.size
        let origin = CGPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 48
        )
        
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        logger.info("Wispr Flow blob shown at bottom center of screen")
    }
    
    func hideRecordingHUD() {
        guard let panel = recordingPanel, panel.isVisible else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
        logger.info("Recording bubble hidden")
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            // Left click toggles the popover
            togglePopover(sender)
        }
    }
    
    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "VoiceFlow", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit VoiceFlow", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func openSettings() {
        showSettingsWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
