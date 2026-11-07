import SmartSpectra

/// Converts SDK `Metrics` into plain dictionaries for the Flutter codec.
///
/// Rates are reduced to their latest valid value. Traces are reduced to the
/// samples that are new since the previous update, so Dart can append them.
final class MetricsMapper {
    private var lastPulseTrace: Int64 = .min
    private var lastBreathingTrace: Int64 = .min
    private var lastEdaTrace: Int64 = .min
    private var lastBlink: Int64 = .min
    private var eyesClosed = false

    func reset() {
        lastPulseTrace = .min
        lastBreathingTrace = .min
        lastEdaTrace = .min
        lastBlink = .min
        eyesClosed = false
    }

    func map(_ metrics: Metrics) -> [String: Any]? {
        var out: [String: Any] = [:]

        let cardio = metrics.cardio
        if let pulse = cardio.pulseRate.last(where: { $0.timestamp > 0 }) {
            out["pulseRate"] = reading(pulse.value, pulse.confidence, pulse.stable, pulse.timestamp)
        }
        if let hrv = cardio.hrv.last(where: { $0.timestamp > 0 }) {
            out["hrv"] = [
                "rmssd": hrv.rmssd,
                "sdnn": hrv.sdnn,
                "meanNn": hrv.meanNn,
                "baevsky": hrv.baevsky,
                "confidence": Double(hrv.confidence),
                "stable": hrv.stable,
                "timestamp": hrv.timestamp,
            ] as [String: Any]
        }
        let freshPulse = cardio.arterialPressureTrace.filter { $0.timestamp > lastPulseTrace }
        if let last = freshPulse.last {
            lastPulseTrace = last.timestamp
            out["pulseTrace"] = trace(freshPulse.map(\.timestamp), freshPulse.map(\.value))
        }

        let breathing = metrics.breathing
        if let rate = breathing.rate.last(where: { $0.timestamp > 0 }) {
            out["breathingRate"] = reading(rate.value, rate.confidence, rate.stable, rate.timestamp)
        }
        let freshBreathing = breathing.upperTrace.filter { $0.timestamp > lastBreathingTrace }
        if let last = freshBreathing.last {
            lastBreathingTrace = last.timestamp
            out["breathingTrace"] = trace(freshBreathing.map(\.timestamp), freshBreathing.map(\.value))
        }

        let face = metrics.face
        if let expression = face.expression.last {
            var scores: [String: Double] = [:]
            for score in expression.scores {
                if let name = Self.name(of: score.type) {
                    scores[name] = Double(score.confidence)
                }
            }
            if !scores.isEmpty {
                out["expression"] = [
                    "scores": scores,
                    "stable": expression.stable,
                    "timestamp": expression.timestamp,
                ] as [String: Any]
            }
        }
        if let blink = face.blinking.last {
            out["blinking"] = detection(blink.detected, blink.stable, blink.timestamp)
        }
        // One update can hold several blink samples; count every
        // open -> closed transition so no blink is lost between updates.
        let freshBlinks = face.blinking.filter { $0.timestamp > lastBlink }
        if let last = freshBlinks.last {
            var count = 0
            for sample in freshBlinks {
                if sample.detected && !eyesClosed { count += 1 }
                eyesClosed = sample.detected
            }
            lastBlink = last.timestamp
            out["newBlinks"] = count
        }
        if let talk = face.talking.last {
            out["talking"] = detection(talk.detected, talk.stable, talk.timestamp)
        }

        let freshEda = metrics.eda.trace.filter { $0.timestamp > lastEdaTrace }
        if let last = freshEda.last {
            lastEdaTrace = last.timestamp
            out["edaTrace"] = trace(freshEda.map(\.timestamp), freshEda.map(\.value))
        }

        return out.isEmpty ? nil : out
    }

    private static func name(of type: ExpressionType) -> String? {
        switch type {
        case .angry: return "ANGRY"
        case .contempt: return "CONTEMPT"
        case .disgust: return "DISGUST"
        case .fear: return "FEAR"
        case .happy: return "HAPPY"
        case .neutral: return "NEUTRAL"
        case .sad: return "SAD"
        case .surprise: return "SURPRISE"
        default: return nil
        }
    }

    private func reading(_ value: Float, _ confidence: Float, _ stable: Bool, _ timestamp: Int64) -> [String: Any] {
        ["value": Double(value), "confidence": Double(confidence), "stable": stable, "timestamp": timestamp]
    }

    private func detection(_ detected: Bool, _ stable: Bool, _ timestamp: Int64) -> [String: Any] {
        ["detected": detected, "stable": stable, "timestamp": timestamp]
    }

    private func trace(_ timestamps: [Int64], _ values: [Float]) -> [String: Any] {
        ["t": timestamps, "v": values.map { Double($0) }]
    }
}
