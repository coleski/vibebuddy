//
//  TranscriptionFeature.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import CoreGraphics
import Inject
import SwiftUI
import WhisperKit
import IOKit
import IOKit.pwr_mgt
import Sauce

struct QueuedTranscription: Identifiable, Equatable {
  let id = UUID()
  let audioURL: URL
  let startTime: Date
  let isAIMode: Bool
  let model: String
  let language: String?
  let wasAddedToActiveQueue: Bool // True if queue was already processing when added
}

enum TranscriptionError: Error, LocalizedError {
  case audioFileNotFound(URL)
  case modelNotAvailable(String)
  case transcriptionFailed(String)
  case pasteOperationFailed(String)
  
  var errorDescription: String? {
    switch self {
    case .audioFileNotFound(let url):
      return "Audio file not found: \(url.lastPathComponent)"
    case .modelNotAvailable(let model):
      return "Transcription model '\(model)' is not available"
    case .transcriptionFailed(let reason):
      return "Transcription failed: \(reason)"
    case .pasteOperationFailed(let reason):
      return "Paste operation failed: \(reason)"
    }
  }
}

@Reducer
struct TranscriptionFeature {
  @ObservableState
  struct State {
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var isPrewarming: Bool = false
    var needsModel: Bool = false
    var isAIMode: Bool = false
    var aiResponse: String?
    var isGeneratingAI: Bool = false
    var error: String?
    var recordingStartTime: Date?
    var meter: Meter = .init(averagePower: 0, peakPower: 0)
    var assertionID: IOPMAssertionID?
    
    // Queue management
    var transcriptionQueue: [QueuedTranscription] = []
    var isProcessingQueue: Bool = false
    static let maxQueueSize = 10 // Prevent memory issues with too many concurrent recordings
    
    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case task
    case audioLevelUpdated(Meter)

    // Hotkey actions
    case hotKeyPressed(isAIMode: Bool = false)
    case hotKeyReleased

    // Recording flow
    case startRecording
    case recordingStarted
    case stopRecording
    case modelCheckResult(Bool)
    case hideNeedsModelIndicator

    // Cancel entire flow
    case cancel(playSound: Bool = true)

    // Transcription result flow
    case transcriptionResult(String)
    case transcriptionError(Error)
    
    // Queue management
    case queueTranscription(QueuedTranscription)
    case startProcessingQueue
    case transcriptionQueueResult(id: UUID, result: String)
    case transcriptionQueueError(id: UUID, error: Error)
    
    // AI Mode
    case setAIMode(Bool)
    case aiResponseReceived(String)
    case aiGenerationError(Error)
    case clearAIResponse
  }

  enum CancelID {
    case delayedRecord
    case metering
    case transcription
    case queueProcessing
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.ollama) var ollama

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Starts two concurrent effects:
        // 1) Observing audio meter
        // 2) Monitoring hot key events
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect()
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case let .hotKeyPressed(isAIMode):
        // Start recording - allow during transcription but not during another recording
        print("[HOTKEY] Hot key pressed - AI Mode: \(isAIMode)")
        print("[HOTKEY] Current state - isRecording: \(state.isRecording), isTranscribing: \(state.isTranscribing), isProcessingQueue: \(state.isProcessingQueue)")
        print("[HOTKEY] Queue size: \(state.transcriptionQueue.count)")
        print("[HOTKEY] Thread: \(Thread.current)")
        
        // Check for potential conflicts
        if state.isRecording {
            print("[HOTKEY] WARNING: Already recording! This might cause conflicts.")
        }
        
        state.isAIMode = isAIMode
        return handleHotKeyPressed(minimumKeyTime: state.hexSettings.minimumKeyTime)

      case .hotKeyReleased:
        // If we’re currently recording, then stop. Otherwise, just cancel
        // the delayed “startRecording” effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        print("[RECORDING] startRecording action received")
        print("[RECORDING] Current state - isRecording: \(state.isRecording), isTranscribing: \(state.isTranscribing)")
        print("[RECORDING] Thread: \(Thread.current)")
        
        // Safety check - prevent concurrent recordings
        guard !state.isRecording else {
            print("[RECORDING] ERROR: Attempted to start recording while already recording! Ignoring.")
            return .none
        }
        
        // First check if model is available
        let model = state.hexSettings.selectedModel
        print("[RECORDING] Checking model availability: \(model)")
        return .run { send in
          let isModelAvailable = await transcription.isModelDownloaded(model)
          print("[RECORDING] Model \(model) availability: \(isModelAvailable)")
          await send(.modelCheckResult(isModelAvailable))
        }
        
      case .recordingStarted:
        return handleRecordingStarted(&state)
        
      case let .modelCheckResult(isAvailable):
        if isAvailable {
          return handleStartRecording(&state)
        } else {
          // Show "needs model" indicator
          state.needsModel = true
          return .merge(
            .run { _ in
              await soundEffect.play(.cancel)
            },
            .run { send in
              try? await Task.sleep(for: .seconds(2))
              await send(.hideNeedsModelIndicator)
            }
          )
        }
        
      case .hideNeedsModelIndicator:
        state.needsModel = false
        return .none

      case .stopRecording:
        print("[RECORDING] stopRecording action received")
        print("[RECORDING] Current state - isRecording: \(state.isRecording), duration: \(state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0)s")
        print("[RECORDING] Thread: \(Thread.current)")
        
        guard state.isRecording else {
            print("[RECORDING] WARNING: Attempted to stop recording when not recording! Ignoring.")
            return .none
        }
        
        return handleStopRecording(&state)

      // MARK: - Transcription Results

      case let .transcriptionResult(result):
        return handleTranscriptionResult(&state, result: result)

      case let .transcriptionError(error):
        return handleTranscriptionError(&state, error: error)
        
      // MARK: - Queue Management
      
      case let .queueTranscription(queuedTranscription):
        print("[QUEUE] Adding item to queue: ID \(queuedTranscription.id), AI Mode: \(queuedTranscription.isAIMode)")
        print("[QUEUE] Audio file: \(queuedTranscription.audioURL.lastPathComponent)")
        print("[QUEUE] Current thread: \(Thread.current)")
        print("[QUEUE] State before adding - isProcessingQueue: \(state.isProcessingQueue), isTranscribing: \(state.isTranscribing), isRecording: \(state.isRecording)")
        
        // Check if queue is at maximum capacity
        if state.transcriptionQueue.count >= State.maxQueueSize {
          print("[QUEUE] Queue at maximum capacity (\(State.maxQueueSize)), discarding oldest item")
          if let oldestItem = state.transcriptionQueue.first {
            // Clean up the oldest audio file
            let cleanupEffect = Effect<Action>.run { _ in
              do {
                try FileManager.default.removeItem(at: oldestItem.audioURL)
                print("[QUEUE] Cleaned up oldest audio file: \(oldestItem.audioURL.lastPathComponent)")
              } catch {
                print("[QUEUE] Failed to clean up oldest audio file: \(error)")
              }
            }
            state.transcriptionQueue.removeFirst()
            
            // Add new item and start cleanup
            state.transcriptionQueue.append(queuedTranscription)
            
            return .merge(
              cleanupEffect,
              state.isProcessingQueue ? .none : .send(.startProcessingQueue)
            )
          }
        }
        
        state.transcriptionQueue.append(queuedTranscription)
        print("[QUEUE] Queue size after adding: \(state.transcriptionQueue.count)")
        print("[QUEUE] Currently processing queue: \(state.isProcessingQueue)")
        print("[QUEUE] Full queue state: \(state.transcriptionQueue.map { "ID: \($0.id), AI: \($0.isAIMode), File: \($0.audioURL.lastPathComponent)" })")
        
        // Start processing queue if not already processing
        if !state.isProcessingQueue {
          print("[QUEUE] Starting queue processing...")
          return .send(.startProcessingQueue)
        }
        print("[QUEUE] Queue processing already in progress")
        return .none
        
      case .startProcessingQueue:
        print("[QUEUE] startProcessingQueue called - queue size: \(state.transcriptionQueue.count)")
        print("[QUEUE] isProcessingQueue: \(state.isProcessingQueue)")
        print("[QUEUE] Current state snapshot:")
        print("[QUEUE]   - isRecording: \(state.isRecording)")
        print("[QUEUE]   - isTranscribing: \(state.isTranscribing)")
        print("[QUEUE]   - isPrewarming: \(state.isPrewarming)")
        print("[QUEUE]   - isProcessingQueue: \(state.isProcessingQueue)")
        
        guard !state.transcriptionQueue.isEmpty else {
          print("[QUEUE] Queue is empty - stopping processing")
          print("[QUEUE] Resetting all processing states")
          state.isProcessingQueue = false
          // Clear transcribing indicators since queue is done
          state.isTranscribing = false
          state.isPrewarming = false
          state.isGeneratingAI = false
          return .none
        }
        
        // Prevent concurrent processing
        guard !state.isProcessingQueue else {
          print("[QUEUE] Queue processing already in progress - ignoring duplicate call")
          return .none
        }
        
        print("[QUEUE] Starting queue processing")
        state.isProcessingQueue = true
        state.isTranscribing = true
        state.isPrewarming = true
        
        let queuedItem = state.transcriptionQueue[0]
        print("[QUEUE] Processing item ID: \(queuedItem.id), AI Mode: \(queuedItem.isAIMode), Model: \(queuedItem.model)")
        print("[QUEUE] Memory address of queue item: \(Unmanaged.passUnretained(queuedItem as AnyObject).toOpaque())")
        print("[QUEUE] Transcription thread: \(Thread.current)")
        
        return .run { send in
          do {
            let startTime = Date()
            print("[QUEUE] Starting transcription for queued audio at \(startTime)")
            print("[QUEUE] Audio URL: \(queuedItem.audioURL.lastPathComponent)")
            
            // Check if audio file still exists
            guard FileManager.default.fileExists(atPath: queuedItem.audioURL.path) else {
              throw TranscriptionError.audioFileNotFound(queuedItem.audioURL)
            }
            
            // Check if model is still available (it might have been deleted)
            let isModelAvailable = await transcription.isModelDownloaded(queuedItem.model)
            guard isModelAvailable else {
              throw TranscriptionError.modelNotAvailable(queuedItem.model)
            }
            
            // Create transcription options with the selected language
            let decodeOptions = DecodingOptions(
              language: queuedItem.language,
              detectLanguage: queuedItem.language == nil,
              chunkingStrategy: .vad
            )
            
            let transcriptionStart = Date()
            // Create an immutable copy of the result to prevent corruption
            let transcriptionResult = try await transcription.transcribe(queuedItem.audioURL, queuedItem.model, decodeOptions) { _ in }
            // Make an explicit copy to isolate the string and validate it
            let result = String(transcriptionResult)
            
            // Validate the result doesn't contain corruption patterns
            let containsCorruption = result.contains { char in
              // Check for common corruption patterns (high Unicode values, control chars)
              let scalar = char.unicodeScalars.first?.value ?? 0
              return scalar > 127 && !char.isLetter && !char.isNumber && !char.isPunctuation && !char.isWhitespace
            }
            
            if containsCorruption {
              print("[QUEUE] WARNING: Transcription result appears corrupted!")
              print("[QUEUE] Corrupted result preview: '\(result.prefix(50))'")
              print("[QUEUE] Unicode values: \(result.prefix(20).unicodeScalars.map { $0.value })")
              // Return empty string instead of corrupted text
              await send(.transcriptionQueueResult(id: queuedItem.id, result: ""))
            } else {
              await send(.transcriptionQueueResult(id: queuedItem.id, result: result))
            }
            let transcriptionEnd = Date()
            let transcriptionTime = transcriptionEnd.timeIntervalSince(transcriptionStart)
            
            print("[QUEUE] Transcription completed in \(String(format: "%.2f", transcriptionTime))s: '\(result)'")
            print("[QUEUE] Result length: \(result.count) characters")
            print("[QUEUE] Result UTF-8 byte count: \(result.utf8.count)")
            print("[QUEUE] Result contains non-ASCII: \(result.contains { !$0.isASCII })")
            print("[QUEUE] Sending transcription result at \(transcriptionEnd)")
            print("[QUEUE] Memory address of result string: \(Unmanaged.passUnretained(result as AnyObject).toOpaque())")
            await send(.transcriptionQueueResult(id: queuedItem.id, result: result))
          } catch {
            print("[QUEUE] Error transcribing queued audio: \(error)")
            await send(.transcriptionQueueError(id: queuedItem.id, error: error))
          }
        }
        .cancellable(id: CancelID.queueProcessing)
        
      case let .transcriptionQueueResult(id, result):
        print("[ACTION] transcriptionQueueResult received - ID: \(id), result length: \(result.count)")
        print("[ACTION] Current state - isTranscribing: \(state.isTranscribing), queue size: \(state.transcriptionQueue.count)")
        return handleQueueTranscriptionResult(&state, id: id, result: result)
        
      case let .transcriptionQueueError(id, error):
        return handleQueueTranscriptionError(&state, id: id, error: error)
        
      // MARK: - AI Mode
      
      case let .setAIMode(enabled):
        state.isAIMode = enabled
        return .none
      
      case let .aiResponseReceived(response):
        state.aiResponse = response
        state.isGeneratingAI = false
        
        // If we're processing a queue, maintain transcribing state
        // until the entire queue is done
        if !state.isProcessingQueue {
          state.isTranscribing = false
        }
        
        // AI responses are only displayed in modal, never automatically pasted
        // The user must manually copy/paste from the modal
        print("[AI] AI response received and displayed in modal: '\(response)'")
        return .none
        
      case let .aiGenerationError(error):
        state.isGeneratingAI = false
        state.error = error.localizedDescription
        
        // If we're processing a queue, maintain transcribing state
        if !state.isProcessingQueue {
          state.isTranscribing = false
        }
        
        return .run { _ in
          await soundEffect.play(.cancel)
        }
        
      case .clearAIResponse:
        state.aiResponse = nil
        state.isAIMode = false
        return .none

      // MARK: - Cancel Entire Flow

      case let .cancel(playSound):
        // Only cancel if we're in the middle of recording or transcribing
        guard state.isRecording || state.isTranscribing else {
          return .none
        }
        return handleCancel(&state, playSound: playSound)
      }
    }
  }
}

// MARK: - Effects: Metering & HotKey

private extension TranscriptionFeature {
  /// Effect to begin observing the audio meter.
  func startMeteringEffect() -> Effect<Action> {
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering, cancelInFlight: true)
  }

  /// Effect to start monitoring hotkey events through the `keyEventMonitor`.
  func startHotKeyMonitoringEffect() -> Effect<Action> {
    .run { send in
      var hotKeyProcessor: HotKeyProcessor = .init(hotkey: HotKey(key: nil, modifiers: [.option]), aiKey: nil)
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.hexSettings) var hexSettings: HexSettings
      
      // Track if AI key is held during recording
      var isAIKeyHeld = false
      var isCurrentlyRecording = false
      
      // Handle incoming key events
      keyEventMonitor.handleKeyEvent { keyEvent in
        // Skip if the user is currently setting a hotkey
        if isSettingHotKey {
          return false
        }

        // If Escape is pressed with no modifiers while idle, let's treat that as `cancel`.
        if keyEvent.key == .escape, keyEvent.modifiers.isEmpty,
           hotKeyProcessor.state == .idle
        {
          Task { await send(.cancel(playSound: true)) }
          return false
        }
        
        // Track AI modifier key when we're recording (only if AI assistant is enabled)
        if isCurrentlyRecording && hexSettings.isAIAssistantEnabled && keyEvent.key == hexSettings.aiModifierKey {
          isAIKeyHeld = true
          // Immediately update AI mode visually
          Task { await send(.setAIMode(true)) }
          return true // Intercept the AI key to prevent system beep
        }

        // Always keep hotKeyProcessor in sync with current user hotkey preference
        hotKeyProcessor.hotkey = hexSettings.hotkey
        hotKeyProcessor.useDoubleTapOnly = hexSettings.useDoubleTapOnly
        hotKeyProcessor.aiKey = hexSettings.aiModifierKey

        // Process the key event
        switch hotKeyProcessor.process(keyEvent: keyEvent) {
        case .startRecording:
          isCurrentlyRecording = true
          isAIKeyHeld = false // Reset AI mode flag

          // If double-tap lock is triggered, we start recording immediately
          if hotKeyProcessor.state == .doubleTapLock {
            Task { await send(.startRecording) }
          } else {
            Task { await send(.hotKeyPressed(isAIMode: false)) }
          }
          // If the hotkey is purely modifiers, return false to keep it from interfering with normal usage
          // But if useDoubleTapOnly is true, always intercept the key
          return hexSettings.useDoubleTapOnly || keyEvent.key != nil

        case .stopRecording:
          isCurrentlyRecording = false
          let wasAIMode = isAIKeyHeld
          isAIKeyHeld = false
          // Pass the AI mode state when releasing
          Task { 
            if wasAIMode {
              await send(.setAIMode(true))
            }
            await send(.hotKeyReleased) 
          }
          return false

        case .cancel:
          Task { await send(.cancel(playSound: true)) }
          return true

        case .none:
          // If we're recording and a non-hotkey/non-AI key is pressed, cancel the recording
          if isCurrentlyRecording {
            // Check if this is neither the hotkey nor the AI key
            let isHotkey = (keyEvent.key == hotKeyProcessor.hotkey.key &&
                           keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers)
            let isAIKey = hexSettings.isAIAssistantEnabled && (keyEvent.key == hexSettings.aiModifierKey)

            if !isHotkey && !isAIKey && keyEvent.key != nil {
              // Cancel the recording (silent - accidental key detection)
              isCurrentlyRecording = false
              isAIKeyHeld = false
              Task { await send(.cancel(playSound: false)) }
              return true
            }
          }
          
          // If we detect repeated same chord, maybe intercept.
          if let pressedKey = keyEvent.key,
             pressedKey == hotKeyProcessor.hotkey.key,
             keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers
          {
            return true
          }
          return false
        }
      }
    }
  }
}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyPressed(minimumKeyTime: Double) -> Effect<Action> {
    // We wait minimumKeyTime before actually sending `.startRecording`
    // so the user can do a quick press => do something else
    // (like a double-tap).
    let delayedStart = Effect.run { send in
      try await Task.sleep(for: .seconds(minimumKeyTime))
      await send(Action.startRecording)
    }
    .cancellable(id: CancelID.delayedRecord, cancelInFlight: true)

    return delayedStart
  }

  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    if isRecording {
      // We actually stop if we’re currently recording
      return .send(.stopRecording)
    } else {
      // If not recording yet, just cancel the delayed start
      return .cancel(id: CancelID.delayedRecord)
    }
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    return .run { send in
      let recordingStarted = await recording.startRecording()
      
      if recordingStarted {
        await send(.recordingStarted)
      } else {
        // Recording couldn't start (probably already recording)
        print("Recording could not start - likely already in progress")
      }
    }
  }
  
  func handleRecordingStarted(_ state: inout State) -> Effect<Action> {
    state.isRecording = true
    state.recordingStartTime = Date()
    state.needsModel = false
    
    // Clear any previous AI response when starting new recording
    state.aiResponse = nil

    // Prevent system sleep during recording
    if state.hexSettings.preventSystemSleep {
      preventSystemSleep(&state)
    }

    return .run { _ in
      await soundEffect.play(.startRecording)
    }
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    state.isRecording = false

    // Allow system to sleep again by releasing the power management assertion
    // Always call this, even if the setting is off, to ensure we don't leak assertions
    //  (e.g. if the setting was toggled off mid-recording)
    reallowSystemSleep(&state)

    let durationIsLongEnough: Bool = {
      guard let startTime = state.recordingStartTime else { return false }
      return Date().timeIntervalSince(startTime) > state.hexSettings.minimumKeyTime
    }()

    // For modifier-only hotkeys, enforce minimum duration
    // For hotkeys with a regular key, always proceed (intentional press)
    let shouldProceed = durationIsLongEnough || state.hexSettings.hotkey.key != nil

    guard shouldProceed else {
      // Recording was too short for a modifier-only hotkey
      print("Recording was too short, discarding")
      return .run { _ in
        _ = await recording.stopRecording()
      }
    }

    // Create queued transcription instead of immediate transcription
    let model = state.hexSettings.selectedModel
    let language = state.hexSettings.outputLanguage
    let isAIMode = state.isAIMode
    let startTime = state.recordingStartTime ?? Date()
    // Track if we're adding to an already-active queue
    let wasAddedToActiveQueue = state.isProcessingQueue || state.isTranscribing
    
    return .run { send in
      await soundEffect.play(.stopRecording)
      let audioURL = await recording.stopRecording()
      
      // Validate that we have a valid audio file
      let fileExists = FileManager.default.fileExists(atPath: audioURL.path)
      print("[RECORDING] Audio file exists: \(fileExists), URL: \(audioURL.lastPathComponent)")
      
      if fileExists {
        // Get file size to ensure it's not empty
        if let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let fileSize = attributes[.size] as? Int64 {
          print("[RECORDING] Audio file size: \(fileSize) bytes")
          
          // Only queue if file has meaningful content (> 1KB)
          if fileSize > 1024 {
            let queuedTranscription = QueuedTranscription(
              audioURL: audioURL,
              startTime: startTime,
              isAIMode: isAIMode,
              model: model,
              language: language,
              wasAddedToActiveQueue: wasAddedToActiveQueue
            )
            
            await send(.queueTranscription(queuedTranscription))
          } else {
            print("[RECORDING] Audio file too small (\(fileSize) bytes), discarding")
            try? FileManager.default.removeItem(at: audioURL)
          }
        } else {
          print("[RECORDING] Could not get audio file size, discarding")
          try? FileManager.default.removeItem(at: audioURL)
        }
      } else {
        print("[RECORDING] Audio file does not exist, skipping transcription")
      }
    }
  }
}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String
  ) -> Effect<Action> {
    // Only clear transcribing state if we're NOT processing a queue
    // Queue processing will manage its own state
    if !state.isProcessingQueue {
      state.isTranscribing = false
      state.isPrewarming = false
    }

    // If empty text, nothing else to do
    guard !result.isEmpty else {
      state.isAIMode = false
      return .none
    }

    // Check if we're in AI mode
    if state.isAIMode {
      state.isGeneratingAI = true
      let model = state.hexSettings.selectedOllamaModel
      let systemPrompt = state.hexSettings.ollamaSystemPrompt
      
      return .run { send in
        do {
          let response = try await ollama.generate(result, model, systemPrompt)
          await send(.aiResponseReceived(response))
        } catch {
          await send(.aiGenerationError(error))
        }
      }
    } else {
      // Normal transcription mode - paste the text
      // Compute how long we recorded
      let duration = state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

      // Continue with storing the final result in the background
      return finalizeRecordingAndStoreTranscript(
        result: result,
        duration: duration,
        transcriptionHistory: state.$transcriptionHistory
      )
    }
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error
  ) -> Effect<Action> {
    // Only clear transcribing state if we're NOT processing a queue
    if !state.isProcessingQueue {
      state.isTranscribing = false
      state.isPrewarming = false
    }
    state.error = error.localizedDescription

    return .run { _ in
      await soundEffect.play(.cancel)
    }
  }

  /// Move file to permanent location, create a transcript record, paste text, and play sound.
  func finalizeRecordingAndStoreTranscript(
    result: String,
    duration: TimeInterval,
    transcriptionHistory: Shared<TranscriptionHistory>
  ) -> Effect<Action> {
    .run { send in
      do {
        let originalURL = await recording.stopRecording()
        
        @Shared(.hexSettings) var hexSettings: HexSettings

        // Check if we should save to history
        if hexSettings.saveTranscriptionHistory {
          // Move the file to a permanent location
          let fm = FileManager.default
          let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          )
          let ourAppFolder = supportDir.appendingPathComponent("com.kitlangton.Hex", isDirectory: true)
          let recordingsFolder = ourAppFolder.appendingPathComponent("Recordings", isDirectory: true)
          try fm.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

          // Create a unique file name
          let filename = "\(Date().timeIntervalSince1970).wav"
          let finalURL = recordingsFolder.appendingPathComponent(filename)

          // Move temp => final
          try fm.moveItem(at: originalURL, to: finalURL)

          // Build a transcript object
          let transcript = Transcript(
            timestamp: Date(),
            text: result,
            audioPath: finalURL,
            duration: duration
          )

          // Append to the in-memory shared history
          transcriptionHistory.withLock { history in
            history.history.insert(transcript, at: 0)
            
            // Trim history if max entries is set
            if let maxEntries = hexSettings.maxHistoryEntries, maxEntries > 0 {
              while history.history.count > maxEntries {
                if let removedTranscript = history.history.popLast() {
                  // Delete the audio file
                  try? FileManager.default.removeItem(at: removedTranscript.audioPath)
                }
              }
            }
          }
        } else {
          // If not saving history, just delete the temp audio file
          try? FileManager.default.removeItem(at: originalURL)
        }

        // Paste text (and copy if enabled via pasteWithClipboard)
        await pasteboard.paste(result)
        await soundEffect.play(.pasteTranscript)
      } catch {
        await send(.transcriptionError(error))
      }
    }
  }
  
  /// Finalize a queued transcription (similar to finalizeRecordingAndStoreTranscript but for queue items)
  func finalizeQueuedTranscript(
    result: String,
    duration: TimeInterval,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>,
    wasAddedToActiveQueue: Bool = false
  ) -> Effect<Action> {
    .run { send in
      let finalizeStart = Date()
      print("[TIMING] finalizeQueuedTranscript started at \(finalizeStart)")
      
      do {
        @Shared(.hexSettings) var hexSettings: HexSettings
        
        // If this was added to an already-active queue (not the first item),
        // prepend a space for natural flow
        let textToInsert = wasAddedToActiveQueue ? " \(result)" : result
        print("[QUEUE] Text to insert: '\(textToInsert)' (prepended space: \(wasAddedToActiveQueue))")

        // Check if we should save to history
        if hexSettings.saveTranscriptionHistory {
          // Move the file to a permanent location
          let fm = FileManager.default
          let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          )
          let ourAppFolder = supportDir.appendingPathComponent("com.kitlangton.Hex", isDirectory: true)
          let recordingsFolder = ourAppFolder.appendingPathComponent("Recordings", isDirectory: true)
          try fm.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

          // Create a unique file name
          let filename = "\(Date().timeIntervalSince1970).wav"
          let finalURL = recordingsFolder.appendingPathComponent(filename)

          // Move temp => final
          try fm.moveItem(at: audioURL, to: finalURL)

          // Build a transcript object
          let transcript = Transcript(
            timestamp: Date(),
            text: result,
            audioPath: finalURL,
            duration: duration
          )

          // Append to the in-memory shared history
          transcriptionHistory.withLock { history in
            history.history.insert(transcript, at: 0)
            
            // Trim history if max entries is set
            if let maxEntries = hexSettings.maxHistoryEntries, maxEntries > 0 {
              while history.history.count > maxEntries {
                if let removedTranscript = history.history.popLast() {
                  // Delete the audio file
                  try? FileManager.default.removeItem(at: removedTranscript.audioPath)
                }
              }
            }
          }
        } else {
          // If not saving history, just delete the temp audio file
          try? FileManager.default.removeItem(at: audioURL)
        }

        // Paste text (and copy if enabled via pasteWithClipboard)
        let pasteStart = Date()
        print("[TIMING] Starting paste operation at \(pasteStart)")
        print("[PASTE] About to paste text: '\(String(textToInsert.prefix(100)))\(textToInsert.count > 100 ? "..." : "")'")
        print("[PASTE] Text memory address before paste: \(Unmanaged.passUnretained(textToInsert as AnyObject).toOpaque())")
        print("[PASTE] Text integrity pre-paste - length: \(textToInsert.count), UTF-8 bytes: \(textToInsert.utf8.count)")
        
        // Create a copy to detect corruption
        let resultCopy = String(textToInsert)
        print("[PASTE] Created result copy - matches original: \(textToInsert == resultCopy)")
        
        await pasteboard.paste(textToInsert)
        
        // Check if original got corrupted during paste
        let corruptionCheck = (textToInsert == resultCopy)
        print("[PASTE] Post-paste corruption check - original still matches copy: \(corruptionCheck)")
        if !corruptionCheck {
          print("[PASTE] CORRUPTION DETECTED! Original: '\(String(textToInsert.prefix(50)))', Copy: '\(String(resultCopy.prefix(50)))'")
        }
        
        let pasteEnd = Date()
        let pasteTime = pasteEnd.timeIntervalSince(pasteStart)
        print("[TIMING] Paste completed in \(String(format: "%.2f", pasteTime))s at \(pasteEnd)")
        
        await soundEffect.play(.pasteTranscript)
        
        let finalizeEnd = Date()
        let totalFinalizeTime = finalizeEnd.timeIntervalSince(finalizeStart)
        print("[TIMING] finalizeQueuedTranscript total time: \(String(format: "%.2f", totalFinalizeTime))s")
        print("[TIMING] finalization completed successfully for text of length \(textToInsert.count)")
      } catch {
        print("[ERROR] finalizeQueuedTranscript failed: \(error)")
        print("[ERROR] Result at time of error: '\(String(textToInsert.prefix(50)))'")
        await send(.transcriptionError(error))
      }
    }
  }
  
  // MARK: - Queue Processing Handlers
  
  func handleQueueTranscriptionResult(
    _ state: inout State,
    id: UUID,
    result: String
  ) -> Effect<Action> {
    let handleStart = Date()
    print("[QUEUE] handleQueueTranscriptionResult started at \(handleStart) for item ID: \(id)")
    print("[QUEUE] Current queue size: \(state.transcriptionQueue.count)")
    print("[QUEUE] Transcription result: '\(result)' (length: \(result.count))")
    print("[QUEUE] Result memory address: \(Unmanaged.passUnretained(result as AnyObject).toOpaque())")
    print("[QUEUE] Current thread: \(Thread.current)")
    print("[QUEUE] State snapshot - isProcessingQueue: \(state.isProcessingQueue), isTranscribing: \(state.isTranscribing), isRecording: \(state.isRecording)")
    
    // Find the processed item to get its settings
    guard let processedItemIndex = state.transcriptionQueue.firstIndex(where: { $0.id == id }) else {
      print("[QUEUE] ERROR: Item with ID \(id) not found in queue - continuing processing")
      return .send(.startProcessingQueue)
    }
    
    let processedItem = state.transcriptionQueue[processedItemIndex]
    print("[QUEUE] Found processed item: AI Mode: \(processedItem.isAIMode), Model: \(processedItem.model)")
    
    // Remove the processed item from queue
    state.transcriptionQueue.remove(at: processedItemIndex)
    print("[QUEUE] Removed item from queue. New queue size: \(state.transcriptionQueue.count)")
    print("[QUEUE] Remaining items in queue: \(state.transcriptionQueue.map { $0.id })")
    
    // Handle the result based on whether it was AI mode
    if processedItem.isAIMode && !result.isEmpty {
      print("[QUEUE] Processing AI mode result - starting AI generation")
      state.isGeneratingAI = true
      let model = state.hexSettings.selectedOllamaModel
      let systemPrompt = state.hexSettings.ollamaSystemPrompt
      
      // Create a defensive copy of the result to prevent corruption
      let resultCopy = String(result)
      
      print("[QUEUE] Preparing to continue processing queue (AI mode)...")
      let continueProcessing: Effect<Action> = .send(.startProcessingQueue)
      let aiGeneration = Effect.run { send in
        do {
          print("[QUEUE] Generating AI response with model: \(model)")
          // Use the copy instead of the original
          let response = try await ollama.generate(resultCopy, model, systemPrompt)
          print("[QUEUE] AI response received: '\(response)'")
          await send(Action.aiResponseReceived(response))
        } catch {
          print("[QUEUE] AI generation error: \(error)")
          await send(Action.aiGenerationError(error))
        }
      }
      
      return .merge(continueProcessing, aiGeneration)
    } else if !result.isEmpty {
      print("[QUEUE] Processing normal transcription mode - preparing to paste text")
      print("[QUEUE] Result integrity check - length: \(result.count), first 50 chars: '\(String(result.prefix(50)))'")
      print("[QUEUE] Result bytes: \(Array(result.utf8).prefix(20))")
      let duration = processedItem.startTime.timeIntervalSinceNow * -1
      
      // Validate result before proceeding
      let isValidText = !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let hasUnusualCharacters = result.contains { char in
        !char.isLetter && !char.isNumber && !char.isWhitespace && !char.isPunctuation
      }
      
      print("[QUEUE] Text validation - isValid: \(isValidText), hasUnusualChars: \(hasUnusualCharacters)")
      
      // Create a defensive copy of the result to prevent corruption
      let resultCopy = String(result)
      
      print("[QUEUE] Preparing to continue processing queue (normal mode)...")
      let continueProcessing: Effect<Action> = .send(.startProcessingQueue)
      let finalizeEffect = finalizeQueuedTranscript(
        result: resultCopy,
        duration: duration,
        audioURL: processedItem.audioURL,
        transcriptionHistory: state.$transcriptionHistory,
        wasAddedToActiveQueue: processedItem.wasAddedToActiveQueue
      )
      
      print("[QUEUE] Dispatching finalize effect and continue processing")
      return .merge(continueProcessing, finalizeEffect)
    } else {
      print("[QUEUE] Empty result - cleaning up and continuing")
      let cleanupEffect: Effect<Action> = .run { _ in
        do {
          try FileManager.default.removeItem(at: processedItem.audioURL)
          print("[QUEUE] Successfully cleaned up audio file: \(processedItem.audioURL.lastPathComponent)")
        } catch {
          print("[QUEUE] Failed to clean up audio file: \(error)")
        }
      }
      return .merge(cleanupEffect, .send(.startProcessingQueue))
    }
  }
  
  func handleQueueTranscriptionError(
    _ state: inout State,
    id: UUID,
    error: Error
  ) -> Effect<Action> {
    print("[QUEUE] handleQueueTranscriptionError for item ID: \(id), error: \(error)")
    print("[QUEUE] Current queue size before removal: \(state.transcriptionQueue.count)")
    
    // Find and remove the failed item from queue
    let failedItem = state.transcriptionQueue.first { $0.id == id }
    state.transcriptionQueue.removeAll { $0.id == id }
    
    print("[QUEUE] Queue size after removal: \(state.transcriptionQueue.count)")
    
    // Clean up the temporary audio file if we found the item
    let cleanupEffect: Effect<Action> = failedItem.map { item in
      Effect<Action>.run { _ in
        do {
          try FileManager.default.removeItem(at: item.audioURL)
          print("[QUEUE] Successfully cleaned up failed audio file: \(item.audioURL.lastPathComponent)")
        } catch {
          print("[QUEUE] Failed to clean up audio file: \(error)")
        }
      }
    } ?? .none
    
    // Show error and continue processing
    state.error = error.localizedDescription
    
    print("[QUEUE] Continuing queue processing after error")
    
    return .merge(
      cleanupEffect,
      .run { _ in
        await soundEffect.play(.cancel)
      },
      .send(.startProcessingQueue)
    )
  }
}

// MARK: - Cancel Handler

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State, playSound: Bool) -> Effect<Action> {
    state.isTranscribing = false
    state.isRecording = false
    state.isPrewarming = false
    state.isAIMode = false
    state.isGeneratingAI = false
    state.isProcessingQueue = false
    
    // Clear the transcription queue and clean up audio files
    let audioURLsToClean = state.transcriptionQueue.map(\.audioURL)
    state.transcriptionQueue.removeAll()

    // Allow system to sleep again if it was prevented
    reallowSystemSleep(&state)

    return .merge(
      .cancel(id: CancelID.transcription),
      .cancel(id: CancelID.queueProcessing),
      .cancel(id: CancelID.delayedRecord),
      .run { _ in
        // Stop recording to properly release the microphone
        _ = await recording.stopRecording()
        
        // Clean up queued audio files
        for url in audioURLsToClean {
          try? FileManager.default.removeItem(at: url)
        }
        
        if playSound {
          await soundEffect.play(.cancel)
        }
      }
    )
  }
}

// MARK: - System Sleep Prevention

private extension TranscriptionFeature {
  func preventSystemSleep(_ state: inout State) {
    // Prevent system sleep during recording
    let reasonForActivity = "Hex Voice Recording" as CFString
    var assertionID: IOPMAssertionID = 0
    let success = IOPMAssertionCreateWithName(
      kIOPMAssertionTypeNoDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reasonForActivity,
      &assertionID
    )
    if success == kIOReturnSuccess {
      state.assertionID = assertionID
    }
  }

  func reallowSystemSleep(_ state: inout State) {
    if let assertionID = state.assertionID {
      let releaseSuccess = IOPMAssertionRelease(assertionID)
      if releaseSuccess == kIOReturnSuccess {
        state.assertionID = nil
      }
    }
  }
}

// MARK: - View

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  var recordingStatus: TranscriptionIndicatorView.Status {
    if store.isRecording {
      return store.isAIMode ? .aiRecording : .recording
    } else {
      return .hidden
    }
  }
  
  var transcribingStatus: TranscriptionIndicatorView.Status {
    let status: TranscriptionIndicatorView.Status
    
    if store.needsModel {
      status = .needsModel
    } else if store.isTranscribing || store.isGeneratingAI {
      // For queue processing, we need to determine AI mode from the first queued item
      let isAIMode = store.transcriptionQueue.first?.isAIMode ?? store.isAIMode
      status = isAIMode ? .aiTranscribing : .transcribing
    } else if store.isPrewarming {
      status = .prewarming
    } else if store.aiResponse != nil {
      status = .aiResponse
    } else {
      status = .hidden
    }
    
    // Log significant state transitions
    if status != .hidden {
      print("[INDICATOR] Transcribing status: \(status)")
      print("[INDICATOR]   - isTranscribing: \(store.isTranscribing)")
      print("[INDICATOR]   - isProcessingQueue: \(store.isProcessingQueue)")
      print("[INDICATOR]   - isGeneratingAI: \(store.isGeneratingAI)")
      print("[INDICATOR]   - queue size: \(store.transcriptionQueue.count)")
    }
    
    return status
  }
  
  var shouldShowBoth: Bool {
    recordingStatus != .hidden && transcribingStatus != .hidden
  }

  var body: some View {
    HStack(spacing: 8) {
      // Recording orb (if recording)
      if recordingStatus != .hidden {
        TranscriptionIndicatorView(
          status: recordingStatus,
          meter: store.meter,
          aiResponse: nil,
          onDismissAI: {}
        )
      }
      
      // Transcribing orb (if transcribing/processing)
      if transcribingStatus != .hidden {
        TranscriptionIndicatorView(
          status: transcribingStatus,
          meter: store.meter,
          aiResponse: store.aiResponse,
          onDismissAI: {
            store.send(.clearAIResponse)
          }
        )
      }
    }
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}
