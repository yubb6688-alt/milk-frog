import AppKit
import ApplicationServices
import QuartzCore

final class InputActivityMonitor {
    private var activity = TypingActivity()
    private var timer: Timer?
    private var globalKeys: Any?
    private var globalClicks: Any?
    private var localEvents: Any?
    private let systemElement = AXUIElementCreateSystemWide()
    private var lastEditableTime: TimeInterval = -.infinity
    private var wasTrusted = false
    private let testMode: Bool
    var localTestFieldFocused = false
    var onTrustChanged: ((Bool) -> Void)?

    init(testMode: Bool = false) {
        self.testMode = testMode
        AXUIElementSetMessagingTimeout(systemElement, 0.05)
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func snapshot(at time: TimeInterval = CACurrentMediaTime()) -> TypingSnapshot {
        activity.snapshot(at: time)
    }

    func start() {
        stop()
        // Only metadata about the focused control is queried. Never read AXValue,
        // selected text, event.characters, the clipboard, or the typed contents.
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { self?.refreshFocus() }
        }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
            if event.type == .keyDown { self?.handleKey(event) }
            else { DispatchQueue.main.async { self?.refreshFocus() } }
            return event
        }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.refreshPermission()
            self?.refreshFocus()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshPermission()
        refreshFocus()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in [globalKeys, globalClicks, localEvents].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalKeys = nil
        globalClicks = nil
        localEvents = nil
        activity.setFocused(false)
    }

    private func refreshPermission() {
        let trusted = isTrusted
        if trusted, globalKeys == nil {
            globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event)
            }
        } else if !trusted, let monitor = globalKeys {
            NSEvent.removeMonitor(monitor)
            globalKeys = nil
        }
        if trusted != wasTrusted {
            wasTrusted = trusted
            onTrustChanged?(trusted)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func focusedEditable() -> Bool {
        if testMode { return localTestFieldFocused }
        guard isTrusted else { return false }
        var focused = attribute(systemElement, kAXFocusedUIElementAttribute)
        if focused == nil,
           let app = attribute(systemElement, kAXFocusedApplicationAttribute),
           CFGetTypeID(app) == AXUIElementGetTypeID() {
            focused = attribute(unsafeBitCast(app, to: AXUIElement.self), kAXFocusedUIElementAttribute)
        }
        guard let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        if role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole { return false }
        if let enabled = attribute(element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        if ["AXTextField", "AXTextArea", "AXSearchField"].contains(role) { return true }
        if attribute(element, "AXEditable") as? Bool == true { return true }
        if role == "AXComboBox" {
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
                && settable.boolValue
        }
        return false
    }

    private func refreshFocus() {
        let now = CACurrentMediaTime()
        let editable = focusedEditable()
        if editable { lastEditableTime = now }
        // Brief tolerance for IME candidate-window focus changes.
        let focused = editable || ((isTrusted || testMode) && now - lastEditableTime < 0.25)
        let changed = focused != activity.focused
        activity.setFocused(focused)
        if changed, CommandLine.arguments.contains("--debug-typing") {
            NSLog("Input: focused=%@ trusted=%@", focused ? "yes" : "no", isTrusted ? "yes" : "no")
        }
    }

    private func handleKey(_ event: NSEvent) {
        refreshFocus()
        guard activity.focused, focusedEditable(), !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              ![48, 53, 115, 116, 119, 121, 123, 124, 125, 126].contains(Int(event.keyCode)) else { return }
        activity.recordStroke(at: CACurrentMediaTime())
        if CommandLine.arguments.contains("--debug-typing") {
            NSLog("Input: typing-pulse hand=%ld", activity.snapshot(at: CACurrentMediaTime()).frameIndex)
        }
    }
}
