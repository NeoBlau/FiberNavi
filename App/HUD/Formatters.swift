import Foundation

enum Format {
    /// «350 м», «1,2 км», «24 км».
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            let step: Double = meters < 100 ? 10 : 50
            return "\(Int((meters / step).rounded() * step)) м"
        }
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.1f км", km).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int(km.rounded())) км"
    }

    /// «7 мин», «1 ч 05 мин».
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) мин" }
        return String(format: "%d ч %02d мин", minutes / 60, minutes % 60)
    }

    /// Время прибытия «14:35».
    static func eta(after seconds: TimeInterval, from now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now.addingTimeInterval(seconds))
    }
}
