import UIKit

@MainActor
final class TraceHaptics {
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var lastFeedbackAt: Date?

    func prepare() {
        feedback.prepare()
    }

    func pulse(now: Date = .now) {
        if let lastFeedbackAt, now.timeIntervalSince(lastFeedbackAt) < 0.4 { return }
        lastFeedbackAt = now
        feedback.impactOccurred()
    }

    func stop() {
        lastFeedbackAt = nil
    }
}
