import SwiftUI
import Cocoa

extension NSImage {
    static func pulseDot(percentage: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let center = CGPoint(x: 9, y: 9)
        let radius: CGFloat = 6
        let lineWidth: CGFloat = 1.5
        let clampedPercentage = max(0, min(1, percentage))

        // Track circle (30% opacity)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(lineWidth)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.strokePath()

        // Arc fill (from -90° clockwise by utilization × 360°)
        if clampedPercentage > 0 {
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            let startAngle = CGFloat.pi / 2   // -90° in standard coords = π/2 in CoreGraphics (y-flipped)
            let endAngle = startAngle - (CGFloat(clampedPercentage) * .pi * 2)
            context.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            context.strokePath()
        }

        // Center filled ellipse (5×5pt at 6.5,6.5)
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: 6.5, y: 6.5, width: 5, height: 5))

        image.unlockFocus()
        image.isTemplate = true

        return image
    }
}

struct MenuBarIconView: View {
    let usage: UsageState?
    let isAuthenticated: Bool
    let showPercentage: Bool

    @State private var currentImage: Image
    @State private var currentPercentage: Double = -1.0

    init(usage: UsageState?, isAuthenticated: Bool, showPercentage: Bool) {
        self.usage = usage
        self.isAuthenticated = isAuthenticated
        self.showPercentage = showPercentage
        self._currentImage = State(initialValue: Image(systemName: "circle.dotted"))
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

            if let usage = usage, isAuthenticated, showPercentage {
                Text("\(Int(usage.utilization5h * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }

    private func updateImage() {
        guard isAuthenticated, let usage = usage else {
            currentImage = Image(systemName: "circle.dotted")
            currentPercentage = -1.0
            return
        }

        let newPercentage = usage.utilization5h

        if abs(newPercentage - currentPercentage) >= 0.01 || currentPercentage < 0 {
            currentPercentage = newPercentage
            let nsImage = NSImage.pulseDot(percentage: newPercentage)
            currentImage = Image(nsImage: nsImage)
        }
    }
}
