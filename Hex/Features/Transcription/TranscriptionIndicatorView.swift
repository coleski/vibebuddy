//
//  TranscriptionIndicatorView.swift
//  Hex
//
//  Created by Kit Langton on 1/10/25.
//
import Inject
import Pow
import SwiftData
import SwiftUI

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
    case needsModel
    case aiResponse
  }

  var status: Status
  var meter: Meter
  var aiResponse: String?
  var onDismissAI: () -> Void = {}
  var readingSpeed: Double = 250.0 // Default to 250 WPM if not provided

  let transcribeBaseColor: Color = .red
  let aiBaseColor: Color = .purple

  private var backgroundColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.white
    case .recording: return Color.white
    case .aiRecording: return Color.white
    case .transcribing: return Color.white
    case .aiTranscribing: return Color.white
    case .prewarming: return Color.white
    case .needsModel: return Color.white
    case .aiResponse: return Color.white.opacity(0.95)
    }
  }

  private var strokeColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.black.opacity(0.8)
    case .recording: return transcribeBaseColor.opacity(0.9)
    case .aiRecording: return aiBaseColor.opacity(0.9)
    case .transcribing: return transcribeBaseColor.opacity(0.9)
    case .aiTranscribing: return aiBaseColor.opacity(0.9)
    case .prewarming: return transcribeBaseColor.opacity(0.9)
    case .needsModel: return Color.black.opacity(0.5)
    case .aiResponse: return Color.black.opacity(0.5)
    }
  }

  private var innerShadowColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.black.opacity(0.1)
    case .recording: return Color.red.opacity(0.2)
    case .aiRecording: return aiBaseColor.opacity(0.2)
    case .transcribing: return transcribeBaseColor.opacity(0.2)
    case .aiTranscribing: return aiBaseColor.opacity(0.2)
    case .prewarming: return transcribeBaseColor.opacity(0.2)
    case .needsModel: return Color.gray.opacity(0.1)
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
  
  // Helper computed properties to simplify complex expressions
  private var isRecordingOrAIRecording: Bool {
    status == .recording || status == .aiRecording
  }
  
  private var recordingFillColor: Color {
    if status == .recording {
      return Color.red
    } else if status == .aiRecording {
      return aiBaseColor
    } else {
      return Color.clear
    }
  }
  
  private var recordingFillOpacity: Double {
    guard isRecordingOrAIRecording else { return 0 }
    let averagePower = min(1, meter.averagePower * 3)
    return averagePower < 0.1 ? averagePower / 0.1 : 1
  }
  
  private var whiteFillOpacity: Double {
    guard isRecordingOrAIRecording else { return 0 }
    let averagePower = min(1, meter.averagePower * 3)
    return averagePower < 0.1 ? averagePower / 0.1 : 0.5
  }
  
  private var peakFillOpacity: Double {
    guard isRecordingOrAIRecording else { return 0 }
    let peakPower = min(1, meter.peakPower * 3)
    return peakPower < 0.1 ? (peakPower / 0.1) * 0.5 : 0.5
  }
  
  private var shouldHideOrb: Bool {
    status == .hidden || status == .aiResponse || status == .needsModel
  }

  @ViewBuilder
  private var smileyFace: some View {
    if !shouldHideOrb && status != .optionKeyPressed {
      GeometryReader { geometry in
        let containerWidth = geometry.size.width
        let containerHeight = geometry.size.height
        let center = CGPoint(x: containerWidth / 2, y: containerHeight / 2)
        
        // Keep eye size constant, only vary spacing
        let eyeSize: CGFloat = 2
        let eyeSpacing: CGFloat = isRecordingOrAIRecording ? containerWidth * 0.35 : 3
        
        ZStack {
          // Eyes
          HStack(spacing: eyeSpacing) {
            Circle()
              .fill(Color.black)
              .frame(width: eyeSize, height: eyeSize)
            Circle()
              .fill(Color.black)
              .frame(width: eyeSize, height: eyeSize)
          }
          .position(x: center.x, y: center.y - 2)
          
          // Smile - spans between the eyes
          Path { path in
            let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
            let smileWidth = eyeTotalWidth * 0.75
            let height: CGFloat = isRecordingOrAIRecording ? containerHeight * 0.15 : 2
            let yOffset = center.y + (isRecordingOrAIRecording ? containerHeight * 0.15 : 3)
            
            path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
            path.addQuadCurve(
              to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
              control: CGPoint(x: center.x, y: yOffset + height)
            )
          }
          .stroke(Color.black, style: StrokeStyle(lineWidth: isRecordingOrAIRecording ? 2 : 1.5, lineCap: .round))
        }
      }
      .opacity((status == .transcribing || status == .aiTranscribing) ? 0.3 : 0.9)
    }
  }
  
  @ViewBuilder
  private var orbView: some View {
    let averagePower = min(1, meter.averagePower * 3)
    
    Capsule()
      .fill(backgroundColor.shadow(.inner(color: innerShadowColor, radius: 4)))
      .overlay {
        Capsule()
          .stroke(strokeColor, lineWidth: 2)
          .blendMode(.normal)
      }
      .overlay(alignment: .center) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(recordingFillColor.opacity(recordingFillOpacity))
          .blur(radius: 2)
          .blendMode(.screen)
          .padding(6)
      }
      .overlay(alignment: .center) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color.white.opacity(whiteFillOpacity))
          .blur(radius: 1)
          .blendMode(.screen)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(7)
      }
      .overlay {
        smileyFace
      }
      .cornerRadius(cornerRadius)
      .shadow(color: shadowColor1, radius: 6)
      .shadow(color: shadowColor2, radius: 12)
      .animation(.interactiveSpring(), value: meter)
      .frame(
        width: isRecordingOrAIRecording ? expandedWidth : baseWidth,
        height: baseWidth
      )
      .opacity(shouldHideOrb ? 0 : 1)
      .scaleEffect(shouldHideOrb ? 0.0 : 1)
      .blur(radius: shouldHideOrb ? 4 : 0)
      .animation(.bouncy(duration: 0.3), value: status)
      .changeEffect(.glow(color: glowColor, radius: 10), value: status)
      .changeEffect(.shine(angle: .degrees(0), duration: 0.6), value: transcribeEffect)
      .compositingGroup()
      .task(id: status == .transcribing || status == .aiTranscribing) {
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          transcribeEffect += 1
          try? await Task.sleep(for: .seconds(0.25))
        }
      }
  }
  
  private var shadowColor1: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .red.opacity(averagePower * 0.8)
    case .aiRecording: return aiBaseColor.opacity(averagePower * 0.8)
    case .transcribing: return transcribeBaseColor.opacity(0.6)
    case .aiTranscribing: return aiBaseColor.opacity(0.6)
    default: return .clear
    }
  }
  
  private var shadowColor2: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .orange.opacity(averagePower * 0.6)
    case .aiRecording: return .yellow.opacity(averagePower * 0.6)
    case .transcribing: return transcribeBaseColor.opacity(0.4)
    case .aiTranscribing: return aiBaseColor.opacity(0.4)
    default: return .clear
    }
  }
  
  private var glowColor: Color {
    switch status {
    case .recording: return .red.opacity(0.7)
    case .aiRecording: return aiBaseColor.opacity(0.7)
    case .transcribing: return transcribeBaseColor.opacity(0.7)
    case .aiTranscribing: return aiBaseColor.opacity(0.7)
    default: return .clear
    }
  }
  
  var body: some View {
    ZStack {
      // Show "Needs model" text in place of the orb
      if status == .needsModel {
        Text("Needs model")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.black)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.white)
              .overlay(
                RoundedRectangle(cornerRadius: 4)
                  .stroke(Color.gray.opacity(0.3), lineWidth: 1)
              )
          )
          .transition(.opacity.combined(with: .scale))
      } else {
        orbView
        
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
      }
      
    }
    .overlay(alignment: .top) {
      // Show AI response modal as overlay (aligns top edge with indicator)
      if status == .aiResponse, let response = aiResponse {
        AIResponseModalUIKit(
          response: response,
          onDismiss: onDismissAI,
          readingSpeed: readingSpeed
        )
        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
      }
    }
    .enableInjection()
  }
}

// Preview disabled due to Meter type resolution issue
// To test the view, run the full app or use TranscriptionFeature