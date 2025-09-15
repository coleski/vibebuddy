import ComposableArchitecture
import Inject
import Sparkle
import SwiftUI

@main
struct HexApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}
	
	static let portStore = Store(initialState: PortManagementFeature.State()) {
		PortManagementFeature()
	}

	@NSApplicationDelegateAdaptor(HexAppDelegate.self) var appDelegate
  
	var body: some Scene {
		MenuBarExtra {
			MenuContent()
		} label: {
			let image = SmileyFaceIcon.createIcon(size: CGSize(width: 22, height: 22))
			Image(nsImage: image)
		}


		WindowGroup {}.defaultLaunchBehavior(.suppressed)
			.commands {
				CommandGroup(after: .appInfo) {
					CheckForUpdatesView()

					Button("Settings...") {
						appDelegate.presentSettingsView()
					}.keyboardShortcut(",")
				}
			}
	}
}

// Separate view struct to ensure proper state management
struct MenuContent: View {
	var body: some View {
		PortManagementView(store: HexApp.portStore)
		
		Divider()
		
		CheckForUpdatesView()
		
		Button("Settings...") {
			if let delegate = NSApp.delegate as? HexAppDelegate {
				delegate.presentSettingsView()
			}
		}.keyboardShortcut(",")
		
		Divider()
		
		Button("Quit") {
			NSApplication.shared.terminate(nil)
		}.keyboardShortcut("q")
	}
}
