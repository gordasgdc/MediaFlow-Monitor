import Foundation

/// Un punct de istoric pentru grafice — timestamp + valoare.
struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// Ring-buffer simplu pentru seriile de timp afișate în grafice
/// (VRAM/Swap utilization, CPU per-thread) — capacitate fixă, nu crește
/// nemărginit cât timp aplicația rulează.
final class MetricsHistory {
    private let capacity: Int
    private(set) var points: [HistoryPoint] = []

    init(capacity: Int = 120) { // ~ 6 minute la 3s/tick
        self.capacity = capacity
    }

    func append(_ value: Double, at date: Date = Date()) {
        points.append(HistoryPoint(date: date, value: value))
        if points.count > capacity {
            points.removeFirst(points.count - capacity)
        }
    }
}
