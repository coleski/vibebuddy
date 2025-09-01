import ComposableArchitecture
import Inject
import Sparkle
import SwiftUI

@main
struct HexApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}

	@NSApplicationDelegateAdaptor(HexAppDelegate.self) var appDelegate
  
	var body: some Scene {
		MenuBarExtra {
			CheckForUpdatesView()

			Button("Settings...") {
				appDelegate.presentSettingsView()
			}.keyboardShortcut(",")
			
			Divider()
			
			Button("Quit") {
				NSApplication.shared.terminate(nil)
			}.keyboardShortcut("q")
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
