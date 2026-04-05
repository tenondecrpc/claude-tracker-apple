import SwiftUI
import Cocoa

extension NSImage {
    static func usageBar(percentage: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        
        let barCount = 3
        let barWidth: CGFloat = 2
        let barSpacing: CGFloat = 3
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (size.width - totalWidth) / 2
        let maxHeight: CGFloat = 10
        let minHeight: CGFloat = 4
        let baseY: CGFloat = (size.height - maxHeight) / 2
        
        // Determine how many bars to fill
        let clampedPercentage = max(0, min(1, percentage))
        let filledBars: Int
        if clampedPercentage == 0 {
            filledBars = 0
        } else if clampedPercentage <= 0.33 {
            filledBars = 1
        } else if clampedPercentage <= 0.66 {
            filledBars = 2
        } else {
            filledBars = 3
        }
        
        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let height = minHeight + (maxHeight - minHeight) * CGFloat(i + 1) / CGFloat(barCount)
            let y = baseY

            let rect = CGRect(x: x, y: y, width: barWidth, height: height)

            // Fill from left to right (signal strength style)
            if i < filledBars {
                context.setFillColor(NSColor.black.cgColor)
            } else {
                context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            }
            context.fill(rect)
        }
        
        image.unlockFocus()
        image.isTemplate = true
        
        return image
    }
}

struct DynamicMenuBarIconView: View {
    let usage: UsageState?
    let isAuthenticated: Bool
    
    @State private var currentImage: Image
    @State private var currentPercentage: Double = -1.0
    
    init(usage: UsageState?, isAuthenticated: Bool) {
        self.usage = usage
        self.isAuthenticated = isAuthenticated
        self._currentImage = State(initialValue: Image(systemName: "chart.bar"))
    }
    
    var body: some View {
        HStack(spacing: 4) {
            currentImage
                .onAppear {
                    updateImage()
                }
                .onChange(of: usage?.utilization5h) { _, _ in
                    updateImage()
                }
                .onChange(of: isAuthenticated) { _, _ in
                    updateImage()
                }
            
            if let usage = usage, isAuthenticated {
                Text("\(Int(usage.utilization5h * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }
    
    private func updateImage() {
        guard isAuthenticated, let usage = usage else {
            currentImage = Image(systemName: "chart.bar")
            currentPercentage = -1.0
            return
        }
        
        let newPercentage = usage.utilization5h
        
        if abs(newPercentage - currentPercentage) >= 0.01 || currentPercentage < 0 {
            currentPercentage = newPercentage
            let nsImage = NSImage.usageBar(percentage: newPercentage)
            currentImage = Image(nsImage: nsImage)
        }
    }
}
