//
//  AIProcessingSettingsView.swift
//  Hex
//
//  Created on 1/28/25.
//

import SwiftUI
import ComposableArchitecture

struct AIProcessingSettingsView: View {
  @Binding var enableAIProcessing: Bool
  @Binding var aiProcessingPrompt: String
  
  var body: some View {
    Section {
      Label {
        Toggle("Process Transcriptions with AI", isOn: $enableAIProcessing)
        Text("Apply AI formatting to all transcriptions before pasting")
          .font(.caption)
          .foregroundColor(.secondary)
      } icon: {
        Image(systemName: "wand.and.stars")
      }
      
      if enableAIProcessing {
        VStack(alignment: .leading, spacing: 8) {
          Text("Formatting Instructions")
            .font(.caption)
            .foregroundColor(.secondary)
          
          TextEditor(text: $aiProcessingPrompt)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 60, maxHeight: 120)
            .padding(4)
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.top, 4)
        
        Text("The AI will format your transcriptions according to these instructions before pasting.")
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.top, 2)
      }
    } header: {
      Text("AI Processing")
    } footer: {
      if enableAIProcessing {
        Text("Examples: 'Add proper punctuation and capitalization', 'Format as bullet points', 'Convert to title case'")
          .font(.footnote)
          .foregroundColor(.secondary)
      }
    }
  }
}