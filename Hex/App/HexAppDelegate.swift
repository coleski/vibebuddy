import ComposableArchitecture
import SwiftUI

class HexAppDelegate: NSObject, NSApplicationDelegate {
	var invisibleWindow: InvisibleWindow?
	var settingsWindow: NSWindow?
	var statusItem: NSStatusItem!

	@Dependency(\.soundEffects) var soundEffect
	@Shared(.hexSettings) var hexSettings: HexSettings

	func applicationDidFinishLaunching(_: Notification) {
		if isTesting {
			print("TESTING")
			return
		}
		
		// Store self in static property for menu access
		HexApp.sharedDelegate = self

		Task {
			await soundEffect.preloadSounds()
		}
		print("HexAppDelegate did finish launching")
		
		// Clean up any old temporary recording files from previous runs
		cleanupOldTemporaryRecordingFiles()

		// Set activation policy first
		updateAppMode()

		// Add notification observer
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAppModeUpdate),
			name: NSNotification.Name("UpdateAppMode"),
			object: nil
		)

		// Trigger initialization (auto-download of initial model if needed, etc.)
		HexApp.appStore.send(.task)

		// Then present main views
		presentMainView()
		// Don't show settings automatically on startup
		// presentSettingsView()
		// NSApp.activate(ignoringOtherApps: true)
	}

	func presentMainView() {
		guard invisibleWindow == nil else {
			return
		}
		let transcriptionStore = HexApp.appStore.scope(state: \.transcription, action: \.transcription)
		let transcriptionView = TranscriptionView(store: transcriptionStore).padding().padding(.top).padding(.top)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		invisibleWindow = InvisibleWindow.fromView(transcriptionView)
		invisibleWindow?.makeKeyAndOrderFront(nil)
	}

	func presentSettingsView() {
		if let settingsWindow = settingsWindow {
			settingsWindow.makeKeyAndOrderFront(nil)
			settingsWindow.orderFrontRegardless()
			NSApp.activate(ignoringOtherApps: true)
			
			// If window was closed, recreate it
			if !settingsWindow.isVisible {
				self.settingsWindow = nil
				presentSettingsView()
			}
			return
		}

		let settingsView = AppView(store: HexApp.appStore)
		let settingsWindow = NSWindow(
			contentRect: .init(x: 0, y: 0, width: 700, height: 700),
			styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		settingsWindow.titleVisibility = .visible
		settingsWindow.contentView = NSHostingView(rootView: settingsView)
		settingsWindow.isReleasedWhenClosed = false
		settingsWindow.center()
		settingsWindow.toolbarStyle = NSWindow.ToolbarStyle.unified
		settingsWindow.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		self.settingsWindow = settingsWindow
	}

	@objc private func handleAppModeUpdate() {
		Task {
			await updateAppMode()
		}
	}

	@MainActor
	private func updateAppMode() {
		print("hexSettings.showDockIcon: \(hexSettings.showDockIcon)")
		if hexSettings.showDockIcon {
			NSApp.setActivationPolicy(.regular)
		} else {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		presentSettingsView()
		return true
	}
	
	func applicationWillTerminate(_ notification: Notification) {
		// Clean up any temporary recording files when app terminates
		cleanupTemporaryRecordingFiles()
	}
	
	private func cleanupTemporaryRecordingFiles() {
		let tempDir = FileManager.default.temporaryDirectory
		
		do {
			let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
			
			// Remove files that match our recording pattern
			for file in tempFiles {
				let filename = file.lastPathComponent
				if filename.hasPrefix("recording_") && filename.hasSuffix(".wav") {
					try? FileManager.default.removeItem(at: file)
				}
			}
		} catch {
			print("Error cleaning up temporary recording files: \(error)")
		}
	}
	
	private func cleanupOldTemporaryRecordingFiles() {
		let tempDir = FileManager.default.temporaryDirectory
		let now = Date()
		let maxAge: TimeInterval = 24 * 60 * 60 // 24 hours
		
		do {
			let tempFiles = try FileManager.default.contentsOfDirectory(
				at: tempDir, 
				includingPropertiesForKeys: [.contentModificationDateKey]
			)
			
			// Remove old files that match our recording pattern
			for file in tempFiles {
				let filename = file.lastPathComponent
				if filename.hasPrefix("recording_") && filename.hasSuffix(".wav") {
					// Check file age
					if let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
						if now.timeIntervalSince(modificationDate) > maxAge {
							try? FileManager.default.removeItem(at: file)
							print("Cleaned up old temporary recording file: \(filename)")
						}
					} else {
						// If we can't get the date, remove it to be safe
						try? FileManager.default.removeItem(at: file)
					}
				}
			}
		} catch {
			print("Error cleaning up old temporary recording files: \(error)")
		}
	}
}
