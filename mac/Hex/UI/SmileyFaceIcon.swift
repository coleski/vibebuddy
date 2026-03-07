import SwiftUI
import AppKit

struct SmileyFaceIcon {
    static func createIcon(size: CGSize = CGSize(width: 22, height: 22), isAnimating: Bool = false) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        
        // Clear background
        context?.setFillColor(NSColor.clear.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        // Match TranscriptionIndicatorView positioning exactly
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        
        // Eyes - matching TranscriptionIndicatorView
        context?.setFillColor(NSColor.black.cgColor)
        let eyeSize: CGFloat = 2.0
        let eyeSpacing: CGFloat = isAnimating ? size.width * 0.35 : 6.0  // Increased from 3.0 to 6.0
        
        // Position eyes above center (macOS coordinates - Y increases upward)
        let leftEyeX = center.x - eyeSpacing/2 - eyeSize/2
        let rightEyeX = center.x + eyeSpacing/2 - eyeSize/2
        let eyeY = center.y + 2 - eyeSize/2  // Higher Y = above in macOS
        
        context?.fillEllipse(in: CGRect(x: leftEyeX, y: eyeY, width: eyeSize, height: eyeSize))
        context?.fillEllipse(in: CGRect(x: rightEyeX, y: eyeY, width: eyeSize, height: eyeSize))
        
        // Mouth - matching TranscriptionIndicatorView
        context?.setStrokeColor(NSColor.black.cgColor)
        context?.setLineWidth(1.5)
        context?.setLineCap(.round)
        
        if isAnimating {
            // Open mouth for talking (wider spacing)
            let path = CGMutablePath()
            let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
            let smileWidth = eyeTotalWidth * 0.75
            let height = size.height * 0.15
            let yOffset = center.y - size.height * 0.15  // Lower Y = below in macOS
            
            // Draw as an open oval-ish shape
            path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
            path.addQuadCurve(
                to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
                control: CGPoint(x: center.x, y: yOffset - height)  // Control point below for smile
            )
            context?.addPath(path)
            context?.strokePath()
        } else {
            // Normal smile - matching TranscriptionIndicatorView exactly
            let path = CGMutablePath()
            let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
            let smileWidth = eyeTotalWidth * 0.75
            let height = size.height * 0.15
            let yOffset = center.y - size.height * 0.15  // Lower Y = below in macOS
            
            path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
            path.addQuadCurve(
                to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
                control: CGPoint(x: center.x, y: yOffset - height)  // Control point below for smile
            )
            context?.addPath(path)
            context?.strokePath()
        }
        
        image.unlockFocus()
        // Use template mode for proper menu bar appearance
        image.isTemplate = true
        return image
    }
    
    
    static func createUpsideDownIcon(size: CGSize = CGSize(width: 22, height: 22)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        
        // Clear background
        context?.setFillColor(NSColor.clear.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        
        // Draw eyes (upside down - at bottom)
        context?.setFillColor(NSColor.black.cgColor)
        
        let eyeSize: CGFloat = 2.0
        let eyeSpacing: CGFloat = 6.0  // Match the normal icon spacing
        
        let leftEyeX = center.x - eyeSpacing/2 - eyeSize/2
        let rightEyeX = center.x + eyeSpacing/2 - eyeSize/2
        let eyeY = center.y - 2 - eyeSize/2 // Position eyes below for upside down (lower Y in macOS)
        
        context?.fillEllipse(in: CGRect(x: leftEyeX, y: eyeY, width: eyeSize, height: eyeSize))
        context?.fillEllipse(in: CGRect(x: rightEyeX, y: eyeY, width: eyeSize, height: eyeSize))
        
        // Draw frown (upside down smile - at top)
        context?.setStrokeColor(NSColor.black.cgColor)
        context?.setLineWidth(1.5)
        context?.setLineCap(.round)
        
        let path = CGMutablePath()
        let eyeTotalWidth = (eyeSize * 2) + eyeSpacing
        let smileWidth = eyeTotalWidth * 0.75
        let height = size.height * 0.15
        let yOffset = center.y + size.height * 0.15  // Higher Y for top position
        
        path.move(to: CGPoint(x: center.x - smileWidth/2, y: yOffset))
        path.addQuadCurve(
            to: CGPoint(x: center.x + smileWidth/2, y: yOffset),
            control: CGPoint(x: center.x, y: yOffset + height) // Upward curve for frown
        )
        context?.addPath(path)
        context?.strokePath()
        
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}