//
//  CapsLockClient.swift
//  Hex
//
//  TCA dependency client for Caps Lock remapping functionality.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct CapsLockClient: Sendable {
    /// Enables Caps Lock → F18 remapping
    var enableRemap: @Sendable () -> Bool = { false }

    /// Disables Caps Lock → F18 remapping
    var disableRemap: @Sendable () -> Bool = { false }

    /// Returns whether the remap is currently active
    var isActive: @Sendable () -> Bool = { false }

    /// Checks if remap was left active from a previous crash
    var checkCrashRecovery: @Sendable () -> Bool = { false }

    /// Cleans up remap state from a crash
    var cleanupFromCrash: @Sendable () -> Void = {}

    /// The key code for F18 that CGEvent reports when Caps Lock is pressed
    var f18KeyCode: @Sendable () -> Int = { CapsLockManager.f18KeyCode }
}

extension CapsLockClient: DependencyKey {
    static var liveValue: CapsLockClient {
        let manager = CapsLockManager.shared

        return CapsLockClient(
            enableRemap: {
                manager.enableRemap()
            },
            disableRemap: {
                manager.disableRemap()
            },
            isActive: {
                manager.isActive
            },
            checkCrashRecovery: {
                manager.checkCrashRecovery()
            },
            cleanupFromCrash: {
                manager.cleanupFromCrash()
            },
            f18KeyCode: {
                CapsLockManager.f18KeyCode
            }
        )
    }
}

extension CapsLockClient: TestDependencyKey {
    static var testValue: CapsLockClient {
        CapsLockClient()
    }

    static var previewValue: CapsLockClient {
        CapsLockClient(
            enableRemap: { true },
            disableRemap: { true },
            isActive: { false },
            checkCrashRecovery: { false },
            cleanupFromCrash: {},
            f18KeyCode: { CapsLockManager.f18KeyCode }
        )
    }
}

extension DependencyValues {
    var capsLock: CapsLockClient {
        get { self[CapsLockClient.self] }
        set { self[CapsLockClient.self] = newValue }
    }
}
