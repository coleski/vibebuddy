//
//  CapsLockManager.swift
//  Hex
//
//  Manages Caps Lock ↔ F18 remapping via hidutil for push-to-talk functionality.
//

import Foundation
import HexCore

private let logger = HexLog.keyEvent

/// Manages system-level Caps Lock remapping using macOS hidutil.
///
/// When enabled, Caps Lock is remapped to F18 (an unused function key) so it can be
/// detected as a regular key event in the CGEvent tap. The delay is also removed
/// for responsive activation.
final class CapsLockManager {
    static let shared = CapsLockManager()

    // USB HID key codes
    private let capsLockSrc = 0x700000039  // Caps Lock
    private let f18Dst = 0x70000006D       // F18

    // UserDefaults key for crash recovery
    private let remapActiveKey = "CapsLockRemapActive"

    private var isRemapEnabled = false
    private let queue = DispatchQueue(label: "com.kitlangton.Hex.CapsLockManager")

    private init() {}

    // MARK: - Public API

    /// Enables Caps Lock → F18 remapping and removes the built-in delay.
    /// Returns true if successful.
    @discardableResult
    func enableRemap() -> Bool {
        queue.sync {
            guard !isRemapEnabled else {
                logger.debug("Caps Lock remap already enabled")
                return true
            }

            // Check for existing user mappings first
            if let existingMappings = getCurrentMappings(), !existingMappings.isEmpty {
                logger.warning("User has existing hidutil mappings; merging with Caps Lock remap")
            }

            let success = runHidutil(enable: true)
            if success {
                isRemapEnabled = true
                UserDefaults.standard.set(true, forKey: remapActiveKey)
                logger.info("Caps Lock → F18 remap enabled")
            } else {
                logger.error("Failed to enable Caps Lock remap")
            }
            return success
        }
    }

    /// Disables Caps Lock → F18 remapping, restoring normal Caps Lock behavior.
    /// Returns true if successful.
    @discardableResult
    func disableRemap() -> Bool {
        queue.sync {
            guard isRemapEnabled else {
                logger.debug("Caps Lock remap already disabled")
                return true
            }

            let success = runHidutil(enable: false)
            if success {
                isRemapEnabled = false
                UserDefaults.standard.set(false, forKey: remapActiveKey)
                logger.info("Caps Lock → F18 remap disabled")
            } else {
                logger.error("Failed to disable Caps Lock remap")
            }
            return success
        }
    }

    /// Returns whether the remap is currently active.
    var isActive: Bool {
        queue.sync { isRemapEnabled }
    }

    /// Checks if remap was left active from a previous crash and cleans up if needed.
    /// Call this on app launch.
    func checkCrashRecovery() -> Bool {
        let wasActive = UserDefaults.standard.bool(forKey: remapActiveKey)
        if wasActive && !isRemapEnabled {
            logger.warning("Detected Caps Lock remap left active from previous session")
            return true
        }
        return false
    }

    /// Cleans up any leftover remap state from a crash.
    func cleanupFromCrash() {
        _ = runHidutil(enable: false)
        UserDefaults.standard.set(false, forKey: remapActiveKey)
        logger.info("Cleaned up Caps Lock remap from previous crash")
    }

    // MARK: - Private

    private func runHidutil(enable: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")

        let jsonPayload: String
        if enable {
            // Remap Caps Lock → F18 and remove delay
            jsonPayload = """
            {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(capsLockSrc),"HIDKeyboardModifierMappingDst":\(f18Dst)}],"CapsLockDelayOverride":0}
            """
        } else {
            // Clear all user mappings (restores defaults)
            jsonPayload = """
            {"UserKeyMapping":[]}
            """
        }

        process.arguments = ["property", "--set", jsonPayload]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "unknown error"
                logger.error("hidutil failed with status \(process.terminationStatus): \(output)")
                return false
            }
            return true
        } catch {
            logger.error("Failed to run hidutil: \(error.localizedDescription)")
            return false
        }
    }

    private func getCurrentMappings() -> [[String: Any]]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty,
                  output != "(null)" else {
                return nil
            }

            // hidutil returns plist format, try to parse it
            if let jsonData = output.data(using: .utf8),
               let result = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                return result
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Key Code Constants

extension CapsLockManager {
    /// The key code for F18 that CGEvent will report when Caps Lock is pressed (after remapping)
    static let f18KeyCode: Int = 0x4F  // 79 decimal, kVK_F18
}
