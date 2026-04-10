import SwiftUI
import Cocoa

// MARK: - Utilization Color Helper

private func utilizationNSColor(for value: Double) -> NSColor {
    if value >= 0.80 { return .systemRed }
    if value >= 0.60 { return .systemYellow }
    return .black
}

// MARK: - Pulse Dot

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
        let arcColor = utilizationNSColor(for: clampedPercentage)

        // Track circle (30% opacity of arc color)
        context.setStrokeColor(arcColor.withAlphaComponent(0.3).cgColor)
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
            context.setStrokeColor(arcColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            let startAngle = CGFloat.pi / 2
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

        // Center filled ellipse
        context.setFillColor(arcColor.cgColor)
        context.fillEllipse(in: CGRect(x: 6.5, y: 6.5, width: 5, height: 5))

        image.unlockFocus()

        // Only use template (monochrome) when utilization is low — colors need isTemplate = false
        image.isTemplate = clampedPercentage < 0.60

        return image
    }
}

// MARK: - Menu Bar Icon View

struct MenuBarIconView: View {
    let usage: UsageState?
    let isAuthenticated: Bool
    let show5hPercentage: Bool
    let show5hResetTime: Bool
    let show7dPercentage: Bool
    let show7dResetTime: Bool
    let showExtraUsageCredits: Bool
    let use24HourTime: Bool

    @State private var currentImage: Image
    @State private var currentPercentage: Double = -1.0

    init(
        usage: UsageState?,
        isAuthenticated: Bool,
        show5hPercentage: Bool,
        show5hResetTime: Bool,
        show7dPercentage: Bool,
        show7dResetTime: Bool,
        showExtraUsageCredits: Bool,
        use24HourTime: Bool
    ) {
        self.usage = usage
        self.isAuthenticated = isAuthenticated
        self.show5hPercentage = show5hPercentage
        self.show5hResetTime = show5hResetTime
        self.show7dPercentage = show7dPercentage
        self.show7dResetTime = show7dResetTime
        self.showExtraUsageCredits = showExtraUsageCredits
        self.use24HourTime = use24HourTime
        self._currentImage = State(initialValue: Image(systemName: "circle.dotted"))
    }

    var body: some View {
        HStack(spacing: 4) {
            currentImage
                .onAppear { updateImage() }
                .onChange(of: usage?.utilization5h) { _, _ in updateImage() }
                .onChange(of: isAuthenticated) { _, _ in updateImage() }

            if let label = labelText {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }

    // MARK: - Label

    private var labelText: String? {
        guard let usage = usage, isAuthenticated else { return nil }

        var groups: [String] = []

        var fiveHourParts: [String] = []
        if show5hPercentage {
            fiveHourParts.append("\(Int(usage.utilization5h * 100))%")
        }
        if show5hResetTime {
            fiveHourParts.append(TimeFormatPolicy.menuBarClockString(from: usage.resetAt5h, use24HourTime: use24HourTime))
        }
        if !fiveHourParts.isEmpty {
            groups.append("5h " + fiveHourParts.joined(separator: " "))
        }

        var sevenDayParts: [String] = []
        if show7dPercentage {
            sevenDayParts.append("\(Int(usage.utilization7d * 100))%")
        }
        if show7dResetTime {
            sevenDayParts.append(TimeFormatPolicy.menuBarDayString(from: usage.resetAt7d))
        }
        if !sevenDayParts.isEmpty {
            groups.append("7d " + sevenDayParts.joined(separator: " "))
        }

        if showExtraUsageCredits,
           let extra = usage.extraUsage,
           extra.isEnabled,
           let used = extra.usedCreditsAmount,
           let limit = extra.monthlyLimitAmount {
            let usedStr = String(format: "%.2f", used)
            let limitStr = limit.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(limit))
                : String(format: "%.2f", limit)
            groups.append("$\(usedStr)/$\(limitStr)")
        }

        return groups.isEmpty ? nil : groups.joined(separator: " · ")
    }

    // MARK: - Image

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
