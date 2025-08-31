//
//  AIProcessingFeature.swift
//  Hex
//
//  Created on 1/28/25.
//

import ComposableArchitecture
import Foundation

@Reducer
struct AIProcessingFeature {
  @ObservableState
  struct State: Equatable {
    var isProcessing: Bool = false
    var error: String?
    @Shared(.hexSettings) var hexSettings: HexSettings
  }
  
  enum Action {
    case processTranscription(String, completion: (String) -> Void)
    case processingCompleted(String)
    case processingFailed(Error)
  }
  
  @Dependency(\.ollama) var ollama
  
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .processTranscription(text, completion):
        guard state.hexSettings.enableAIProcessing else {
          // If AI processing is disabled, return original text
          completion(text)
          return .none
        }
        
        state.isProcessing = true
        state.error = nil
        
        let model = state.hexSettings.selectedOllamaModel
        let userPrompt = state.hexSettings.aiProcessingPrompt
        
        // Create system prompt that wraps user instructions
        let systemPrompt = AIProcessingFeature.createFormattingSystemPrompt(userPrompt: userPrompt)
        
        return .run { send in
          do {
            // Generate the formatted text using AI
            let formattedText = try await ollama.generate(text, model, systemPrompt)
            await send(.processingCompleted(formattedText))
            completion(formattedText)
          } catch {
            // If AI processing fails, fall back to original text
            print("AI processing failed: \(error), using original text")
            await send(.processingFailed(error))
            completion(text)
          }
        }
        
      case let .processingCompleted(result):
        state.isProcessing = false
        return .none
        
      case let .processingFailed(error):
        state.isProcessing = false
        state.error = error.localizedDescription
        return .none
      }
    }
  }
}

// MARK: - Helper Functions

extension AIProcessingFeature {
  /// Creates a system prompt that instructs the AI to format text according to user instructions
  static func createFormattingSystemPrompt(userPrompt: String) -> String {
    """
    You are a text formatter. Apply the following formatting instructions to the input text.
    
    CRITICAL RULES:
    - Output ONLY the reformatted text
    - Do NOT add any introduction, explanation, or commentary
    - Do NOT add phrases like "Here's the formatted text:" or "I hope that helps"
    - Do NOT add any closing remarks or signatures
    - Start your response with the first word of the formatted text
    - End your response with the last word of the formatted text
    
    Formatting instructions: \(userPrompt)
    
    Input text to format:
    """
  }
  
  /// Processes text with AI if enabled, otherwise returns original text
  static func processText(
    _ text: String,
    settings: HexSettings,
    ollama: OllamaClient
  ) async -> String {
    guard settings.enableAIProcessing else {
      print("[AIProcessing] AI processing is disabled, returning original text")
      return text
    }
    
    print("[AIProcessing] AI processing enabled, formatting text with prompt: \(settings.aiProcessingPrompt)")
    let systemPrompt = createFormattingSystemPrompt(userPrompt: settings.aiProcessingPrompt)
    
    do {
      let formattedText = try await ollama.generate(
        text,
        settings.selectedOllamaModel,
        systemPrompt
      )
      print("[AIProcessing] Successfully formatted text")
      return formattedText
    } catch {
      print("[AIProcessing] AI processing failed: \(error), using original text")
      return text
    }
  }
}