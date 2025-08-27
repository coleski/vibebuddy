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
    
    @State private var isScrolling = false
    @State private var hideScrollbarTask: Task<Void, Never>?
    
    var body: some View {
        let nsFont = NSFont.systemFont(ofSize: 14)
        let font = Font.system(size: 14) // Matching SwiftUI font
        
        let maxLineWidth = computeMaxLineWidth(for: text, with: nsFont)
        let preferredWidth = min(maxLineWidth + 40, 400.0) // Add padding
        
        let contentHeight = computeHeight(at: preferredWidth - 40, for: text, with: nsFont)
        let preferredHeight = min(contentHeight + 40, 600.0) // Add padding and cap at 600
        let isScrollable = preferredHeight >= 600
        
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) { // Hide native scrollbar
                Text(text)
                    .font(font)
                    .foregroundColor(.black)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(GeometryReader { geo in
                        Color.clear.onChange(of: geo.frame(in: .global).minY) { _ in
                            if isScrollable {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    isScrolling = true
                                }
                                
                                // Cancel previous hide task
                                hideScrollbarTask?.cancel()
                                
                                // Hide after 1 second of no scrolling
                                hideScrollbarTask = Task {
                                    try? await Task.sleep(for: .seconds(1))
                                    if !Task.isCancelled {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            isScrolling = false
                                        }
                                    }
                                }
                            }
                        }
                    })
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
                // iOS-style overlay scrollbar (only show if scrollable and scrolling)
                if isScrollable {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(isScrolling ? 0.5 : 0))
                        .frame(width: 3, height: 60) // Thumb size
                        .padding(.trailing, 4)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false) // Don't interfere with scrolling
                }
            }
            
            // Floating X button - white X on clear background
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle()) // Make entire frame clickable
            }
            .buttonStyle(.plain)
            .padding(4) // Much closer to corner
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