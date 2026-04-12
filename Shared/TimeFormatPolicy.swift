import Foundation

enum TimeFormatPolicy {
    private static func fixedTimeLocale(use24HourTime: Bool) -> Locale {
        use24HourTime ? Locale(identifier: "en_GB_POSIX") : Locale(identifier: "en_US_POSIX")
    }

    static func clockString(from date: Date, use24HourTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = fixedTimeLocale(use24HourTime: use24HourTime)
        formatter.dateFormat = use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    static func sessionResetString(resetAt date: Date, now: Date, use24HourTime: Bool, compact: Bool = false) -> String {
        guard date > now else { return "Fresh window" }
        let totalMinutes = Int(date.timeIntervalSince(now) / 60)
        let duration: String
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            duration = minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        } else {
            duration = "\(totalMinutes) min"
        }
        if compact {
            return "Resets in \(duration)"
        }
        return "Resets in \(duration) (\(clockString(from: date, use24HourTime: use24HourTime)))"
    }

    /// Short lowercase day name for menu bar labels: "sat", "sun", etc.
    static func menuBarDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).lowercased()
    }

    /// Compact clock string for menu bar labels: "8:15p" (12h) or "20:15" (24h).
    static func menuBarClockString(from date: Date, use24HourTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = fixedTimeLocale(use24HourTime: use24HourTime)
        if use24HourTime {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "h:mm a"
            let raw = formatter.string(from: date) // e.g. "8:15 AM"
            let parts = raw.components(separatedBy: " ")
            guard parts.count == 2 else { return raw }
            let suffix = parts[1].prefix(1).lowercased() // "a" or "p"
            return parts[0] + suffix // "8:15p"
        }
    }

    static func weeklyResetString(resetAt date: Date, use24HourTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = fixedTimeLocale(use24HourTime: use24HourTime)
        formatter.dateFormat = use24HourTime ? "EEE, HH:mm" : "EEE, h:mm a"
        return "Resets \(formatter.string(from: date))"
    }
}
