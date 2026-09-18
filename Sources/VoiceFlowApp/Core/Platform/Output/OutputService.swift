import Foundation
import ApplicationServices
import AppKit
import OSLog

actor OutputService {
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "OutputService")
    
    private var targetApp: NSRunningApplication?
    private var targetElement: AXUIElement?
    
    func captureTargetContext() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let app = frontmost, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = app
        } else {
            // Find the most recently active non-VoiceFlow app
            targetApp = NSWorkspace.shared.runningApplications.first {
                $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
        }
        
        guard let app = targetApp else { return }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            targetElement = (element as! AXUIElement)
            logger.info("Captured target context: \(app.localizedName ?? "Unknown")")
        } else {
            logger.warning("Could not capture focused element")
            targetElement = nil
        }
    }
    
    func insertText(_ text: String, mode: OutputMode) async {
        guard !text.isEmpty else { return }
        
        switch mode {
        case .pasteAtCursor:
            await pasteAtCursor(text)
        case .clipboardOnly:
            await copyToClipboard(text)
        }
    }
    
    private func pasteAtCursor(_ text: String) async {
        let hasAccessibility = AXIsProcessTrusted()
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        guard hasAccessibility else {
            logger.error("Accessibility is not granted; cannot insert transcript into the active app")
            return
        }
        
        // Ensure the target application where user pointed has frontmost focus
        let appToActivate = (targetApp?.bundleIdentifier != Bundle.main.bundleIdentifier ? targetApp : nil)
            ?? NSWorkspace.shared.runningApplications.first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            ?? NSWorkspace.shared.frontmostApplication
            
        if let app = appToActivate, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 120_000_000)
        } else {
            logger.error("No non-VoiceFlow application was available for text insertion")
            return
        }

        await waitForModifierKeysReleased()
        
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        cmdVDown?.flags = .maskCommand
        cmdVDown?.post(tap: .cghidEventTap)
        
        // 35ms key down duration so target app's event queue processes the synthetic paste reliably
        try? await Task.sleep(nanoseconds: 35_000_000)
        
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        cmdVUp?.flags = .maskCommand
        cmdVUp?.post(tap: .cghidEventTap)
        
        let shouldRestore = await MainActor.run { SettingsStore.shared.restoreClipboard }
        if shouldRestore, let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if NSPasteboard.general.string(forType: .string) == text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(previous, forType: .string)
                }
            }
        }
        
        logger.info("Text pasted successfully via synthetic Command+V")
    }
    
    private func validateTarget() -> Bool {
        guard let element = targetElement else { return false }
        
        var role: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        guard result == .success, let roleString = role as? String else { return false }
        
        let allowedRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXSearchField",
            "AXWebArea",
            "AXTextView"
        ]
        
        let isAllowed = allowedRoles.contains(roleString)
        
        if !isAllowed {
            logger.warning("Target role not allowed for paste: \(roleString)")
        }
        
        return isAllowed
    }
    
    private func waitForModifierKeysReleased() async {
        for _ in 0..<20 {
            let flags = await MainActor.run { NSEvent.modifierFlags }
            if flags.intersection([.command, .option, .control, .shift]).isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    private func copyToClipboard(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Text copied to clipboard")
    }
    
    private func showTranscriptRecovery(_ text: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Could not auto-insert text"
            alert.informativeText = "The text has been copied to your clipboard. Paste manually with ⌘V."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show Transcript")
            alert.alertStyle = .informational
            
            if alert.runModal() == .alertSecondButtonReturn {
                self.showTranscriptWindowOnMainActor(text)
            }
        }
    }
    
    @MainActor
    private func showTranscriptWindowOnMainActor(_ text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceFlow - Transcript"
        window.center()
        
        let textView = NSTextView(frame: window.contentView!.bounds)
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        window.contentView?.addSubview(scrollView)
        window.makeKeyAndOrderFront(nil)
    }
}
