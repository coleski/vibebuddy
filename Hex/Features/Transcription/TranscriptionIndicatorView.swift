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
    case .optionKeyPressed: return Color.black.opacity(0.8)
    case .recording: return transcribeBaseColor
    case .aiRecording: return aiBaseColor
    case .transcribing: return Color.white.opacity(0.4)  // Glass-like transparency
    case .aiTranscribing: return Color.white.opacity(0.4)
    case .prewarming: return transcribeBaseColor
    case .needsModel: return Color.black.opacity(0.5)
    case .aiResponse: return Color.black.opacity(0.5)
    }
  }

  private var strokeColor: Color {
    switch status {
    case .hidden: return Color.clear
    case .optionKeyPressed: return Color.black.opacity(0.8)
    case .recording: return transcribeBaseColor
    case .aiRecording: return aiBaseColor
    case .transcribing: return Color.clear  // No border
    case .aiTranscribing: return Color.clear  // No border
    case .prewarming: return transcribeBaseColor
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
  @State var ellipsisFrame = 0
  @State var rainbowHue: Double = 0
  
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
        
        // Calculate eye color based on volume when recording
        let averagePower = min(1, meter.averagePower * 5)  // Even more sensitive
        let faceOpacity: Double = {
          if isRecordingOrAIRecording {
            // Direct mapping - instant response to volume
            // Nearly invisible at 0, fully visible at very low volumes
            if averagePower < 0.01 {
              return 0  // Completely invisible when truly silent
            } else {
              return min(1.0, averagePower * 5)  // Aggressive scaling, reaches full at just 0.2 power
            }
          } else {
            return 1.0
          }
        }()
        
        let eyeColor: Color = {
          if status == .recording || status == .aiRecording {
            // White eyes for recording modes
            return Color.white
          } else if status == .transcribing || status == .aiTranscribing {
            // Rainbow gradient for transcribing
            return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.9)
          } else if status == .prewarming {
            return Color.white.opacity(0.8)
          } else {
            return Color.black
          }
        }()
        
        ZStack {
          // Eyes with volume-based glow
          HStack(spacing: eyeSpacing) {
            Circle()
              .fill(eyeColor)
              .frame(width: eyeSize, height: eyeSize)
              .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : .clear, 
                      radius: faceOpacity * 6)
            Circle()
              .fill(eyeColor)
              .frame(width: eyeSize, height: eyeSize)
              .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : .clear, 
                      radius: faceOpacity * 6)
          }
          .position(x: center.x, y: center.y - 2)
          
          // Smile for all states
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
          .stroke(eyeColor, style: StrokeStyle(lineWidth: isRecordingOrAIRecording ? 2 : 1.5, lineCap: .round))
          .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : .clear,
                  radius: faceOpacity * 5)
        }
        .opacity(faceOpacity)
      }
      .opacity((status == .transcribing || status == .aiTranscribing) ? 1.0 : 1.0)
    }
  }
  
  @ViewBuilder
  private var orbView: some View {
    let averagePower = min(1, meter.averagePower * 3)
    
    ZStack {
      // Glass effect for transcribing states
      if status == .transcribing || status == .aiTranscribing {
        Capsule()
          .fill(.ultraThinMaterial)
          .overlay {
            Capsule()
              .fill(Color.white.opacity(0.2))
          }
      } else {
        // Regular fill for other states
        Capsule()
          .fill(backgroundColor.shadow(.inner(color: innerShadowColor, radius: 4)))
      }
      
      Capsule()
        .stroke(strokeColor, lineWidth: 2)
        .blendMode(.normal)
    }
    .overlay {
      smileyFace
    }
      .cornerRadius(cornerRadius)
      .shadow(color: shadowColor1, radius: 6)
      .shadow(color: shadowColor2, radius: 12)
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
      .task(id: status == .transcribing || status == .aiTranscribing) {
        ellipsisFrame = 0
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          ellipsisFrame = (ellipsisFrame + 1) % 3
          try? await Task.sleep(for: .milliseconds(300))
        }
      }
      .task(id: status == .transcribing || status == .aiTranscribing) {
        rainbowHue = 0
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          withAnimation(.linear(duration: 0.1)) {
            rainbowHue = (rainbowHue + 0.05).truncatingRemainder(dividingBy: 1.0)
          }
          try? await Task.sleep(for: .milliseconds(50))
        }
      }
  }
  
  private var shadowColor1: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .red.opacity(averagePower * 0.8)
    case .aiRecording: return aiBaseColor.opacity(averagePower * 0.8)
    case .transcribing: return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.9).opacity(0.6)
    case .aiTranscribing: return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.9).opacity(0.6)
    default: return .clear
    }
  }
  
  private var shadowColor2: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .orange.opacity(averagePower * 0.6)
    case .aiRecording: return .yellow.opacity(averagePower * 0.6)
    case .transcribing: return Color(hue: (rainbowHue + 0.2).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 0.9).opacity(0.4)
    case .aiTranscribing: return Color(hue: (rainbowHue + 0.2).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 0.9).opacity(0.4)
    default: return .clear
    }
  }
  
  private var glowColor: Color {
    switch status {
    case .recording: return .red.opacity(0.7)
    case .aiRecording: return aiBaseColor.opacity(0.7)
    case .transcribing: return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.9).opacity(0.8)
    case .aiTranscribing: return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.9).opacity(0.8)
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