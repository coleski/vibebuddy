import ComposableArchitecture
import Inject
import SwiftUI
import Sauce

struct SettingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Form {
			// --- Permissions Section ---
			Section {
				// Microphone
				HStack {
					Label("Microphone", systemImage: "mic.fill")
					Spacer()
					switch store.microphonePermission {
					case .granted:
						Label("Granted", systemImage: "checkmark.circle.fill")
							.foregroundColor(.green)
							.labelStyle(.iconOnly)
					case .denied:
						Button("Request Permission") {
							store.send(.requestMicrophonePermission)
						}
						.buttonStyle(.borderedProminent)
						.tint(.blue)
					case .notDetermined:
						Button("Request Permission") {
							store.send(.requestMicrophonePermission)
						}
						.buttonStyle(.bordered)
					}
				}

				// Accessibility
				HStack {
					Label("Accessibility", systemImage: "accessibility")
					Spacer()
					switch store.accessibilityPermission {
					case .granted:
						Label("Granted", systemImage: "checkmark.circle.fill")
							.foregroundColor(.green)
							.labelStyle(.iconOnly)
					case .denied:
						Button("Request Permission") {
							store.send(.requestAccessibilityPermission)
						}
						.buttonStyle(.borderedProminent)
						.tint(.blue)
					case .notDetermined:
						Button("Request Permission") {
							store.send(.requestAccessibilityPermission)
						}
						.buttonStyle(.bordered)
					}
				}

			} header: {
				Text("Permissions")
			} footer: {
				Text("Ensure Hex can access your microphone and system accessibility features.")
					.font(.footnote)
					.foregroundColor(.secondary)
			}

			// --- Input Device Selection Section ---
			if store.microphonePermission == .granted && !store.availableInputDevices.isEmpty {
				Section {
					// Input device picker
					HStack {
						Label {
							Picker("Input Device", selection: $store.hexSettings.selectedMicrophoneID) {
								Text("System Default").tag(nil as String?)
								ForEach(store.availableInputDevices) { device in
									Text(device.name).tag(device.id as String?)
								}
							}
							.pickerStyle(.menu)
							.id(UUID()) // Force refresh when devices change
						} icon: {
							Image(systemName: "mic.circle")
						}

						Button(action: {
							store.send(.loadAvailableInputDevices)
						}) {
							Image(systemName: "arrow.clockwise")
						}
						.buttonStyle(.borderless)
						.help("Refresh available input devices")
					}

					// Show fallback note for selected device not connected
					if let selectedID = store.hexSettings.selectedMicrophoneID,
					   !store.availableInputDevices.contains(where: { $0.id == selectedID })
					{
						Text("Selected device not connected. System default will be used.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				} header: {
					Text("Microphone Selection")
				} footer: {
					Text("Override the system default microphone with a specific input device. This setting will persist across sessions.")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}

			// --- Transcription Model Section ---
			Section("Transcription Model") {
				ModelDownloadView(store: store.scope(state: \.modelDownload, action: \.modelDownload)
				)
			}

			Label {
				Picker("Output Language", selection: $store.hexSettings.outputLanguage) {
					ForEach(store.languages, id: \.id) { language in
						Text(language.name).tag(language.code)
					}
				}
				.pickerStyle(.menu)
			} icon: {
				Image(systemName: "globe")
			}

			// --- Hot Key Section ---
			Section("Hot Key") {
				let hotKey = store.hexSettings.hotkey
				let key = store.isSettingHotKey ? store.currentKey : hotKey.key
				let modifiers = store.isSettingHotKey ? store.currentModifiers : hotKey.modifiers

				VStack(spacing: 12) {
					// Info text for full keyboard shortcut support
					if hotKey.key != nil && !store.hexSettings.useDoubleTapOnly {
						Text("Hold to record or double-tap to toggle recording")
							.font(.caption)
							.foregroundColor(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)
					} else if hotKey.key != nil && store.hexSettings.useDoubleTapOnly {
						Text("Double-tap to start/stop recording (hold disabled)")
							.font(.caption)
							.foregroundColor(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)
					}

					// Hot key view
					HStack {
						Spacer()
						HotKeyView(modifiers: modifiers, key: key, isActive: store.isSettingHotKey)
							.animation(.spring(), value: key)
							.animation(.spring(), value: modifiers)
						Spacer()
					}
					.contentShape(Rectangle())
					.onTapGesture {
						store.send(.startSettingHotKey)
					}
				}

				// Double-tap toggle (for key+modifier combinations)
				if hotKey.key != nil {
					Label {
						Toggle("Require double-tap (disable hold)", isOn: $store.hexSettings.useDoubleTapOnly)
						Text(store.hexSettings.useDoubleTapOnly ?
							"Double-tap the hotkey to start/stop recording. Holding won't work." :
							"Hold the hotkey to record, or double-tap to toggle recording on/off.")
							.font(.caption)
							.foregroundColor(.secondary)
					} icon: {
						Image(systemName: "hand.tap")
					}
				}

				// Minimum key time (for modifier-only shortcuts)
				if store.hexSettings.hotkey.key == nil {
					Label {
						Slider(value: $store.hexSettings.minimumKeyTime, in: 0.0 ... 2.0, step: 0.1) {
							Text("Ignore below \(store.hexSettings.minimumKeyTime, specifier: "%.1f")s")
						}
					} icon: {
						Image(systemName: "clock")
					}
				}
			}

			// --- Sound Section ---
			Section {
				Label {
					Toggle("Sound Effects", isOn: $store.hexSettings.soundEffectsEnabled)
				} icon: {
					Image(systemName: "speaker.wave.2.fill")
				}
			} header: {
				Text("Sound")
			}

			// --- General Section ---
			Section {
				Label {
					Toggle("Open on Login",
					       isOn: Binding(
					       	get: { store.hexSettings.openOnLogin },
					       	set: { store.send(.toggleOpenOnLogin($0)) }
					       ))
				} icon: {
					Image(systemName: "arrow.right.circle")
				}

				// Dock icon is now always hidden - menu bar only mode
				// Label {
				// 	Toggle("Show Dock Icon", isOn: $store.hexSettings.showDockIcon)
				// } icon: {
				// 	Image(systemName: "dock.rectangle")
				// }

				Label {
					Toggle("Use clipboard to insert", isOn: $store.hexSettings.useClipboardPaste)
					Text("Use clipboard to insert text. Fast but may not restore all clipboard content.\nTurn off to use simulated keypresses. Slower, but doesn't need to restore clipboard")
				} icon: {
					Image(systemName: "doc.on.doc.fill")
				}

				Label {
					Toggle("Copy to clipboard", isOn: $store.hexSettings.copyToClipboard)
					Text("Copy transcription text to clipboard in addition to pasting it")
				} icon: {
					Image(systemName: "doc.on.clipboard")
				}

				Label {
					Toggle(
						"Prevent System Sleep while Recording",
						isOn: Binding(
							get: { store.hexSettings.preventSystemSleep },
							set: { store.send(.togglePreventSystemSleep($0)) }
						)
					)
				} icon: {
					Image(systemName: "zzz")
				}

				Label {
					Toggle(
						"Pause Media while Recording",
						isOn: Binding(
							get: { store.hexSettings.pauseMediaOnRecord },
							set: { store.send(.togglePauseMediaOnRecord($0)) }
						)
					)
				} icon: {
					Image(systemName: "pause")
				}
			} header: {
				Text("General")
			}

			// --- History Section ---
			Section {
				Label {
					Toggle("Save Transcription History", isOn: Binding(
						get: { store.hexSettings.saveTranscriptionHistory },
						set: { store.send(.toggleSaveTranscriptionHistory($0)) }
					))
					Text("Save transcriptions and audio recordings for later access")
						.font(.caption)
						.foregroundColor(.secondary)
				} icon: {
					Image(systemName: "clock.arrow.circlepath")
				}

				if store.hexSettings.saveTranscriptionHistory {
					Label {
						HStack {
							Text("Maximum History Entries")
							Spacer()
							Picker("", selection: Binding(
								get: { store.hexSettings.maxHistoryEntries ?? 0 },
								set: { newValue in
									store.hexSettings.maxHistoryEntries = newValue == 0 ? nil : newValue
								}
							)) {
								Text("Unlimited").tag(0)
								Text("50").tag(50)
								Text("100").tag(100)
								Text("200").tag(200)
								Text("500").tag(500)
								Text("1000").tag(1000)
							}
							.pickerStyle(.menu)
							.frame(width: 120)
						}
					} icon: {
						Image(systemName: "number.square")
					}

					if store.hexSettings.maxHistoryEntries != nil {
						Text("Oldest entries will be automatically deleted when limit is reached")
							.font(.caption)
							.foregroundColor(.secondary)
							.padding(.leading, 28)
					}
				}
			} header: {
				Text("History")
			} footer: {
				if !store.hexSettings.saveTranscriptionHistory {
					Text("When disabled, transcriptions will not be saved and audio files will be deleted immediately after transcription.")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}
			
			// --- AI Assistant Section ---
			Section {
				// Master toggle for AI Assistant
				Label {
					Toggle("Enable AI Assistant", isOn: $store.hexSettings.isAIAssistantEnabled)
				} icon: {
					Image(systemName: "sparkles")
				}

				if store.hexSettings.isAIAssistantEnabled {
					// AI Modifier Key (similar to Hot Key section)
					VStack(spacing: 12) {
						Text("AI Modifier (press with hotkey to trigger AI)")
							.font(.caption)
							.foregroundColor(.secondary)
							.frame(maxWidth: .infinity, alignment: .center)

						// Hot key view for AI modifier
						HStack {
							Spacer()
							HotKeyView(modifiers: [], key: store.isSettingAIKey ? nil : store.hexSettings.aiModifierKey, isActive: store.isSettingAIKey)
								.animation(.spring(), value: store.hexSettings.aiModifierKey)
								.animation(.spring(), value: store.isSettingAIKey)
							Spacer()
						}
						.contentShape(Rectangle())
						.onTapGesture {
							store.send(.startSettingAIKey)
						}
					}

					// Dismissal Speed
					Label {
						Slider(value: $store.hexSettings.aiResponseReadingSpeed, in: 0...1000, step: 50) {
							Text("Dismissal Speed \(Int(store.hexSettings.aiResponseReadingSpeed)) WPM")
						}
						.onChange(of: store.hexSettings.aiResponseReadingSpeed) { newValue in
							print("[SettingsView] WPM slider changed to: \(newValue)")
						}
					} icon: {
						Image(systemName: "timer")
					}
				}
			} header: {
				Text("AI Assistant")
			} footer: {
				if store.hexSettings.isAIAssistantEnabled {
					Text("Hold the AI modifier key while recording to send transcription to Ollama for processing. The response will auto-dismiss based on reading speed.")
						.font(.footnote)
						.foregroundColor(.secondary)
				} else {
					Text("Enable to use AI assistant features. When disabled, the dictation hotkey will work normally without AI interference.")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}
			
			// --- AI Models Section ---
			if store.hexSettings.isAIAssistantEnabled {
				Section {
					OllamaModelView(
						store: store.scope(
							state: \.ollamaModel,
							action: \.ollamaModel
						)
					)
				} header: {
					Text("AI Models")
				}
			}
		}
		.formStyle(GroupedFormStyle())
		.task {
			await store.send(.task).finish()
		}
		.enableInjection()
	}
}
