import Foundation
import Carbon
import Cocoa
import OSLog
import KeyboardShortcuts

@preconcurrency import ApplicationServices

private nonisolated func checkAccessibilityPermissionStatic() -> Bool {
    let options: [CFString: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
}

private nonisolated func requestAccessibilityPermissionStatic() {
    let options: [CFString: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
}

@MainActor
final class HotkeyService: Sendable {
    static let shared = HotkeyService()
    
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "HotkeyService")
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var autoRetryTimer: Timer?
    
    private var isRightOptionPressed = false
    private var isRightCmdOptionPressed = false
    private var isRightCmdOptionChordActive = false
    private var pendingPushToTalkStart: DispatchWorkItem?
    private var didStartPushToTalk = false
    private var lastContinuousToggleTime = Date.distantPast
    
    private var pushToTalkKeyDown: (() -> Void)?
    private var pushToTalkKeyUp: (() -> Void)?
    private var continuousToggle: (() -> Void)?
    
    private var currentMode: HotkeyMode = .pushToTalk
    private var useDefaults = true
    
    private init() {}
    
    func startMonitoring(
        mode: HotkeyMode,
        useDefaults: Bool,
        pushToTalkKeyDown: @escaping () -> Void,
        pushToTalkKeyUp: @escaping () -> Void,
        continuousToggle: @escaping () -> Void
    ) {
        logger.info("Starting background hotkey reservation (mode: \(mode.rawValue), useDefaults: \(useDefaults))")
        self.currentMode = mode
        self.useDefaults = useDefaults
        self.pushToTalkKeyDown = pushToTalkKeyDown
        self.pushToTalkKeyUp = pushToTalkKeyUp
        self.continuousToggle = continuousToggle
        
        // 1. Setup KeyboardShortcuts for custom hotkeys
        setupKeyboardShortcuts()
        
        // 2. Setup NSEvent global and local monitors (active across all apps in background)
        setupNSEventMonitors()
        
        // 3. Setup CGEventTap if accessibility is already granted
        if checkAccessibilityPermissionStatic() {
            setupEventTap()
        } else {
            logger.warning("Accessibility not granted yet; auto-retry guardian will initialize once enabled")
        }
        
        // 4. Start continuous auto-retry guardian to keep hotkeys permanently reserved
        startAutoRetryTimer()
    }
    
    func retryMonitoringIfReady() {
        setupNSEventMonitors()
        setupKeyboardShortcuts()
        
        if eventTap == nil && checkAccessibilityPermissionStatic() {
            logger.info("Accessibility active: initializing CGEventTap")
            setupEventTap()
        }
    }
    
    func updateMode(_ mode: HotkeyMode, useDefaults: Bool) {
        self.currentMode = mode
        self.useDefaults = useDefaults
        setupKeyboardShortcuts()
    }
    
    func stopMonitoring() {
        pendingPushToTalkStart?.cancel()
        pendingPushToTalkStart = nil
        autoRetryTimer?.invalidate()
        autoRetryTimer = nil
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            self.globalMonitor = nil
        }
        
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            self.localMonitor = nil
        }
        
        KeyboardShortcuts.disable(.startDictation)
        KeyboardShortcuts.disable(.toggleDictation)
    }
    
    func requestAccessibilityPermission() {
        requestAccessibilityPermissionStatic()
    }
    
    // MARK: - Auto-Retry Guardian
    private func startAutoRetryTimer() {
        autoRetryTimer?.invalidate()
        autoRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.eventTap == nil || self.globalMonitor == nil {
                    self.retryMonitoringIfReady()
                }
            }
        }
    }
    
    // MARK: - NSEvent Background Monitoring
    private func setupNSEventMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.handleNSEvent(event)
            }
            logger.info("NSEvent global background monitor registered")
        }
        
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.handleNSEvent(event)
                return event
            }
            logger.info("NSEvent local monitor registered")
        }
    }
    
    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags
        
        let isRightOption = keyCode == 61
        let isRightCommand = keyCode == 54
        let isOptionPressed = flags.contains(.option)
        let isCommandPressed = flags.contains(.command)
        
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(isRightOption: isRightOption, isOptionPressed: isOptionPressed, isRightCommand: isRightCommand, isCommandPressed: isCommandPressed)
            
        case .keyUp:
            finishPushToTalkIfNeeded(isRightOption: isRightOption)
            
        default:
            break
        }
    }
    
    // MARK: - CGEventTap Hardware Filter
    private func setupEventTap() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon!).takeUnretainedValue()
            return service.handleCGEvent(proxy: proxy, type: type, event: event)
        }
        
        let selfRef = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // listenOnly prevents timeouts and event blocking
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfRef
        )
        
        guard let eventTap = eventTap else {
            logger.error("Failed to create CGEventTap")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        logger.info("CGEventTap active and reserved in background")
    }
    
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = self.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                logger.info("Re-enabled CGEventTap after system timeout")
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        let isRightOption = keyCode == 61
        let isRightCommand = keyCode == 54
        let isOptionPressed = flags.contains(.maskAlternate)
        let isCommandPressed = flags.contains(.maskCommand)
        
        switch type {
        case .flagsChanged:
            handleFlagsChanged(isRightOption: isRightOption, isOptionPressed: isOptionPressed, isRightCommand: isRightCommand, isCommandPressed: isCommandPressed)
            
        case .keyUp:
            finishPushToTalkIfNeeded(isRightOption: isRightOption)
            
        default:
            break
        }
        
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - State Management & Debouncing
    private func handleFlagsChanged(isRightOption: Bool, isOptionPressed: Bool, isRightCommand: Bool, isCommandPressed: Bool) {
        guard useDefaults else { return }
        
        let now = Date()
        
        // 1. Check for Continuous Mode Chord: Cmd + Right Option (or Right Cmd + Option)
        let isChord = isOptionPressed && isCommandPressed && (isRightOption || isRightCommand || isRightCmdOptionChordActive)
        
        if isChord {
            cancelPendingPushToTalkStart()
            isRightCmdOptionChordActive = true
            isRightOptionPressed = false
            
            if now.timeIntervalSince(lastContinuousToggleTime) > 0.4 {
                lastContinuousToggleTime = now
                logger.info("Right Cmd+Option detected -> continuousToggle")
                continuousToggle?()
            }
            return
        }
        
        // If chord was active and keys are now released
        if isRightCmdOptionChordActive {
            if !isOptionPressed && !isCommandPressed {
                isRightCmdOptionChordActive = false
                isRightOptionPressed = false
            }
            return
        }
        
        // 2. If user setting is Continuous Mode: Right Option alone toggles
        if currentMode == .continuous {
            if isRightOption && isOptionPressed && !isCommandPressed {
                if !isRightOptionPressed && now.timeIntervalSince(lastContinuousToggleTime) > 0.4 {
                    lastContinuousToggleTime = now
                    isRightOptionPressed = true
                    logger.info("Right Option toggled in continuous mode")
                    continuousToggle?()
                }
            } else if !isOptionPressed {
                isRightOptionPressed = false
            }
            return
        }
        
        // 3. Default Push-to-Talk Mode: Right Option alone (hold to talk, release to type)
        if currentMode == .pushToTalk {
            let wasPressed = isRightOptionPressed
            
            if isRightOption {
                isRightOptionPressed = isOptionPressed && !isCommandPressed
            } else if isRightOptionPressed && !isOptionPressed {
                isRightOptionPressed = false
            }
            
            if wasPressed && !isRightOptionPressed {
                let didStart = didStartPushToTalk
                cancelPendingPushToTalkStart()
                logger.info("Right Option released -> pushToTalkKeyUp")
                if didStart {
                    didStartPushToTalk = false
                    pushToTalkKeyUp?()
                }
            } else if !wasPressed && isRightOptionPressed {
                schedulePushToTalkStart()
            }
        }
    }

    private func schedulePushToTalkStart() {
        pendingPushToTalkStart?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRightOptionPressed, !self.isRightCmdOptionChordActive else { return }
            self.didStartPushToTalk = true
            self.logger.info("Right Option held -> pushToTalkKeyDown")
            self.pushToTalkKeyDown?()
        }

        pendingPushToTalkStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func cancelPendingPushToTalkStart() {
        pendingPushToTalkStart?.cancel()
        pendingPushToTalkStart = nil
    }

    private func finishPushToTalkIfNeeded(isRightOption: Bool) {
        guard useDefaults, currentMode == .pushToTalk, isRightOption,
              isRightOptionPressed, !isRightCmdOptionChordActive else { return }

        isRightOptionPressed = false
        let didStart = didStartPushToTalk
        cancelPendingPushToTalkStart()

        if didStart {
            didStartPushToTalk = false
            logger.info("Right Option released -> pushToTalkKeyUp")
            pushToTalkKeyUp?()
        }
    }
    
    // MARK: - KeyboardShortcuts (Custom User-Declared Hotkeys)
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.disable(.startDictation)
        KeyboardShortcuts.disable(.toggleDictation)
        
        if !useDefaults {
            logger.info("Reserving user-declared custom hotkeys in background")
            
            // 1. Custom Push-to-Talk (Hold key combination to talk, release to auto-type)
            KeyboardShortcuts.onKeyDown(for: .startDictation) { [weak self] in
                self?.logger.info("Custom Push-to-Talk DOWN -> start recording")
                self?.pushToTalkKeyDown?()
            }
            KeyboardShortcuts.onKeyUp(for: .startDictation) { [weak self] in
                self?.logger.info("Custom Push-to-Talk UP -> stop recording and auto-type")
                self?.pushToTalkKeyUp?()
            }
            
            // 2. Custom Continuous Hands-Free Toggle (Press once to start, press again to stop)
            KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
                self?.logger.info("Custom Continuous Toggle -> toggle recording")
                self?.continuousToggle?()
            }
        }
    }
}
