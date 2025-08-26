//
//  HexCapsuleView.swift
//  Hex
//
//  Created by Kit Langton on 1/25/25.

import Inject
import Pow
import SwiftUI

struct AIResponseModal: View {
  let response: String
  let onDismiss: () -> Void
  
  @State private var isHovered = false
  @State private var dismissTask: Task<Void, Never>?
  
  // Calculate dismiss delay based on text length (min 3 seconds, max 10 seconds)
  var dismissDelay: TimeInterval {
    let wordsPerMinute = 200.0
    let words = Double(response.split(separator: " ").count)
    let readingTime = (words / wordsPerMinute) * 60
    return min(max(readingTime + 2, 3), 10)
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(response)
        .font(.system(size: 14))
        .foregroundColor(.black)
        .lineSpacing(4)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 200, idealWidth: 300, maxWidth: 500, alignment: .leading)
      
      HStack {
        Spacer()
        Button("Dismiss") {
          dismissTask?.cancel()
          onDismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.white.opacity(0.95))
        .shadow(radius: 10)
    )
    .fixedSize(horizontal: true, vertical: true)
    .onHover { hovering in
      isHovered = hovering
      if hovering {
        dismissTask?.cancel()
        dismissTask = nil
      }
    }
    .onTapGesture {
      // Prevent dismissal on modal click
    }
    .background(
      Color.clear
        .contentShape(Rectangle())
        .frame(width: 2000, height: 2000)
        .onTapGesture {
          dismissTask?.cancel()
          onDismiss()
        }
    )
    .onAppear {
      // Start auto-dismiss timer
      dismissTask = Task {
        try? await Task.sleep(for: .seconds(dismissDelay))
        if !isHovered && !Task.isCancelled {
          onDismiss()
        }
      }
    }
    .onDisappear {
      dismissTask?.cancel()
    }
  }
}

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject
  
  enum Status {
    case hidden
    case optionKeyPressed
    case recording
    case aiRecording
    case transcribing
    case aiTranscribing
    case prewarming
    case aiResponse
  }

  var status: Status
  var meter: Meter
  var aiResponse: String?
  var onDismissAI: () -> Void = {}

  let transcribeBaseColor: Color = .blue
  let aiBaseColor: Color = .purple

  private var backgroundColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.black
    case .recording: return .red.mix(with: .black, by: 0.5).mix(with: .red, by: meter.averagePower * 3)
    case .aiRecording: return aiBaseColor.mix(with: .black, by: 0.5).mix(with: aiBaseColor, by: meter.averagePower * 3)
    case .transcribing: return transcribeBaseColor.mix(with: .black, by: 0.5)
    case .aiTranscribing: return aiBaseColor.mix(with: .black, by: 0.5)
    case .prewarming: return transcribeBaseColor.mix(with: .black, by: 0.5)
    case .aiResponse: return Color.white.opacity(0.95)
    }
  }

  private var strokeColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.black
    case .recording: return Color.red.mix(with: .white, by: 0.1).opacity(0.6)
    case .aiRecording: return aiBaseColor.mix(with: .white, by: 0.1).opacity(0.6)
    case .transcribing: return transcribeBaseColor.mix(with: .white, by: 0.1).opacity(0.6)
    case .aiTranscribing: return aiBaseColor.mix(with: .white, by: 0.1).opacity(0.6)
    case .prewarming: return transcribeBaseColor.mix(with: .white, by: 0.1).opacity(0.6)
    case .aiResponse: return Color.gray.opacity(0.3)
    }
  }

  private var innerShadowColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.clear
    case .recording: return Color.red
    case .aiRecording: return aiBaseColor
    case .transcribing: return transcribeBaseColor
    case .aiTranscribing: return aiBaseColor
    case .prewarming: return transcribeBaseColor
    case .aiResponse: return Color.gray.opacity(0.2)
    }
  }

  private let cornerRadius: CGFloat = 8
  private let baseWidth: CGFloat = 16
  private let expandedWidth: CGFloat = 56

  var isHidden: Bool {
    status == .hidden
  }

  @State var transcribeEffect = 0

  var body: some View {
    let averagePower = min(1, meter.averagePower * 3)
    let peakPower = min(1, meter.peakPower * 3)
    ZStack {
      Capsule()
        .fill(backgroundColor.shadow(.inner(color: innerShadowColor, radius: 4)))
        .overlay {
          Capsule()
            .stroke(strokeColor, lineWidth: 1)
            .blendMode(.screen)
        }
        .overlay(alignment: .center) {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill((status == .recording ? Color.red : status == .aiRecording ? aiBaseColor : Color.clear).opacity((status == .recording || status == .aiRecording) ? (averagePower < 0.1 ? averagePower / 0.1 : 1) : 0))
            .blur(radius: 2)
            .blendMode(.screen)
            .padding(6)
        }
        .overlay(alignment: .center) {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(status == .recording ? (averagePower < 0.1 ? averagePower / 0.1 : 0.5) : 0))
            .blur(radius: 1)
            .blendMode(.screen)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(7)
        }
        .overlay(alignment: .center) {
          GeometryReader { proxy in
            RoundedRectangle(cornerRadius: cornerRadius)
              .fill(Color.red.opacity(status == .recording ? (peakPower < 0.1 ? (peakPower / 0.1) * 0.5 : 0.5) : 0))
              .frame(width: max(proxy.size.width * (peakPower + 0.6), 0), height: proxy.size.height, alignment: .center)
              .frame(maxWidth: .infinity, alignment: .center)
              .blur(radius: 4)
              .blendMode(.screen)
          }.padding(6)
        }
        .cornerRadius(cornerRadius)
        .shadow(
          color: status == .recording ? .red.opacity(averagePower) : 
                 status == .aiRecording ? aiBaseColor.opacity(averagePower) : .red.opacity(0),
          radius: 4
        )
        .shadow(
          color: status == .recording ? .red.opacity(averagePower * 0.5) : 
                 status == .aiRecording ? aiBaseColor.opacity(averagePower * 0.5) : .red.opacity(0),
          radius: 8
        )
        .animation(.interactiveSpring(), value: meter)
        .frame(
          width: (status == .recording || status == .aiRecording) ? expandedWidth : baseWidth,
          height: baseWidth
        )
        .opacity(status == .hidden ? 0 : 1)
        .scaleEffect(status == .hidden ? 0.0 : 1)
        .blur(radius: status == .hidden ? 4 : 0)
        .animation(.bouncy(duration: 0.3), value: status)
        .changeEffect(.glow(color: .red.opacity(0.5), radius: 8), value: status)
        .changeEffect(.shine(angle: .degrees(0), duration: 0.6), value: transcribeEffect)
        .compositingGroup()
        .task(id: status == .transcribing || status == .aiTranscribing) {
          while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
            transcribeEffect += 1
            try? await Task.sleep(for: .seconds(0.25))
          }
        }
      
      // Show tooltip when prewarming
      if status == .prewarming {
        VStack(spacing: 4) {
          Text("Model prewarming...")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.8))
            )
        }
        .offset(y: -24)
        .transition(.opacity)
        .zIndex(2)
      }
      
      // Show AI response modal
      if status == .aiResponse, let response = aiResponse {
        AIResponseModal(
          response: response,
          onDismiss: onDismissAI
        )
        .offset(y: 40)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .zIndex(3)
      }
    }
    .enableInjection()
  }
}

#Preview("HEX") {
  VStack(spacing: 8) {
    TranscriptionIndicatorView(status: .hidden, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .optionKeyPressed, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.5, peakPower: 0.5))
    TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0))
    TranscriptionIndicatorView(status: .prewarming, meter: .init(averagePower: 0, peakPower: 0))
  }
  .padding(40)
}
