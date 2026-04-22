import Foundation

struct ShakeDetector {
    private var samples: [(position: CGPoint, time: TimeInterval)] = []
    private var lastFiredAt: TimeInterval = -.infinity

    var windowDuration: TimeInterval = 0.4
    var minReverseCount: Int = 3
    var minSpeed: CGFloat = 600
    var cooldownDuration: TimeInterval = 1.5

    mutating func record(point: CGPoint, at time: TimeInterval) -> CGPoint? {
        samples.append((position: point, time: time))
        samples.removeAll { time - $0.time > windowDuration }

        guard samples.count >= 4, time - lastFiredAt > cooldownDuration else { return nil }

        var reversals = 0
        for i in 1..<samples.count - 1 {
            let prev = samples[i - 1]
            let curr = samples[i]
            let next = samples[i + 1]

            let dt1 = curr.time - prev.time
            let dt2 = next.time - curr.time
            guard dt1 > 0, dt2 > 0 else { continue }

            let vx1 = (curr.position.x - prev.position.x) / dt1
            let vx2 = (next.position.x - curr.position.x) / dt2

            if abs(vx1) > minSpeed && abs(vx2) > minSpeed && vx1.sign != vx2.sign {
                reversals += 1
            }
        }

        if reversals >= minReverseCount {
            lastFiredAt = time
            return samples.last?.position
        }
        return nil
    }

    mutating func reset() {
        samples.removeAll()
        lastFiredAt = -.infinity
    }
}
