//
//  AIResponseUIKitView.swift
//  Hex
//
//  Created by Assistant on 8/26/25.
//

import SwiftUI
import AppKit // For NSFont, to compute sizes accurately

// PreferenceKey for tracking scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DynamicTextView: View {
    var text: String
    var onDismiss: () -> Void
    
    var body: some View {
        let nsFont = NSFont.systemFont(ofSize: 14)
        let font = Font.system(size: 14) // Matching SwiftUI font
        
        let maxLineWidth = computeMaxLineWidth(for: text, with: nsFont)
        let preferredWidth = min(maxLineWidth + 40, 400.0) // Add padding
        
        let contentHeight = computeHeight(at: preferredWidth - 40, for: text, with: nsFont)
        let preferredHeight = min(contentHeight + 40, 600.0) // Add padding and cap at 600
        
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) { // Hide native scrollbar
                Text(text)
                    .font(font)
                    .foregroundColor(.black)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(width: preferredWidth, height: preferredHeight)
            .background(
                ZStack {
                    // Glass effect with blur
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle white overlay for better text readability
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.3))
                }
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .overlay(alignment: .trailing) {
                // iOS-style overlay scrollbar (only show if scrollable)
                if preferredHeight >= 600 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 3, height: 50) // Thumb size
                        .padding(.trailing, 4)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false) // Don't interfere with scrolling
                }
            }
            
            // Floating X button with glass effect
            Button(action: onDismiss) {
                ZStack {
                    // White glass circle background
                    Circle()
                        .fill(.thinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.4))
                        )
                    
                    // X with clear/transparent effect
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary) // This creates a subtle, translucent appearance
                }
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
    
    private func computeMaxLineWidth(for text: String, with font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 100 }
        
        let lines = text.components(separatedBy: .newlines)
        var maxWidth: CGFloat = 0
        
        for line in lines {
            let lineSize = (line as NSString).size(withAttributes: [.font: font])
            maxWidth = max(maxWidth, lineSize.width)
        }
        
        return ceil(maxWidth)
    }
    
    private func computeHeight(at width: CGFloat, for text: String, with font: NSFont) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 50 }
        
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = (text as NSString).boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        
        return ceil(boundingBox.height)
    }
}

// Wrapper for auto-dismiss behavior
struct AIResponseModalUIKit: View {
    let response: String
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var opacity: Double = 1.0
    
    // Calculate dismiss delay based on text length
    var dismissDelay: TimeInterval {
        let wordsPerMinute = 250.0
        let words = Double(response.split(separator: " ").count)
        let readingTime = (words / wordsPerMinute) * 60
        return min(max(readingTime + 3, 4), 8)
    }
    
    var body: some View {
        DynamicTextView(text: response, onDismiss: {
            dismissTask?.cancel()
            fadeOutAndDismiss()
        })
        .opacity(opacity)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                dismissTask?.cancel()
                dismissTask = nil
                opacity = 1.0
            }
        }
        .onAppear {
            print("[AI Modal] Modal appeared - starting timer")
            startDismissTimer()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }
    
    private func startDismissTimer() {
        dismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(dismissDelay))
                
                if !isHovered && !Task.isCancelled {
                    await fadeOutAndDismiss()
                }
            } catch {
                // Task was cancelled
            }
        }
    }
    
    private func fadeOutAndDismiss() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
            }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                onDismiss()
            }
        }
    }
}