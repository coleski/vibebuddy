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
  
  enum FaceExpression: CaseIterable {
    case surprise      // :O - circle mouth
    case smile         // :) - normal smile
    case thinking      // ... - animated ellipsis
    case skeptical     // -_- - squinty eyes, horizontal mouth (rare)
    
    static func random() -> FaceExpression {
      // Make skeptical rare (5% chance)
      let randomValue = Int.random(in: 0..<100)
      if randomValue < 5 {
        return .skeptical
      } else {
        // Equal chance for the other three
        let otherFaces: [FaceExpression] = [.surprise, .smile, .thinking]
        return otherFaces.randomElement()!
      }
    }
  }
  
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
    case .transcribing: return Color.white  // Solid white
    case .aiTranscribing: return Color.white
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
  @State var currentFaceExpression: FaceExpression = .surprise
  @State var waveRotation: Double = 0
  
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
        let eyeSpacing: CGFloat = containerWidth * 0.35
        
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
            // Darker, more saturated rainbow eyes for transcribing
            return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.6).opacity(0.85)
          } else if status == .prewarming {
            return Color.white.opacity(0.8)
          } else {
            return Color.black
          }
        }()
        
        let mouthColor: Color = {
          if status == .recording || status == .aiRecording {
            // White mouth for recording modes
            return Color.white
          } else if status == .transcribing || status == .aiTranscribing {
            // Darker, more saturated rainbow mouth for transcribing modes
            return Color(hue: rainbowHue, saturation: 0.9, brightness: 0.6).opacity(0.85)
          } else {
            // Black mouth for all other states
            return Color.black
          }
        }()
        
        ZStack {
          // Eyes with volume-based glow
          if (status == .transcribing || status == .aiTranscribing) && currentFaceExpression == .skeptical {
            // Squinty eyes for skeptical face -_-
            HStack(spacing: eyeSpacing) {
              Rectangle()
                .fill(eyeColor)
                .frame(width: eyeSize * 2, height: 0.5)
              Rectangle()
                .fill(eyeColor)
                .frame(width: eyeSize * 2, height: 0.5)
            }
            .position(x: center.x, y: center.y - 2)
          } else {
            // Normal circular eyes
            HStack(spacing: eyeSpacing) {
              Circle()
                .fill(eyeColor)
                .frame(width: eyeSize, height: eyeSize)
                .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : (status == .transcribing || status == .aiTranscribing) ? eyeColor.opacity(0.4) : .clear, 
                        radius: (status == .transcribing || status == .aiTranscribing) ? 5 : faceOpacity * 6)
              Circle()
                .fill(eyeColor)
                .frame(width: eyeSize, height: eyeSize)
                .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : (status == .transcribing || status == .aiTranscribing) ? eyeColor.opacity(0.4) : .clear, 
                        radius: (status == .transcribing || status == .aiTranscribing) ? 5 : faceOpacity * 6)
            }
            .position(x: center.x, y: center.y - 2)
          }
          
          // Mouth - different expressions for transcribing, smile for other states
          if status == .transcribing || status == .aiTranscribing {
            // Show different face expressions based on random selection
            switch currentFaceExpression {
            case .surprise:
              // Circle mouth :O with glow
              Circle()
                .stroke(mouthColor, lineWidth: 1.5)
                .frame(width: 4, height: 4)
                .shadow(color: mouthColor.opacity(0.5), radius: 5)
                .shadow(color: mouthColor.opacity(0.3), radius: 8)
                .position(x: center.x, y: center.y + containerHeight * 0.15)
              
            case .smile:
              // Normal smile :)
              Path { path in
                let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
                let smileWidth = eyeTotalWidth * 0.75
                let height: CGFloat = containerHeight * 0.15
                let yOffset = center.y + containerHeight * 0.15
                
                path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
                path.addQuadCurve(
                  to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
                  control: CGPoint(x: center.x, y: yOffset + height)
                )
              }
              .stroke(mouthColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
              
            case .thinking:
              // Animated ellipsis ... with glow
              HStack(spacing: 2) {
                ForEach(0..<3) { index in
                  Circle()
                    .fill(mouthColor)
                    .frame(width: 1.5, height: 1.5)
                    .opacity(index <= ellipsisFrame ? 1.0 : 0.3)
                    .shadow(color: mouthColor.opacity(index <= ellipsisFrame ? 0.4 : 0), radius: 3)
                }
              }
              .position(x: center.x, y: center.y + containerHeight * 0.15)
              
            case .skeptical:
              // Horizontal line mouth with squinty eyes handled separately
              Path { path in
                let mouthWidth: CGFloat = eyeSpacing * 0.5
                let yOffset = center.y + containerHeight * 0.15
                
                path.move(to: CGPoint(x: center.x - mouthWidth/2, y: yOffset))
                path.addLine(to: CGPoint(x: center.x + mouthWidth/2, y: yOffset))
              }
              .stroke(mouthColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
          } else {
            // Smile for other states
            Path { path in
              let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
              let smileWidth = eyeTotalWidth * 0.75
              let height: CGFloat = containerHeight * 0.15
              let yOffset = center.y + containerHeight * 0.15
              
              path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
              path.addQuadCurve(
                to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
                control: CGPoint(x: center.x, y: yOffset + height)
              )
            }
            .stroke(mouthColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .shadow(color: isRecordingOrAIRecording ? Color.white.opacity(0.8) : .clear,
                    radius: faceOpacity * 5)
          }
        }
        .opacity(faceOpacity)
      }
      .opacity((status == .transcribing || status == .aiTranscribing) ? 1.0 : 1.0)
    }
  }
  
  @ViewBuilder
  private var orbView: some View {
    let averagePower = min(1, meter.averagePower * 3)
    
    Capsule()
      .fill(backgroundColor.shadow(.inner(color: innerShadowColor, radius: 4)))
      .overlay {
        // Rainbow wave border for transcribing states
        if status == .transcribing || status == .aiTranscribing {
          ZStack {
            // Multiple layers for tapered effect
            ForEach(0..<8) { layer in
              let progress = Double(layer) / 7.0
              let opacity = pow(1.0 - progress, 2.0) // Exponential fade
              let lineWidth = 3.0 * (1.0 - progress * 0.7) // Tapering width
              
              Capsule()
                .stroke(
                  AngularGradient(
                    gradient: Gradient(stops: [
                      .init(color: Color(hue: (rainbowHue + progress * 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(opacity), location: 0),
                      .init(color: Color(hue: (rainbowHue + 0.05 + progress * 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(opacity * 0.8), location: 0.05),
                      .init(color: Color(hue: (rainbowHue + 0.1 + progress * 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(opacity * 0.5), location: 0.15),
                      .init(color: Color(hue: (rainbowHue + 0.15 + progress * 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 1.0, brightness: 1.0).opacity(opacity * 0.2), location: 0.20),
                      .init(color: Color.clear, location: 0.25), // Fade complete at 25% of the circle
                      .init(color: Color.clear, location: 1.0)
                    ]),
                    center: .center,
                    startAngle: Angle(degrees: waveRotation - Double(layer) * 2),
                    endAngle: Angle(degrees: waveRotation + 360 - Double(layer) * 2)
                  ),
                  lineWidth: lineWidth
                )
                .blendMode(.plusLighter)
            }
          }
        } else {
          Capsule()
            .stroke(strokeColor, lineWidth: 2)
            .blendMode(.normal)
        }
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
      .animation(.easeInOut(duration: 0.15), value: isRecordingOrAIRecording)
    .changeEffect(.glow(color: glowColor, radius: 10), value: status)
    .changeEffect(.shine(angle: .degrees(0), duration: 0.6), value: transcribeEffect)
    .compositingGroup()
      .task(id: status == .transcribing || status == .aiTranscribing) {
        // Randomize face expression when entering transcribing state
        if status == .transcribing || status == .aiTranscribing {
          currentFaceExpression = FaceExpression.random()
        }
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          transcribeEffect += 1
          try? await Task.sleep(for: .seconds(0.25))
        }
      }
      .task(id: status == .transcribing || status == .aiTranscribing) {
        ellipsisFrame = 0
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          ellipsisFrame = (ellipsisFrame + 1) % 4  // Changed to 4 for better animation
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
      .task(id: status == .transcribing || status == .aiTranscribing) {
        waveRotation = 0
        while (status == .transcribing || status == .aiTranscribing), !Task.isCancelled {
          withAnimation(.linear(duration: 0.02)) {
            waveRotation = (waveRotation + 3).truncatingRemainder(dividingBy: 360)
          }
          try? await Task.sleep(for: .milliseconds(20))
        }
      }
  }
  
  private var shadowColor1: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .red.opacity(averagePower * 0.8)
    case .aiRecording: return aiBaseColor.opacity(averagePower * 0.8)
    case .transcribing: return Color(hue: rainbowHue, saturation: 1.0, brightness: 1.0).opacity(averagePower * 0.8)  // Rainbow glow with volume response
    case .aiTranscribing: return Color(hue: rainbowHue, saturation: 1.0, brightness: 1.0).opacity(averagePower * 0.8)  // Rainbow glow with volume response
    default: return .clear
    }
  }
  
  private var shadowColor2: Color {
    let averagePower = min(1, meter.averagePower * 3)
    switch status {
    case .recording: return .orange.opacity(averagePower * 0.6)
    case .aiRecording: return .yellow.opacity(averagePower * 0.6)
    case .transcribing: return Color(hue: (rainbowHue + 0.15).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 1.0).opacity(averagePower * 0.6)  // Secondary rainbow with volume
    case .aiTranscribing: return Color(hue: (rainbowHue + 0.15).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 1.0).opacity(averagePower * 0.6)  // Secondary rainbow with volume
    default: return .clear
    }
  }
  
  private var glowColor: Color {
    switch status {
    case .recording: return .red.opacity(0.7)
    case .aiRecording: return aiBaseColor.opacity(0.7)
    case .transcribing: return Color(hue: rainbowHue, saturation: 1.0, brightness: 1.0).opacity(0.7)  // Rainbow glow matching recording intensity
    case .aiTranscribing: return Color(hue: rainbowHue, saturation: 1.0, brightness: 1.0).opacity(0.7)  // Rainbow glow matching recording intensity
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
      }

    }
    .overlay(alignment: .top) {
      // Show AI response modal as overlay (aligns top edge with indicator)
      if status == .aiResponse, let response = aiResponse {
        AIResponseModalUIKit(
          response: response,
          onDismiss: onDismissAI
        )
        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
      }
    }
    .enableInjection()
  }
}

// Preview disabled due to Meter type resolution issue
// To test the view, run the full app or use TranscriptionFeature