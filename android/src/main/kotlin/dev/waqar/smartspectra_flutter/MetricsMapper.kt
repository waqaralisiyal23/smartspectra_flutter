package dev.waqar.smartspectra_flutter

import com.presagetech.smartspectra.proto.MetricsProto.ExpressionType
import com.presagetech.smartspectra.proto.MetricsProto.Metrics

/**
 * Converts SDK protobuf [Metrics] into plain maps for the Flutter codec.
 *
 * Rates are reduced to their latest valid value. Traces are reduced to the
 * samples that are new since the previous update, so Dart can append them.
 */
internal class MetricsMapper {
    private var lastPulseTrace = Long.MIN_VALUE
    private var lastBreathingTrace = Long.MIN_VALUE
    private var lastEdaTrace = Long.MIN_VALUE
    private var lastBlink = Long.MIN_VALUE
    private var eyesClosed = false

    fun reset() {
        lastPulseTrace = Long.MIN_VALUE
        lastBreathingTrace = Long.MIN_VALUE
        lastEdaTrace = Long.MIN_VALUE
        lastBlink = Long.MIN_VALUE
        eyesClosed = false
    }

    fun map(metrics: Metrics): Map<String, Any?>? {
        val out = HashMap<String, Any?>()

        if (metrics.hasCardio()) {
            val cardio = metrics.cardio
            cardio.pulseRateList.lastOrNull { it.timestamp > 0 }?.let {
                out["pulseRate"] = reading(it.value, it.confidence, it.stable, it.timestamp)
            }
            cardio.hrvList.lastOrNull { it.timestamp > 0 }?.let {
                out["hrv"] = mapOf(
                    "rmssd" to it.rmssd,
                    "sdnn" to it.sdnn,
                    "meanNn" to it.meanNn,
                    "baevsky" to it.baevsky,
                    "confidence" to it.confidence.toDouble(),
                    "stable" to it.stable,
                    "timestamp" to it.timestamp,
                )
            }
            val fresh = cardio.arterialPressureTraceList.filter { it.timestamp > lastPulseTrace }
            if (fresh.isNotEmpty()) {
                lastPulseTrace = fresh.last().timestamp
                out["pulseTrace"] = trace(fresh.map { it.timestamp }, fresh.map { it.value })
            }
        }

        if (metrics.hasBreathing()) {
            val breathing = metrics.breathing
            breathing.rateList.lastOrNull { it.timestamp > 0 }?.let {
                out["breathingRate"] = reading(it.value, it.confidence, it.stable, it.timestamp)
            }
            val fresh = breathing.upperTraceList.filter { it.timestamp > lastBreathingTrace }
            if (fresh.isNotEmpty()) {
                lastBreathingTrace = fresh.last().timestamp
                out["breathingTrace"] = trace(fresh.map { it.timestamp }, fresh.map { it.value })
            }
        }

        if (metrics.hasFace()) {
            val face = metrics.face
            face.expressionList.lastOrNull()?.let { expression ->
                val scores = expression.scoresList
                    .filter {
                        it.type != ExpressionType.UNSPECIFIED &&
                            it.type != ExpressionType.UNRECOGNIZED
                    }
                    .associate { it.type.name to it.confidence.toDouble() }
                if (scores.isNotEmpty()) {
                    out["expression"] = mapOf(
                        "scores" to scores,
                        "stable" to expression.stable,
                        "timestamp" to expression.timestamp,
                    )
                }
            }
            face.blinkingList.lastOrNull()?.let {
                out["blinking"] = detection(it.detected, it.stable, it.timestamp)
            }
            // One update can hold several blink samples; count every
            // open -> closed transition so no blink is lost between updates.
            val freshBlinks = face.blinkingList.filter { it.timestamp > lastBlink }
            if (freshBlinks.isNotEmpty()) {
                var count = 0
                for (sample in freshBlinks) {
                    if (sample.detected && !eyesClosed) count++
                    eyesClosed = sample.detected
                }
                lastBlink = freshBlinks.last().timestamp
                out["newBlinks"] = count
            }
            face.talkingList.lastOrNull()?.let {
                out["talking"] = detection(it.detected, it.stable, it.timestamp)
            }
        }

        if (metrics.hasEda()) {
            val fresh = metrics.eda.traceList.filter { it.timestamp > lastEdaTrace }
            if (fresh.isNotEmpty()) {
                lastEdaTrace = fresh.last().timestamp
                out["edaTrace"] = trace(fresh.map { it.timestamp }, fresh.map { it.value })
            }
        }

        return out.ifEmpty { null }
    }

    private fun reading(value: Float, confidence: Float, stable: Boolean, timestamp: Long) = mapOf(
        "value" to value.toDouble(),
        "confidence" to confidence.toDouble(),
        "stable" to stable,
        "timestamp" to timestamp,
    )

    private fun detection(detected: Boolean, stable: Boolean, timestamp: Long) = mapOf(
        "detected" to detected,
        "stable" to stable,
        "timestamp" to timestamp,
    )

    private fun trace(timestamps: List<Long>, values: List<Float>) = mapOf(
        "t" to timestamps,
        "v" to values.map { it.toDouble() },
    )
}
