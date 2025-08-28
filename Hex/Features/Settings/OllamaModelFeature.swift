// MARK: – OllamaModelFeature.swift

// A TCA reducer + SwiftUI view for managing Ollama AI models.
// Mirrors the UX of ModelDownloadFeature for voice models.
// Dependencies: ComposableArchitecture, IdentifiedCollections, Dependencies, SwiftUI

import ComposableArchitecture
import Dependencies
import IdentifiedCollections
import SwiftUI
import Foundation


// ──────────────────────────────────────────────────────────────────────────

// MARK: – Data Models

// ──────────────────────────────────────────────────────────────────────────

public struct OllamaModelInfo: Equatable, Identifiable {
	public let name: String
	public let displayName: String
	public let parameterCount: String
	public let context: String
	public let speedStars: Int
	public let capabilityStars: Int
	public let minRAM: Int
	public let storageSize: String
	public var isDownloaded: Bool
	public var isRecommended: Bool
	
	public var id: String { name }
	
	public init(
		name: String,
		displayName: String,
		parameterCount: String,
		context: String,
		speedStars: Int,
		capabilityStars: Int,
		minRAM: Int,
		storageSize: String,
		isDownloaded: Bool,
		isRecommended: Bool
	) {
		self.name = name
		self.displayName = displayName
		self.parameterCount = parameterCount
		self.context = context
		self.speedStars = speedStars
		self.capabilityStars = capabilityStars
		self.minRAM = minRAM
		self.storageSize = storageSize
		self.isDownloaded = isDownloaded
		self.isRecommended = isRecommended
	}
}

public struct CuratedOllamaModel: Equatable, Identifiable, Codable {
	public let name: String
	public let displayName: String
	public let parameterCount: String
	public let context: String
	public let speedStars: Int
	public let capabilityStars: Int
	public let minRAM: Int
	public let storageSize: String
	public var isDownloaded: Bool
	public var isRecommended: Bool
	
	public var id: String { name }
	
	private enum CodingKeys: String, CodingKey {
		case name, displayName, parameterCount, context
		case speedStars, capabilityStars, minRAM, storageSize, isRecommended
	}
	
	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = try c.decode(String.self, forKey: .name)
		displayName = try c.decode(String.self, forKey: .displayName)
		parameterCount = try c.decode(String.self, forKey: .parameterCount)
		context = try c.decode(String.self, forKey: .context)
		speedStars = try c.decode(Int.self, forKey: .speedStars)
		capabilityStars = try c.decode(Int.self, forKey: .capabilityStars)
		minRAM = try c.decode(Int.self, forKey: .minRAM)
		storageSize = try c.decode(String.self, forKey: .storageSize)
		isRecommended = try c.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
		isDownloaded = false
	}
}

public struct SystemCapabilities: Equatable {
	public let totalRAM: Int64 // in GB
	public let hasGPU: Bool
	
	public static func current() -> SystemCapabilities {
		let totalRAM = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
		// Simple GPU detection for Mac (Metal support)
		let hasGPU = true // All modern Macs have Metal GPUs
		return SystemCapabilities(totalRAM: Int64(totalRAM), hasGPU: hasGPU)
	}
}

// Convenience helper for loading the bundled ollama_models.json once.
private enum CuratedOllamaModelLoader {
	static func load() -> [CuratedOllamaModel] {
		guard let url = Bundle.main.url(forResource: "ollama_models", withExtension: "json") ??
			Bundle.main.url(forResource: "ollama_models", withExtension: "json", subdirectory: "Data")
		else {
			assertionFailure("ollama_models.json not found in bundle")
			return []
		}
		do { return try JSONDecoder().decode([CuratedOllamaModel].self, from: Data(contentsOf: url)) }
		catch { assertionFailure("Failed to decode ollama_models.json – \(error)"); return [] }
	}
}

// ──────────────────────────────────────────────────────────────────────────

// MARK: – Domain

// ──────────────────────────────────────────────────────────────────────────

@Reducer
public struct OllamaModelFeature {
	@ObservableState
	public struct State: Equatable {
		// Shared user settings
		@Shared(.hexSettings) var hexSettings: HexSettings
		
		// Remote data
		public var availableModels: IdentifiedArrayOf<OllamaModelInfo> = []
		public var curatedModels: IdentifiedArrayOf<OllamaModelInfo> = []
		public var systemCapabilities: SystemCapabilities = .current()
		
		// Service status
		public var isOllamaRunning = false
		public var lastStatusCheck: Date?
		
		// UI state
		public var showAllModels = false
		public var isDownloading = false
		public var downloadProgress: Double = 0
		public var downloadError: String?
		public var downloadingModelName: String?
		
		// Convenience computed vars
		var selectedModel: String { hexSettings.selectedOllamaModel }
		var selectedModelIsDownloaded: Bool {
			availableModels[id: selectedModel]?.isDownloaded ?? false
		}
		
		var anyModelDownloaded: Bool {
			availableModels.contains(where: { $0.isDownloaded })
		}
		
		func getRecommendedModel() -> String {
			if systemCapabilities.totalRAM >= 32 {
				return "gpt-oss:20b"
			} else if systemCapabilities.totalRAM >= 16 {
				return "qwen2.5:7b"
			} else if systemCapabilities.totalRAM >= 4 {
				return "llama3.2:1b"
			} else {
				return "qwen2.5:0.5b"
			}
		}
		
		func canRunModel(_ model: OllamaModelInfo) -> ModelCompatibility {
			if systemCapabilities.totalRAM >= model.minRAM * 2 {
				return .recommended
			} else if systemCapabilities.totalRAM >= model.minRAM {
				return .compatible
			} else {
				return .incompatible
			}
		}
	}
	
	public enum ModelCompatibility {
		case recommended
		case compatible
		case incompatible
	}
	
	// MARK: Actions
	
	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		// Requests
		case checkOllamaStatus
		case fetchModels
		case selectModel(String)
		case toggleModelDisplay
		case pullModel(String)
		case deleteModel(String)
		case openOllamaApp
		case openModelLocation
		// Effects
		case ollamaStatusChecked(Bool)
		case modelsLoaded([OllamaModel])
		case downloadProgress(Double)
		case downloadCompleted(Result<String, Error>)
	}
	
	// MARK: Dependencies
	
	@Dependency(\.ollama) var ollama
	@Dependency(\.continuousClock) var clock
	
	public init() {}
	
	// MARK: Reducer
	
	public var body: some ReducerOf<Self> {
		BindingReducer()
		Reduce(reduce)
	}
	
	private func reduce(state: inout State, action: Action) -> Effect<Action> {
		switch action {
		// MARK: – UI bindings
		
		case .binding:
			return .none
			
		case .toggleModelDisplay:
			state.showAllModels.toggle()
			return .none
			
		case let .selectModel(model):
			state.$hexSettings.withLock { $0.selectedOllamaModel = model }
			return .none
			
		// MARK: – Ollama Status
		
		case .checkOllamaStatus:
			return .run { send in
				let isRunning = await ollama.isRunning()
				await send(.ollamaStatusChecked(isRunning))
			}
			
		case let .ollamaStatusChecked(isRunning):
			state.isOllamaRunning = isRunning
			state.lastStatusCheck = Date()
			if isRunning {
				return .run { send in await send(.fetchModels) }
			}
			return .none
			
		case .openOllamaApp:
			return .run { _ in
				if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ollama.app") ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jazzignition.ollama") {
					try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
				}
				// Wait a bit for Ollama to start
				try await clock.sleep(for: .seconds(2))
			}
			
		// MARK: – Fetch Models
		
		case .fetchModels:
			return .run { send in
				do {
					let models = try await ollama.listModels()
					print("[OllamaModel] Fetched \(models.count) models from Ollama")
					for model in models {
						print("[OllamaModel] - Model: '\(model.name)', Size: \(model.size)")
					}
					await send(.modelsLoaded(models))
				} catch {
					print("[OllamaModel] ERROR fetching models: \(error)")
					await send(.modelsLoaded([]))
				}
			}
			
		case let .modelsLoaded(ollamaModels):
			// Load curated models
			var curated = CuratedOllamaModelLoader.load()
			let recommendedModel = state.getRecommendedModel()
			
			print("[OllamaModel] Processing models loaded event")
			print("[OllamaModel] Curated models: \(curated.map { $0.name })")
			
			// Build available models list
			var availableModels: [OllamaModelInfo] = []
			
			// Add curated models with download status
			for model in curated {
				// Check if any downloaded model matches our curated model
				let isDownloaded = ollamaModels.contains(where: { ollamaModel in
					// Exact match
					if ollamaModel.name == model.name { 
						print("[OllamaModel] Exact match: '\(ollamaModel.name)' == '\(model.name)'")
						return true 
					}
					
					// Check if it's the same base model (e.g., "llama3.2" in both)
					let ollamaBase = String(ollamaModel.name.split(separator: ":").first ?? "")
					let modelBase = String(model.name.split(separator: ":").first ?? "")
					
					// For llama models, check if the size matches
					if ollamaBase == modelBase {
						// Check if both have the same size identifier
						let ollamaSize = String(ollamaModel.name.split(separator: ":").last ?? "")
						let modelSize = String(model.name.split(separator: ":").last ?? "")
						let matches = ollamaSize == modelSize
						print("[OllamaModel] Base match: '\(ollamaBase)' == '\(modelBase)', Size: '\(ollamaSize)' vs '\(modelSize)' = \(matches)")
						return matches
					}
					
					return false
				})
				
				print("[OllamaModel] Curated model '\(model.name)' isDownloaded: \(isDownloaded)")
				availableModels.append(OllamaModelInfo(
					name: model.name,
					displayName: model.displayName,
					parameterCount: model.parameterCount,
					context: model.context,
					speedStars: model.speedStars,
					capabilityStars: model.capabilityStars,
					minRAM: model.minRAM,
					storageSize: model.storageSize,
					isDownloaded: isDownloaded,
					isRecommended: model.name == recommendedModel
				))
			}
			
			// Add any additional downloaded models not in curated list
			for ollamaModel in ollamaModels {
				// Check if this model is already in our curated list
				let alreadyAdded = availableModels.contains(where: { availModel in
					availModel.name == ollamaModel.name ||
					(availModel.name.split(separator: ":").first == ollamaModel.name.split(separator: ":").first &&
					 availModel.name.split(separator: ":").last == ollamaModel.name.split(separator: ":").last)
				})
				
				if !alreadyAdded {
					// Parse model name for display
					let displayName = ollamaModel.name
						.replacingOccurrences(of: ":", with: " ")
						.replacingOccurrences(of: "-", with: " ")
						.capitalized
					
					availableModels.append(OllamaModelInfo(
						name: ollamaModel.name,
						displayName: displayName,
						parameterCount: "Unknown",
						context: "Unknown",
						speedStars: 3,
						capabilityStars: 3,
						minRAM: 8,
						storageSize: formatBytes(ollamaModel.size),
						isDownloaded: true,
						isRecommended: false
					))
				}
			}
			
			state.availableModels = IdentifiedArrayOf(uniqueElements: availableModels)
			state.curatedModels = IdentifiedArrayOf(
				uniqueElements: availableModels.filter { model in curated.contains(where: { $0.name == model.name }) }
			)
			return .none
			
		// MARK: – Download
		
		case let .pullModel(modelName):
			guard !modelName.isEmpty else { return .none }
			print("[OllamaModel] Starting download for model: '\(modelName)'")
			state.downloadError = nil
			state.isDownloading = true
			state.downloadingModelName = modelName
			state.downloadProgress = 0
			
			// If this model isn't in our list yet, add it as "downloading"
			if state.availableModels[id: modelName] == nil {
				print("[OllamaModel] Model '\(modelName)' not in list, adding it")
				let displayName = modelName
					.replacingOccurrences(of: ":", with: " ")
					.replacingOccurrences(of: "-", with: " ")
					.capitalized
				
				let newModel = OllamaModelInfo(
					name: modelName,
					displayName: displayName,
					parameterCount: "Unknown",
					context: "Unknown",
					speedStars: 3,
					capabilityStars: 3,
					minRAM: 8,
					storageSize: "Unknown",
					isDownloaded: false,
					isRecommended: false
				)
				state.availableModels.append(newModel)
			}
			
			return .run { send in
				do {
					try await ollama.pullModel(modelName) { progress in
						Task { await send(.downloadProgress(progress)) }
					}
					await send(.downloadCompleted(.success(modelName)))
				} catch {
					await send(.downloadCompleted(.failure(error)))
				}
			}
			
		case let .downloadProgress(progress):
			state.downloadProgress = progress
			return .none
			
		case let .downloadCompleted(result):
			state.isDownloading = false
			state.downloadingModelName = nil
			state.downloadProgress = 0
			
			switch result {
			case let .success(name):
				print("[OllamaModel] Download completed successfully for: '\(name)'")
				state.availableModels[id: name]?.isDownloaded = true
				state.curatedModels[id: name]?.isDownloaded = true
				print("[OllamaModel] Marked as downloaded, now refreshing models list")
				// Refresh models to get updated info
				return .run { send in await send(.fetchModels) }
				
			case let .failure(err):
				print("[OllamaModel] Download failed: \(err)")
				state.downloadError = err.localizedDescription
			}
			return .none
			
		// MARK: – Delete
		
		case let .deleteModel(modelName):
			guard !modelName.isEmpty else { return .none }
			return .run { send in
				do {
					try await ollama.deleteModel(modelName)
					await send(.fetchModels)
				} catch {
					await send(.downloadCompleted(.failure(error)))
				}
			}
			
		case .openModelLocation:
			return .run { _ in
				let modelsPath = OllamaModelFeature.ollamaModelsPath()
				if FileManager.default.fileExists(atPath: modelsPath.path) {
					NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelsPath.path)
				} else {
					// If Ollama models directory doesn't exist, open the parent .ollama directory
					let ollamaPath = modelsPath.deletingLastPathComponent()
					if FileManager.default.fileExists(atPath: ollamaPath.path) {
						NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ollamaPath.path)
					}
				}
			}
		}
	}
	
	// MARK: Helpers
	
	private func formatBytes(_ bytes: Int64) -> String {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .binary
		return formatter.string(fromByteCount: bytes)
	}
	
	static func ollamaModelsPath() -> URL {
		// Ollama stores models in ~/.ollama/models
		let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
		return homeDirectory.appendingPathComponent(".ollama/models", isDirectory: true)
	}
}

// ──────────────────────────────────────────────────────────────────────────

// MARK: – SwiftUI Views

// ──────────────────────────────────────────────────────────────────────────

private struct StarRatingView: View {
	let filled: Int
	let max: Int
	
	init(_ filled: Int, max: Int = 5) {
		self.filled = filled
		self.max = max
	}
	
	var body: some View {
		HStack(spacing: 3) {
			ForEach(0 ..< max, id: \.self) { i in
				Image(systemName: i < filled ? "circle.fill" : "circle")
					.font(.system(size: 7))
					.foregroundColor(i < filled ? .blue : .gray.opacity(0.5))
			}
		}
	}
}

public struct OllamaModelView: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	public init(store: StoreOf<OllamaModelFeature>) {
		self.store = store
	}
	
	public var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			// Ollama Status
			OllamaStatusView(store: store)
			
			if store.isOllamaRunning {
				// Header
				HeaderView(store: store)
				
				// Model List
				Group {
					if store.showAllModels {
						AllModelsList(store: store)
					} else {
						CuratedList(store: store)
					}
				}
				
				// Error display
				if let err = store.downloadError {
					Text("Error: \(err)")
						.foregroundColor(.red)
						.font(.caption)
				}
				
				// System Prompt Editor
				SystemPromptEditor(store: store)
				
				// Footer
				FooterView(store: store)
			}
		}
		.task {
			store.send(.checkOllamaStatus)
		}
		.onAppear {
			store.send(.checkOllamaStatus)
		}
	}
}

// MARK: – Subviews

private struct OllamaStatusView: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	var body: some View {
		HStack {
			Label {
				Text("Ollama Service")
			} icon: {
				Image(systemName: store.isOllamaRunning ? "circle.fill" : "circle")
					.foregroundColor(store.isOllamaRunning ? .green : .red)
			}
			
			Spacer()
			
			if !store.isOllamaRunning {
				Button("Launch Ollama") {
					store.send(.openOllamaApp)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
			} else {
				Button(action: { store.send(.checkOllamaStatus) }) {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
				.help("Refresh status")
			}
		}
		.padding(.vertical, 4)
	}
}

private struct HeaderView: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	var body: some View {
		HStack {
			Text(store.showAllModels ? "Showing all models" : "Showing recommended models")
				.font(.caption)
				.foregroundColor(.secondary)
			Spacer()
			Button(
				store.showAllModels ? "Show Recommended" : "Show All Models"
			) {
				store.send(.toggleModelDisplay)
			}
			.font(.caption)
		}
	}
}

private struct AllModelsList: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(store.availableModels) { model in
				ModelRow(store: store, model: model)
			}
		}
	}
}

private struct CuratedList: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			// Header
			HStack(alignment: .bottom) {
				Text("Model")
					.frame(minWidth: 100, alignment: .leading)
					.font(.caption.bold())
				Spacer()
				Text("Speed")
					.frame(minWidth: 60, alignment: .leading)
					.font(.caption.bold())
				Spacer()
				Text("Capability")
					.frame(minWidth: 60, alignment: .leading)
					.font(.caption.bold())
				Spacer()
				Text("Size")
					.frame(minWidth: 60, alignment: .leading)
					.font(.caption.bold())
				Text("Status")
					.frame(minWidth: 80, alignment: .leading)
					.font(.caption.bold())
			}
			.padding(.horizontal, 8)
			
			ForEach(store.curatedModels) { model in
				CuratedRow(store: store, model: model)
			}
		}
	}
}

private struct CuratedRow: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	let model: OllamaModelInfo
	
	var isSelected: Bool {
		model.name == store.hexSettings.selectedOllamaModel
	}
	
	var compatibility: OllamaModelFeature.ModelCompatibility {
		store.state.canRunModel(model)
	}
	
	var statusIcon: some View {
		Group {
			if model.isDownloaded {
				// Don't show any status for downloaded models
				EmptyView()
			} else {
				// Show compatibility status for undownloaded models
				switch compatibility {
				case .recommended:
					if model.isRecommended {
						Label("Recommended", systemImage: "star.fill")
							.foregroundColor(.yellow)
							.font(.caption)
					} else {
						Label("Compatible", systemImage: "checkmark.circle")
							.foregroundColor(.green)
							.font(.caption)
					}
				case .compatible:
					Label("May be slow", systemImage: "exclamationmark.triangle")
						.foregroundColor(.orange)
						.font(.caption)
				case .incompatible:
					Label("\(model.minRAM)GB RAM required", systemImage: "xmark.circle")
						.foregroundColor(.red)
						.font(.caption)
				}
			}
		}
	}
	
	var body: some View {
		Button(
			action: { 
				if model.isDownloaded {
					store.send(.selectModel(model.name))
				} else if compatibility != .incompatible {
					store.send(.pullModel(model.name))
				}
			}
		) {
			HStack {
				HStack {
					Text(model.displayName)
						.font(.headline)
						.foregroundColor(model.isDownloaded ? .primary : .secondary)
					if isSelected && model.isDownloaded {
						Image(systemName: "checkmark")
							.foregroundColor(.blue)
					} else if !model.isDownloaded && compatibility != .incompatible {
						Image(systemName: "arrow.down.circle")
							.foregroundColor(.blue)
							.font(.system(size: 13))
					}
				}
				.frame(minWidth: 100, alignment: .leading)
				
				Spacer()
				StarRatingView(model.speedStars)
					.frame(minWidth: 60, alignment: .leading)
					.opacity(model.isDownloaded ? 1.0 : 0.5)
				
				Spacer()
				StarRatingView(model.capabilityStars)
					.frame(minWidth: 60, alignment: .leading)
					.opacity(model.isDownloaded ? 1.0 : 0.5)
				
				Spacer()
				Text(model.storageSize)
					.foregroundColor(.secondary)
					.frame(minWidth: 60, alignment: .leading)
					.opacity(model.isDownloaded ? 1.0 : 0.6)
				
				statusIcon
					.frame(minWidth: 80, alignment: .leading)
			}
			.padding(8)
			.background(
				RoundedRectangle(cornerRadius: 8)
					.fill(isSelected && model.isDownloaded ? Color.blue.opacity(0.1) : Color.clear)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 8)
					.stroke(
						isSelected && model.isDownloaded
							? Color.blue.opacity(0.3)
							: Color.gray.opacity(0.2)
					)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.disabled(!model.isDownloaded && compatibility == .incompatible)
	}
}

private struct ModelRow: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	let model: OllamaModelInfo
	
	var isSelected: Bool {
		model.name == store.hexSettings.selectedOllamaModel
	}
	
	var body: some View {
		HStack {
			Button(action: {
				if model.isDownloaded {
					store.send(.selectModel(model.name))
				} else {
					store.send(.pullModel(model.name))
				}
			}) {
				HStack {
					Text(model.displayName)
						.foregroundColor(model.isDownloaded ? .primary : .secondary)
					if isSelected && model.isDownloaded {
						Image(systemName: "checkmark")
							.foregroundColor(.blue)
					} else if !model.isDownloaded {
						Image(systemName: "arrow.down.circle")
							.foregroundColor(.blue)
							.font(.system(size: 13))
					}
					if model.isRecommended && !model.isDownloaded {
						Text("Recommended")
							.font(.caption)
							.foregroundColor(.secondary)
					}
					Spacer()
					Text(model.storageSize)
						.foregroundColor(.secondary)
						.opacity(model.isDownloaded ? 1.0 : 0.6)
				}
			}
			.buttonStyle(.plain)
			
			if model.isDownloaded && !isSelected {
				Button("Delete", role: .destructive) {
					store.send(.deleteModel(model.name))
				}
				.buttonStyle(.borderless)
				.font(.caption)
			}
		}
		.padding(4)
	}
}

private struct SystemPromptEditor: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	@State private var isExpanded = false
	@State private var editingPrompt: String = ""
	@FocusState private var isTextEditorFocused: Bool
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Label("System Prompt", systemImage: "text.bubble")
					.font(.headline)
				
				Spacer()
				
				Button(action: {
					withAnimation(.easeInOut(duration: 0.2)) {
						isExpanded.toggle()
						if isExpanded {
							editingPrompt = store.hexSettings.ollamaSystemPrompt
							// Small delay to ensure view is visible before focusing
							DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
								isTextEditorFocused = true
							}
						}
					}
				}) {
					Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
						.foregroundColor(.secondary)
				}
				.buttonStyle(.borderless)
			}
			
			if isExpanded {
				VStack(alignment: .leading, spacing: 8) {
					TextEditor(text: $editingPrompt)
						.font(.system(.body, design: .monospaced))
						.frame(minHeight: 100, maxHeight: 200)
						.padding(4)
						.background(Color(NSColor.textBackgroundColor))
						.overlay(
							RoundedRectangle(cornerRadius: 6)
								.stroke(Color.gray.opacity(0.2), lineWidth: 1)
						)
						.focused($isTextEditorFocused)
					
					HStack {
						Button("Reset to Default") {
							editingPrompt = "Be concise and helpful. For simple calculations or yes/no questions, give just the answer. For explanations or how-to questions, provide clear but brief responses with essential details. Avoid unnecessary preambles or conclusions."
						}
						.buttonStyle(.borderless)
						.foregroundColor(.blue)
						
						Spacer()
						
						Button("Cancel") {
							withAnimation {
								isExpanded = false
								editingPrompt = store.hexSettings.ollamaSystemPrompt
							}
						}
						.buttonStyle(.borderless)
						
						Button("Save") {
							store.$hexSettings.withLock { settings in
								settings.ollamaSystemPrompt = editingPrompt
							}
							withAnimation {
								isExpanded = false
							}
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.small)
					}
				}
				.padding(.top, 4)
			}
		}
		.padding(.vertical, 4)
		.onAppear {
			editingPrompt = store.hexSettings.ollamaSystemPrompt
		}
	}
}

private struct FooterView: View {
	@Bindable var store: StoreOf<OllamaModelFeature>
	
	var body: some View {
		if store.isDownloading, let modelName = store.downloadingModelName {
			VStack(alignment: .leading) {
				Text("Downloading \(modelName)...")
					.font(.caption)
				ProgressView(value: store.downloadProgress)
					.tint(.blue)
			}
		} else {
			HStack {
				if let selected = store.availableModels.first(where: { $0.name == store.hexSettings.selectedOllamaModel }) {
					Text("Selected: \(selected.displayName)")
						.font(.caption)
				}
				Spacer()
				
				Button("Show Models Folder") {
					store.send(.openModelLocation)
				}
				.font(.caption)
				.buttonStyle(.borderless)
				.foregroundStyle(.secondary)
				
				if !store.selectedModelIsDownloaded && 
				   store.curatedModels.contains(where: { $0.name == store.selectedModel }) {
					Button("Download") {
						store.send(.pullModel(store.selectedModel))
					}
					.font(.caption)
					.buttonStyle(.borderless)
				} else if store.selectedModelIsDownloaded && !store.isDownloading {
					Button("Delete", role: .destructive) {
						store.send(.deleteModel(store.selectedModel))
					}
					.font(.caption)
					.buttonStyle(.borderless)
				}
			}
		}
	}
}