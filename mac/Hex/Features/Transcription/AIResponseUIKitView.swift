//
//  AIResponseUIKitView.swift
//  Hex
//
//  Created by Assistant on 8/26/25.
//

import SwiftUI

// PreferenceKey for tracking content height
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DynamicTextView: View {
    var text: String
    var onDismiss: () -> Void
    
    @State private var isScrolling = false
    @State private var hideScrollbarTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var actualContentHeight: CGFloat = 0
    
    var body: some View {
        let font = Font.system(size: 14)
        let maxWidth: CGFloat = 400
        let maxHeight: CGFloat = 600
        
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(font)
                        .foregroundColor(.black)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true) // Let text size itself naturally
                        .frame(maxWidth: maxWidth - 40, alignment: .leading)
                        .background(GeometryReader { geo in
                            Color.clear
                                .preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
                                .onChange(of: geo.frame(in: .named("scroll")).minY) { newValue in
                                    let needsScroll = actualContentHeight > maxHeight - 40
                                    if needsScroll {
                                        scrollOffset = -newValue
                                        
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            isScrolling = true
                                        }
                                        
                                        hideScrollbarTask?.cancel()
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
                .disabled(actualContentHeight <= maxHeight - 40) // Disable scroll when not needed
            }
            .coordinateSpace(name: "scroll")
            .padding(20)
            .frame(width: maxWidth, height: min(actualContentHeight + 40, maxHeight))
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
            .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                actualContentHeight = value
                containerHeight = min(value + 40, maxHeight)
            }
            .overlay(alignment: .topTrailing) {
                // iOS-style overlay scrollbar (only show if scrollable and scrolling)
                let needsScroll = actualContentHeight > maxHeight - 40
                if needsScroll {
                    let scrollableHeight = max(0, actualContentHeight - (maxHeight - 40))
                    let scrollProgress = scrollableHeight > 0 ? min(1, max(0, scrollOffset / scrollableHeight)) : 0
                    let thumbHeight: CGFloat = 60
                    let trackHeight = maxHeight - 40 - 16 // Track height within content area
                    let availableSpace = trackHeight - thumbHeight
                    let thumbOffset = availableSpace * scrollProgress
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(isScrolling ? 0.5 : 0))
                        .frame(width: 3, height: thumbHeight)
                        .offset(y: thumbOffset)
                        .padding(.trailing, 24) // Adjust for window padding
                        .padding(.vertical, 28) // Adjust for window padding
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