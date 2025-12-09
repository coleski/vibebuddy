//
//  PasteboardClient.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import HexCore
import Sauce
import SwiftUI

private let pasteboardLogger = HexLog.pasteboard

@DependencyClient
struct PasteboardClient {
    var paste: @Sendable (String) async -> Void
    var copy: @Sendable (String) async -> Void
    var sendKeyboardCommand: @Sendable (KeyboardCommand) async -> Void
}

extension PasteboardClient: DependencyKey {
    static var liveValue: Self {
        let live = PasteboardClientLive()
        return .init(
            paste: { text in
                await live.paste(text: text)
            },
            copy: { text in
                await live.copy(text: text)
            },
            sendKeyboardCommand: { command in
                await live.sendKeyboardCommand(command)
            }
        )
    }
}

extension DependencyValues {
    var pasteboard: PasteboardClient {
        get { self[PasteboardClient.self] }
        set { self[PasteboardClient.self] = newValue }
    }
}

private func formatDuration(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let totalSeconds = Double(seconds) + Double(attoseconds) / 1e18
    return String(format: "%.3f", totalSeconds)
}

actor PasteboardClientLive {
    @Shared(.hexSettings) var hexSettings: HexSettings
    
    // Queue to ensure paste operations happen sequentially
    private var pasteQueue: [String] = []
    private var isProcessingQueue = false

    func paste(text: String) async {
        print("[PASTE_ACTOR] paste() called with text length: \(text.count)")
        print("[PASTE_ACTOR] Text preview: '\(String(text.prefix(50)))\(text.count > 50 ? "..." : "")'")
        print("[PASTE_ACTOR] Current queue size: \(pasteQueue.count)")
        print("[PASTE_ACTOR] Currently processing: \(isProcessingQueue)")
        print("[PASTE_ACTOR] Text memory address: \(Unmanaged.passUnretained(text as AnyObject).toOpaque())")
        print("[PASTE_ACTOR] Current thread: \(Thread.current)")
        
        // Validate text integrity before queueing
        let textIntegrityCheck = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasInvalidChars = text.contains { char in
            let unicode = char.unicodeScalars.first?.value ?? 0
            return unicode > 0x10FFFF || (unicode >= 0xD800 && unicode <= 0xDFFF) // Invalid Unicode
        }
        
        print("[PASTE_ACTOR] Text validation - isValid: \(textIntegrityCheck), hasInvalidChars: \(hasInvalidChars)")
        
        if hasInvalidChars {
            print("[PASTE_ACTOR] WARNING: Text contains invalid Unicode characters!")
            print("[PASTE_ACTOR] Invalid chars detected in: '\(text.unicodeScalars.map { $0.value }.prefix(20))'")
        }
        
        // Create a defensive copy to isolate from caller
        let textCopy = String(text)
        
        // Add the copy to queue and process
        pasteQueue.append(textCopy)
        print("[PASTE_ACTOR] Added copy to queue. New queue size: \(pasteQueue.count)")
        await processQueue()
    }
    
    private func processQueue() async {
        print("[PASTE_ACTOR] processQueue() called")
        print("[PASTE_ACTOR] Current state - isProcessingQueue: \(isProcessingQueue), queueSize: \(pasteQueue.count)")
        
        // Prevent concurrent processing
        guard !isProcessingQueue else { 
            print("[PASTE_ACTOR] Already processing queue, returning early")
            return 
        }
        guard !pasteQueue.isEmpty else { 
            print("[PASTE_ACTOR] Queue is empty, returning early")
            return 
        }
        
        print("[PASTE_ACTOR] Starting queue processing")
        isProcessingQueue = true
        
        var itemIndex = 0
        while !pasteQueue.isEmpty {
            let text = pasteQueue.removeFirst()
            print("[PASTE_ACTOR] Processing queue item \(itemIndex): length \(text.count)")
            print("[PASTE_ACTOR] Item \(itemIndex) preview: '\(String(text.prefix(30)))\(text.count > 30 ? "..." : "")'")
            print("[PASTE_ACTOR] Item \(itemIndex) memory address: \(Unmanaged.passUnretained(text as AnyObject).toOpaque())")
            
            // Check text integrity before processing
            let preProcessIntegrity = String(text)
            let integrityMatches = (text == preProcessIntegrity)
            print("[PASTE_ACTOR] Item \(itemIndex) pre-process integrity check: \(integrityMatches)")
            
            if !integrityMatches {
                print("[PASTE_ACTOR] CORRUPTION DETECTED before processing item \(itemIndex)!")
                print("[PASTE_ACTOR] Original: '\(String(text.prefix(30)))', Copy: '\(String(preProcessIntegrity.prefix(30)))'")
            }
            
            await performPaste(text: text)
            
            // Post-process integrity check
            let postProcessIntegrity = (text == preProcessIntegrity)
            print("[PASTE_ACTOR] Item \(itemIndex) post-process integrity check: \(postProcessIntegrity)")
            
            itemIndex += 1
            print("[PASTE_ACTOR] Completed item \(itemIndex - 1). Remaining queue size: \(pasteQueue.count)")
            
            // Add delay between pastes (but not after the last one)
            if !pasteQueue.isEmpty {
                print("[PASTE_ACTOR] Adding delay before next paste")
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        
        print("[PASTE_ACTOR] Queue processing completed")
        isProcessingQueue = false
    }
    
    private func performPaste(text: String) async {
        print("[PASTE_ACTOR] performPaste() started")
        print("[PASTE_ACTOR] Text length: \(text.count), preview: '\(String(text.prefix(50)))\(text.count > 50 ? "..." : "")'")
        print("[PASTE_ACTOR] Text memory address: \(Unmanaged.passUnretained(text as AnyObject).toOpaque())")
        print("[PASTE_ACTOR] Current thread: \(Thread.current)")
        
        // Get the setting values in actor context
        let useClipboard = hexSettings.useClipboardPaste
        let copyToClipboard = hexSettings.copyToClipboard
        let useAccessibilityAPI = hexSettings.useAccessibilityAPI
        
        print("[PASTE_ACTOR] Settings - useClipboard: \(useClipboard), useAccessibilityAPI: \(useAccessibilityAPI), copyToClipboard: \(copyToClipboard)")
        
        // Create a defensive copy before any operations
        let textCopy = String(text)
        let preOpIntegrity = (text == textCopy)
        print("[PASTE_ACTOR] Pre-operation integrity check: \(preOpIntegrity)")
        if !preOpIntegrity {
            print("[PASTE_ACTOR] TEXT CORRUPTION detected before operation!")
            print("[PASTE_ACTOR] Original: '\(String(text.prefix(30)))', Copy: '\(String(textCopy.prefix(30)))'")
        }
        
        // Perform the paste operation on main actor
        print("[PASTE_METHOD] ===== PASTE METHOD SELECTION =====")
        print("[PASTE_METHOD] useClipboard: \(useClipboard)")
        print("[PASTE_METHOD] useAccessibilityAPI: \(useAccessibilityAPI)")
        print("[PASTE_METHOD] copyToClipboard: \(copyToClipboard)")
        
        if useClipboard {
            print("[PASTE_METHOD] ✅ SELECTED METHOD: CLIPBOARD PASTE (Cmd+V)")
            print("[PASTE_ACTOR] Using clipboard paste")
            await pasteWithClipboard(text, copyToClipboard: copyToClipboard)
        } else if useAccessibilityAPI {
            print("[PASTE_METHOD] ✅ SELECTED METHOD: ACCESSIBILITY API (Direct insertion)")
            print("[PASTE_ACTOR] Using Accessibility API")
            await MainActor.run {
                insertTextWithAccessibilityAPI(text)
            }
        } else {
            print("[PASTE_METHOD] ✅ SELECTED METHOD: APPLESCRIPT TYPING (Simulated keystrokes)")
            print("[PASTE_ACTOR] Using simulated typing")
            await MainActor.run {
                simulateTypingWithAppleScript(text)
            }
        }
        print("[PASTE_METHOD] =====================================")
        
        // Final integrity check
        let postOpIntegrity = (text == textCopy)
        print("[PASTE_ACTOR] Post-operation integrity check: \(postOpIntegrity)")
        if !postOpIntegrity {
            print("[PASTE_ACTOR] TEXT CORRUPTION detected after operation!")
            print("[PASTE_ACTOR] Original now: '\(String(text.prefix(30)))', Expected: '\(String(textCopy.prefix(30)))'")
        }
        
        print("[PASTE_ACTOR] performPaste() completed")
    }
    
    @MainActor
    func copy(text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    @MainActor
    func sendKeyboardCommand(_ command: KeyboardCommand) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Convert modifiers to CGEventFlags and key codes for modifier keys
        var modifierKeyCodes: [CGKeyCode] = []
        var flags = CGEventFlags()
        
        for modifier in command.modifiers.sorted {
            switch modifier.kind {
            case .command:
                flags.insert(.maskCommand)
                modifierKeyCodes.append(55) // Left Cmd
            case .shift:
                flags.insert(.maskShift)
                modifierKeyCodes.append(56) // Left Shift
            case .option:
                flags.insert(.maskAlternate)
                modifierKeyCodes.append(58) // Left Option
            case .control:
                flags.insert(.maskControl)
                modifierKeyCodes.append(59) // Left Control
            case .fn:
                flags.insert(.maskSecondaryFn)
                // Fn key doesn't need explicit key down/up
            case .capsLock:
                flags.insert(.maskAlphaShift)
                modifierKeyCodes.append(57) // Caps Lock
            }
        }
        
        // Press modifiers down
        for keyCode in modifierKeyCodes {
            let modDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            modDown?.post(tap: .cghidEventTap)
        }
        
        // Press main key if present
        if let key = command.key {
            let keyCode = Sauce.shared.keyCode(for: key)
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            keyDown?.flags = flags
            keyDown?.post(tap: .cghidEventTap)
            
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.flags = flags
            keyUp?.post(tap: .cghidEventTap)
        }
        
        // Release modifiers in reverse order
        for keyCode in modifierKeyCodes.reversed() {
            let modUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            modUp?.post(tap: .cghidEventTap)
        }
        
        pasteboardLogger.debug("Sent keyboard command: \(command.displayName)")
    }

    // Function to save the current state of the NSPasteboard
    @MainActor
    func savePasteboardState(pasteboard: NSPasteboard) -> [[String: Any]] {
        var savedItems: [[String: Any]] = []
        
        for item in pasteboard.pasteboardItems ?? [] {
            var itemDict: [String: Any] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemDict[type.rawValue] = data
                }
            }
            savedItems.append(itemDict)
        }
        
        return savedItems
    }

    // Function to restore the saved state of the NSPasteboard
    @MainActor
    func restorePasteboardState(pasteboard: NSPasteboard, savedItems: [[String: Any]]) {
        pasteboard.clearContents()
        
        for itemDict in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in itemDict {
                if let data = data as? Data {
                    item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
                }
            }
            pasteboard.writeObjects([item])
        }
    }

    /// Pastes current clipboard content to the frontmost application
    static func pasteToFrontmostApp() -> Bool {
        print("[PASTE_APPLESCRIPT] pasteToFrontmostApp() called")
        print("[PASTE_APPLESCRIPT] Current thread: \(Thread.current)")
        let script = """
        if application "System Events" is not running then
            tell application "System Events" to launch
            delay 0.1
        end if
        tell application "System Events"
            tell process (name of first application process whose frontmost is true)
                tell (menu item "Paste" of menu of menu item "Paste" of menu "Edit" of menu bar item "Edit" of menu bar 1)
                    if exists then
                        log (get properties of it)
                        if enabled then
                            click it
                            return true
                        else
                            return false
                        end if
                    end if
                end tell
                tell (menu item "Paste" of menu "Edit" of menu bar item "Edit" of menu bar 1)
                    if exists then
                        if enabled then
                            click it
                            return true
                        else
                            return false
                        end if
                    else
                        return false
                    end if
                end tell
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            print("[PASTE_APPLESCRIPT] About to execute AppleScript for frontmost app paste")
            let result = scriptObject.executeAndReturnError(&error)
            if let error = error {
pasteboardLogger.error("AppleScript paste failed: \(error)")
                print("[PASTE_APPLESCRIPT] AppleScript error: \(error)")
                print("[PASTE_APPLESCRIPT] Error description: \(error.description)")
                return false
            }
            let success = result.booleanValue
            print("[PASTE_APPLESCRIPT] AppleScript result: \(success)")
            print("[PASTE_APPLESCRIPT] Result object: \(result.description)")
            return success
        }
        print("[PASTE_APPLESCRIPT] Failed to create AppleScript object")
        return false
    }

    @MainActor
    func pasteWithClipboard(_ text: String, copyToClipboard: Bool) async {
        let methodStart = ContinuousClock.now
        print("")
        print("[CLIPBOARD] 🔵 CLIPBOARD PASTE METHOD STARTED")
        print("[CLIPBOARD] =================================")
        print("[CLIPBOARD] pasteWithClipboard started for text length: \(text.count)")
        print("[CLIPBOARD] Text preview: '\(String(text.prefix(50)))\(text.count > 50 ? "..." : "")'")
        print("[CLIPBOARD] copyToClipboard setting: \(copyToClipboard)")

        let pasteboard = NSPasteboard.general

        let saveStart = ContinuousClock.now
        let originalItems = savePasteboardState(pasteboard: pasteboard)
        print("[CLIPBOARD] savePasteboardState took \(formatDuration(ContinuousClock.now - saveStart))s (items: \(originalItems.count))")

        let writeStart = ContinuousClock.now
        let targetChangeCount = writeAndTrackChangeCount(pasteboard: pasteboard, text: text)
        print("[CLIPBOARD] writeAndTrackChangeCount took \(formatDuration(ContinuousClock.now - writeStart))s")

        let commitStart = ContinuousClock.now
        let commitSucceeded = await waitForPasteboardCommit(targetChangeCount: targetChangeCount)
        print("[CLIPBOARD] waitForPasteboardCommit took \(formatDuration(ContinuousClock.now - commitStart))s (succeeded: \(commitSucceeded))")

        let pasteStart = ContinuousClock.now
        let pasteSucceeded = await tryPaste(text)
        print("[CLIPBOARD] tryPaste took \(formatDuration(ContinuousClock.now - pasteStart))s (succeeded: \(pasteSucceeded))")
        print("[CLIPBOARD] Total paste operation took \(formatDuration(ContinuousClock.now - methodStart))s")
        
        // Only restore original pasteboard contents if:
        // 1. Copying to clipboard is disabled AND
        // 2. The paste operation succeeded
if !copyToClipboard && pasteSucceeded {
            let savedItems = originalItems
            Task { @MainActor in
                // Give slower apps (e.g., Claude, Warp) a short window to read the plain-text entry
                // before we repopulate the clipboard with the user's previous rich data.
                try? await Task.sleep(for: .milliseconds(500))
                pasteboard.clearContents()
                restorePasteboardState(pasteboard: pasteboard, savedItems: savedItems)
            }
        }
        
        // If we failed to paste AND user doesn't want clipboard retention,
        // show a notification that text is available in clipboard
        if !pasteSucceeded && !copyToClipboard {
            // Keep the transcribed text in clipboard regardless of setting
            pasteboardLogger.notice("Paste operation failed; text remains in clipboard as fallback.")
            
            // TODO: Could add a notification here to inform user
            // that text is available in clipboard
        }
    }

    @MainActor
    private func writeAndTrackChangeCount(pasteboard: NSPasteboard, text: String) -> Int {
        let before = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let after = pasteboard.changeCount
        if after == before {
            // Ensure we always advance by at least one to avoid infinite waits if the system
            // coalesces writes (seen on Sonoma betas with zero-length strings).
            return after + 1
        }
        return after
    }

    @MainActor
    private func waitForPasteboardCommit(
        targetChangeCount: Int,
        timeout: Duration = .milliseconds(150),
        pollInterval: Duration = .milliseconds(5)
    ) async -> Bool {
        guard targetChangeCount > NSPasteboard.general.changeCount else { return true }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if NSPasteboard.general.changeCount >= targetChangeCount {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }

    // MARK: - Paste Orchestration

    @MainActor
    private func tryPaste(_ text: String) async -> Bool {
        // 1) Fast path: send Cmd+V (no delay)
        let cmdVStart = ContinuousClock.now
        if await postCmdV(delayMs: 0) {
            print("[CLIPBOARD] postCmdV succeeded in \(formatDuration(ContinuousClock.now - cmdVStart))s")
            return true
        }
        print("[CLIPBOARD] postCmdV failed in \(formatDuration(ContinuousClock.now - cmdVStart))s, trying menu fallback")

        // 2) Menu fallback (quiet failure)
        let menuStart = ContinuousClock.now
        if PasteboardClientLive.pasteToFrontmostApp() {
            print("[CLIPBOARD] pasteToFrontmostApp succeeded in \(formatDuration(ContinuousClock.now - menuStart))s")
            return true
        }
        print("[CLIPBOARD] pasteToFrontmostApp failed in \(formatDuration(ContinuousClock.now - menuStart))s, trying AX fallback")

        // 3) AX insert fallback
        let axStart = ContinuousClock.now
        if (try? Self.insertTextAtCursor(text)) != nil {
            print("[CLIPBOARD] insertTextAtCursor succeeded in \(formatDuration(ContinuousClock.now - axStart))s")
            return true
        }
        print("[CLIPBOARD] insertTextAtCursor failed in \(formatDuration(ContinuousClock.now - axStart))s")
        return false
    }

    // MARK: - Helpers

    @MainActor
    private func postCmdV(delayMs: Int) async -> Bool {
        // Optional tiny wait before keystrokes
        try? await wait(milliseconds: delayMs)
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = vKeyCode()
        let cmdKey: CGKeyCode = 55
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        return true
    }

    @MainActor
    private func vKeyCode() -> CGKeyCode {
        if Thread.isMainThread { return Sauce.shared.keyCode(for: .v) }
        return DispatchQueue.main.sync { Sauce.shared.keyCode(for: .v) }
    }

    @MainActor
    private func wait(milliseconds: Int) async throws {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
    
    @MainActor  
    func simulateTypingWithAppleScript(_ text: String) {
        let typingStart = Date()
        print("")
        print("[APPLESCRIPT] 🟢 APPLESCRIPT TYPING METHOD STARTED")
        print("[APPLESCRIPT] ===================================")
        print("[APPLESCRIPT] Typing started at \(typingStart) for text length: \(text.count)")
        print("[APPLESCRIPT] This method will: Use AppleScript to simulate individual keystrokes")
        print("[APPLESCRIPT] Text preview: '\(String(text.prefix(50)))\(text.count > 50 ? "..." : "")'")
        print("[APPLESCRIPT] Text memory address: \(Unmanaged.passUnretained(text as AnyObject).toOpaque())")
        
        // Integrity check before AppleScript processing
        let textCopy = String(text)
        let preScriptIntegrity = (text == textCopy)
        print("[APPLESCRIPT] Pre-script integrity check: \(preScriptIntegrity)")
        
        if !preScriptIntegrity {
            print("[APPLESCRIPT] TEXT CORRUPTION detected before AppleScript!")
            print("[APPLESCRIPT] Original: '\(String(text.prefix(30)))', Copy: '\(String(textCopy.prefix(30)))'")
        }
        
        // Properly escape text for AppleScript:
        // 1. First escape backslashes (must be done first!)
        // 2. Then escape quotes
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        print("[APPLESCRIPT] Escaped text length: \(escapedText.count)")
        print("[APPLESCRIPT] Escaped preview: '\(String(escapedText.prefix(30)))\(escapedText.count > 30 ? "..." : "")'")
        
        let scriptSource = "tell application \"System Events\" to keystroke \"\(escapedText)\""
        print("[APPLESCRIPT] Script source length: \(scriptSource.count)")
        
        let script = NSAppleScript(source: scriptSource)
        var error: NSDictionary?
        
        print("[APPLESCRIPT] About to execute script")
        let result = script?.executeAndReturnError(&error)
        print("[APPLESCRIPT] Script execution completed")
        
        // Post-execution integrity check
        let postScriptIntegrity = (text == textCopy)
        print("[APPLESCRIPT] Post-script integrity check: \(postScriptIntegrity)")
        if !postScriptIntegrity {
            print("[APPLESCRIPT] TEXT CORRUPTION detected after AppleScript!")
            print("[APPLESCRIPT] Original now: '\(String(text.prefix(30)))', Expected: '\(String(textCopy.prefix(30)))'")
        }
        
        let typingEnd = Date()
        let typingTime = typingEnd.timeIntervalSince(typingStart)
        
        if let error = error {
            pasteboardLogger.error("Error executing AppleScript typing fallback: \(error)")
            print("[APPLESCRIPT] Typing failed in \(String(format: "%.2f", typingTime))s: \(error)")
            print("[APPLESCRIPT] Error details: \(error.description)")
        } else {
            print("[APPLESCRIPT] Typing completed successfully in \(String(format: "%.2f", typingTime))s")
            print("[APPLESCRIPT] Result: \(result?.description ?? "nil")")
        }
    }

    @MainActor
    func insertTextWithAccessibilityAPI(_ text: String) {
        let insertStart = Date()
        print("")
        print("[ACCESSIBILITY] 🟡 ACCESSIBILITY API METHOD STARTED")
        print("[ACCESSIBILITY] ===================================")
        print("[ACCESSIBILITY] Insertion started at \(insertStart) for text length: \(text.count)")
        print("[ACCESSIBILITY] This method will: Use Accessibility API to directly insert text at cursor")
        print("[ACCESSIBILITY] Text preview: '\(String(text.prefix(50)))\(text.count > 50 ? "..." : "")'")

        do {
            print("[ACCESSIBILITY] About to call insertTextAtCursor")
            try PasteboardClientLive.insertTextAtCursor(text)

            let insertEnd = Date()
            let insertTime = insertEnd.timeIntervalSince(insertStart)
            print("[ACCESSIBILITY] Insertion completed successfully in \(String(format: "%.2f", insertTime))s")
        } catch {
            let insertEnd = Date()
            let insertTime = insertEnd.timeIntervalSince(insertStart)
            print("[ACCESSIBILITY] Insertion failed in \(String(format: "%.2f", insertTime))s: \(error)")
            print("[ACCESSIBILITY] Error type: \(type(of: error))")

            // Fallback to AppleScript if accessibility API fails
            print("[ACCESSIBILITY] Falling back to AppleScript due to failure")
            simulateTypingWithAppleScript(text)
        }
    }

    enum PasteError: Error {
        case systemWideElementCreationFailed
        case focusedElementNotFound
        case elementDoesNotSupportTextEditing
        case failedToInsertText
    }
    
    static func insertTextAtCursor(_ text: String) throws {
        print("[ACCESSIBILITY_STATIC] ---- ACCESSIBILITY API: DIRECT TEXT INSERTION ----")
        print("[ACCESSIBILITY_STATIC] insertTextAtCursor called with text length: \(text.count)")
        print("[ACCESSIBILITY_STATIC] Text preview: '\(String(text.prefix(30)))\(text.count > 30 ? "..." : "")'")
        print("[ACCESSIBILITY_STATIC] Text memory address: \(Unmanaged.passUnretained(text as AnyObject).toOpaque())")
        print("[ACCESSIBILITY_STATIC] This will directly set text in the focused element via AX API")
        
        // Get the system-wide accessibility element
        let systemWideElement = AXUIElementCreateSystemWide()
        print("[ACCESSIBILITY_STATIC] Created system-wide element")
        
        // Get the focused element
        var focusedElementRef: CFTypeRef?
        let axError = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        
        print("[ACCESSIBILITY_STATIC] AX error result: \(axError)")
        
        guard axError == .success, let focusedElementRef = focusedElementRef else {
            print("[ACCESSIBILITY_STATIC] Failed to get focused element - error: \(axError)")
            throw PasteError.focusedElementNotFound
        }
        
        print("[ACCESSIBILITY_STATIC] Successfully got focused element")
        
        let focusedElement = focusedElementRef as! AXUIElement
        
        // Verify if the focused element supports text insertion
        var value: CFTypeRef?
        let supportsText = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &value) == .success
        let supportsSelectedText = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &value) == .success
        
        if !supportsText && !supportsSelectedText {
            throw PasteError.elementDoesNotSupportTextEditing
        }
        
        // // Get any selected text
        // var selectedText: String = ""
        // if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &value) == .success,
        //    let selectedValue = value as? String {
        //     selectedText = selectedValue
        // }
        
        // print("selected text: \(selectedText)")
        
        // Insert text at cursor position by replacing selected text (or empty selection)
        print("[ACCESSIBILITY_STATIC] About to insert text via AXUIElementSetAttributeValue")
        let insertResult = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        
        print("[ACCESSIBILITY_STATIC] Insert result: \(insertResult)")
        
        if insertResult != .success {
            print("[ACCESSIBILITY_STATIC] Failed to insert text - result: \(insertResult)")
            throw PasteError.failedToInsertText
        }
        
        print("[ACCESSIBILITY_STATIC] Successfully inserted text")
    }
}
