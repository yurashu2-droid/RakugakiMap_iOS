import Foundation

public struct RevealGate: Sendable {
    private var lastAcceptedTimestamp: Date?
    private var consecutiveCount = 0
    private var unlocked = false

    public init() {}

    public mutating func ingest(
        distanceM: Double,
        accuracyM: Double,
        timestamp: Date,
        now: Date,
        radiusM: Double
    ) -> Bool {
        if unlocked { return true }

        let sampleAge = now.timeIntervalSince(timestamp)
        guard distanceM.isFinite, accuracyM.isFinite, radiusM.isFinite,
              sampleAge.isFinite,
              (10.0...200.0).contains(radiusM),
              distanceM >= 0, distanceM <= radiusM,
              (0.0...25.0).contains(accuracyM),
              (0.0...10.0).contains(sampleAge) else {
            lastAcceptedTimestamp = nil
            consecutiveCount = 0
            return false
        }

        if let lastAcceptedTimestamp, timestamp <= lastAcceptedTimestamp {
            return false
        }

        lastAcceptedTimestamp = timestamp
        consecutiveCount += 1
        if consecutiveCount >= 2 {
            unlocked = true
        }
        return unlocked
    }
}
