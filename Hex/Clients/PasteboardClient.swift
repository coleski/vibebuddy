//
//  PasteboardClient.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Sauce
import SwiftUI

@DependencyClient
struct PasteboardClient {
    var paste: @Sendable (String) async -> Void
    var copy: @Sendable (String) async -> Void
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

actor PasteboardClientLive {
    @Shared(.hexSettings) var hexSettings: HexSettings
    
    // Queue to ensure paste operations happen sequentially
    private var pasteQueue: [String] = []
    private var isProcessingQueue = false

    func paste(text: String) async {
        // Add to queue and process
        pasteQueue.append(text)
        await processQueue()
    }
    
    private func processQueue() async {
        // Prevent concurrent processing
        guard !isProcessingQueue else { return }
        guard !pasteQueue.isEmpty else { return }
        
        isProcessingQueue = true
        
        while !pasteQueue.isEmpty {
            let text = pasteQueue.removeFirst()
            await performPaste(text: text)
            
            // Small delay between pastes to avoid conflicts
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        isProcessingQueue = false
    }
    
    private func performPaste(text: String) async {
        // Get the setting values in actor context
        let useClipboard = hexSettings.useClipboardPaste
        let copyToClipboard = hexSettings.copyToClipboard
        
        print("[PasteboardClient] performPaste called with useClipboard: \(useClipboard), copyToClipboard: \(copyToClipboard)")
        
        // Perform the paste operation on main actor
        if useClipboard {
            print("[PasteboardClient] Using clipboard paste")
            await pasteWithClipboard(text, copyToClipboard: copyToClipboard)
        } else {
            print("[PasteboardClient] Using simulated typing")
            await MainActor.run {
                simulateTypingWithAppleScript(text)
            }
        }
    }
    
    @MainActor
    func copy(text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
        print("[PasteboardClient] pasteToFrontmostApp() called")
        let script = """
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
            print("[PasteboardClient] About to execute AppleScript")
            let result = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("[PasteboardClient] AppleScript error: \(error)")
                return false
            }
            let success = result.booleanValue
            print("[PasteboardClient] AppleScript result: \(success)")
            return success
        }
        print("[PasteboardClient] Failed to create AppleScript object")
        return false
    }

    @MainActor
    func pasteWithClipboard(_ text: String, copyToClipboard: Bool) async {
        print("[PasteboardClient] pasteWithClipboard started for text: '\(text)'")
        let pasteboard = NSPasteboard.general
        let originalItems = await savePasteboardState(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[PasteboardClient] Set text to pasteboard")

        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Track if paste operation successful
        print("[PasteboardClient] Attempting to paste to frontmost app")
        var pasteSucceeded = PasteboardClientLive.pasteToFrontmostApp()
        print("[PasteboardClient] Paste to frontmost app result: \(pasteSucceeded)")
        
        // If menu-based paste failed, try simulated keypresses
        if !pasteSucceeded {
            print("[PasteboardClient] AppleScript paste failed, falling back to simulated Cmd+V keypresses")
            let vKeyCode = Sauce.shared.keyCode(for: .v)
            let cmdKeyCode: CGKeyCode = 55 // Command key
            
            print("[PasteboardClient] vKeyCode: \(vKeyCode), cmdKeyCode: \(cmdKeyCode)")

            // Create cmd down event
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true)
            print("[PasteboardClient] Created cmdDown event: \(cmdDown != nil)")

            // Create v down event
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            vDown?.flags = .maskCommand
            print("[PasteboardClient] Created vDown event: \(vDown != nil)")

            // Create v up event
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            vUp?.flags = .maskCommand
            print("[PasteboardClient] Created vUp event: \(vUp != nil)")

            // Create cmd up event
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)
            print("[PasteboardClient] Created cmdUp event: \(cmdUp != nil)")

            // Post the events
            print("[PasteboardClient] Posting keyboard events...")
            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
            print("[PasteboardClient] Keyboard events posted")
            
            // Assume keypress-based paste succeeded - but text will remain in clipboard as fallback
            pasteSucceeded = true
            print("[PasteboardClient] Marked simulated keypress as succeeded")
        }
        
        // Only restore original pasteboard contents if:
        // 1. Copying to clipboard is disabled AND
        // 2. The paste operation succeeded
        if !copyToClipboard && pasteSucceeded {
            try? await Task.sleep(for: .seconds(0.1))
            pasteboard.clearContents()
            await restorePasteboardState(pasteboard: pasteboard, savedItems: originalItems)
        }
        
        // If we failed to paste AND user doesn't want clipboard retention,
        // show a notification that text is available in clipboard
        if !pasteSucceeded && !copyToClipboard {
            // Keep the transcribed text in clipboard regardless of setting
            print("Paste operation failed. Text remains in clipboard as fallback.")
            
            // TODO: Could add a notification here to inform user
            // that text is available in clipboard
        }
    }
    
    @MainActor  
    func simulateTypingWithAppleScript(_ text: String) {
        let typingStart = Date()
        print("[TIMING] AppleScript typing started at \(typingStart) for text: '\(text)'")
        
        let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = "tell application \"System Events\" to keystroke \"\(escapedText)\""
        let script = NSAppleScript(source: scriptSource)
        var error: NSDictionary?
        
        script?.executeAndReturnError(&error)
        
        let typingEnd = Date()
        let typingTime = typingEnd.timeIntervalSince(typingStart)
        
        if let error = error {
            print("[TIMING] AppleScript typing failed in \(String(format: "%.2f", typingTime))s: \(error)")
        } else {
            print("[TIMING] AppleScript typing completed in \(String(format: "%.2f", typingTime))s")
        }
    }

    enum PasteError: Error {
        case systemWideElementCreationFailed
        case focusedElementNotFound
        case elementDoesNotSupportTextEditing
        case failedToInsertText
    }
    
    static func insertTextAtCursor(_ text: String) throws {
        // Get the system-wide accessibility element
        let systemWideElement = AXUIElementCreateSystemWide()
        
        // Get the focused element
        var focusedElementRef: CFTypeRef?
        let axError = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        
        guard axError == .success, let focusedElementRef = focusedElementRef else {
            throw PasteError.focusedElementNotFound
        }
        
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
        let insertResult = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        
        if insertResult != .success {
            throw PasteError.failedToInsertText
        }
    }
}
