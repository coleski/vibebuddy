//
//  AIAssistantSettingsView.swift
//  Hex
//
//  Created on 1/28/25.
//

import SwiftUI
import ComposableArchitecture
import Sauce

struct AIAssistantSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  
  var body: some View {
    Section {
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
    } header: {
      Text("AI Assistant")
    } footer: {
      Text("Hold the AI modifier key while recording to send transcription to Ollama for processing. The response will auto-dismiss based on reading speed.")
        .font(.footnote)
        .foregroundColor(.secondary)
    }
  }
}