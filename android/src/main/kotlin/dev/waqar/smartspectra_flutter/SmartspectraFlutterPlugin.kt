package dev.waqar.smartspectra_flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.Observer
import com.presagetech.smartspectra.CameraSelection
import com.presagetech.smartspectra.ProcessingStatus
import com.presagetech.smartspectra.SmartSpectraConfig
import com.presagetech.smartspectra.SmartSpectraError
import com.presagetech.smartspectra.SmartSpectraException
import com.presagetech.smartspectra.SmartSpectraSdk
import com.presagetech.smartspectra.ValidationStatus
import com.presagetech.smartspectra.proto.MetricTypesProto.MetricType
import com.presagetech.smartspectra.proto.MetricsProto.Metrics
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Flutter bridge to the SmartSpectra Android SDK. */
class SmartspectraFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var scope = MainScope()
    private val mapper = MetricsMapper()

    private val sdk: SmartSpectraSdk get() = SmartSpectraSdk.shared

    // region Observers

    private val statusObserver = Observer<ProcessingStatus?> { status ->
        if (status != null) emit("status", status.name)
    }

    private val validationObserver = Observer<ValidationStatus?> { status ->
        if (status != null) {
            emit("validation", mapOf("code" to status.code.name, "hint" to status.hint))
        }
    }

    private val errorObserver = Observer<SmartSpectraError?> { error ->
        if (error != null) emit("error", errorMap(error))
    }

    private val metricsObserver = Observer<Metrics?> { metrics ->
        if (metrics != null) mapper.map(metrics)?.let { emit("metrics", it) }
    }

    /**
     * Stops measuring as soon as the app is no longer visible, so the camera
     * never keeps running in the background. The app calls start() again when
     * the user returns.
     */
    private val lifecycleObserver = LifecycleEventObserver { _, event ->
        if (event == Lifecycle.Event.ON_STOP) scope.launch { runCatching { sdk.stop() } }
    }

    /** Keeps the screen awake only while a measurement is starting or running. */
    private val keepAwakeObserver = Observer<ProcessingStatus?> { status ->
        setKeepScreenOn(status == ProcessingStatus.STARTING || status == ProcessingStatus.RUNNING)
    }

    private fun setKeepScreenOn(on: Boolean) {
        val window = activity?.window ?: return
        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (on) window.addFlags(flag) else window.clearFlags(flag)
    }

    // endregion

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "smartspectra_flutter/methods")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "smartspectra_flutter/events")
        events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "smartspectra_flutter/preview",
            PreviewViewFactory(),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        removeObservers()
        scope.cancel()
        scope = MainScope()
        appContext = null
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        (binding.activity as? LifecycleOwner)?.lifecycle?.addObserver(lifecycleObserver)
        sdk.processingStatus.observeForever(keepAwakeObserver)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        detachActivity()
        // The camera must not outlive the UI that showed it.
        scope.launch { runCatching { sdk.stop() } }
    }

    private fun detachActivity() {
        sdk.processingStatus.removeObserver(keepAwakeObserver)
        setKeepScreenOn(false)
        (activity as? LifecycleOwner)?.lifecycle?.removeObserver(lifecycleObserver)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        pendingPermission?.success(false)
        pendingPermission = null
    }

    // endregion

    // region EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        sdk.processingStatus.observeForever(statusObserver)
        sdk.validationStatus.observeForever(validationObserver)
        sdk.error.observeForever(errorObserver)
        sdk.metrics.observeForever(metricsObserver)
    }

    override fun onCancel(arguments: Any?) {
        removeObservers()
        sink = null
    }

    private fun removeObservers() {
        sdk.processingStatus.removeObserver(statusObserver)
        sdk.validationStatus.removeObserver(validationObserver)
        sdk.error.removeObserver(errorObserver)
        sdk.metrics.removeObserver(metricsObserver)
    }

    private fun emit(type: String, data: Any?) {
        sink?.success(mapOf("type" to type, "data" to data))
    }

    // endregion

    // region MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "hasCameraPermission" -> result.success(hasCameraPermission())
            "requestCameraPermission" -> requestCameraPermission(result)
            "start" -> start(result)
            "stop" -> runSuspending(result) { sdk.stop() }
            "reset" -> runSuspending(result) { sdk.reset() }
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: MethodChannel.Result) {
        val apiKey = call.argument<String>("apiKey")
        if (apiKey.isNullOrBlank()) {
            result.error("CONFIGURATION_FAILED", "apiKey is required", null)
            return
        }
        try {
            sdk.config.apiKey = apiKey
            sdk.config.enableTelemetry = call.argument<Boolean>("enableTelemetry") ?: false
            // Android previews through a CameraX PreviewView, not bitmaps.
            sdk.config.imageOutputEnabled = false
            sdk.config.requestedMetrics = requestedMetrics(call.argument<List<String>>("metrics"))
            sdk.useCamera(
                when (call.argument<String>("camera")) {
                    "back" -> CameraSelection.Back
                    "defaultCamera" -> CameraSelection.Default
                    else -> CameraSelection.Front
                },
            )
            result.success(null)
        } catch (e: SmartSpectraException) {
            replyError(result, e)
        } catch (e: Exception) {
            result.error("CONFIGURATION_FAILED", e.message, null)
        }
    }

    private fun requestedMetrics(names: List<String>?): List<MetricType>? {
        if (names.isNullOrEmpty()) return null
        val out = LinkedHashSet<MetricType>()
        for (name in names) {
            when (name) {
                "breathing" -> out.addAll(SmartSpectraConfig.breathingMetrics)
                "cardio" -> out.addAll(SmartSpectraConfig.cardioMetrics)
                "expressions" -> out.add(MetricType.EXPRESSIONS)
                "blinking" -> out.add(MetricType.BLINKING)
                "talking" -> out.add(MetricType.TALKING)
                "eda" -> out.addAll(SmartSpectraConfig.edaMetrics)
            }
        }
        return out.toList().ifEmpty { null }
    }

    private fun start(result: MethodChannel.Result) {
        if (!hasCameraPermission()) {
            result.error("INPUT_UNAVAILABLE", "Camera permission has not been granted", null)
            return
        }
        mapper.reset()
        runSuspending(result) { sdk.start() }
    }

    private fun runSuspending(result: MethodChannel.Result, block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
                result.success(null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: SmartSpectraException) {
                replyError(result, e)
            } catch (e: Exception) {
                result.error("PROCESSING_FAILED", e.message ?: e.toString(), null)
            }
        }
    }

    private fun replyError(result: MethodChannel.Result, e: SmartSpectraException) {
        @Suppress("USELESS_ELVIS")
        val error: SmartSpectraError = e.error ?: run {
            result.error("PROCESSING_FAILED", e.message ?: e.toString(), null)
            return
        }
        result.error(error.code.name, error.message, mapOf("retryable" to error.retryable))
    }

    private fun errorMap(error: SmartSpectraError) = mapOf(
        "code" to error.code.name,
        "message" to error.message,
        "retryable" to error.retryable,
    )

    // endregion

    // region Permissions

    private fun hasCameraPermission(): Boolean {
        val context = activity ?: appContext ?: return false
        return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (hasCameraPermission()) {
            result.success(true)
            return
        }
        val current = activity
        if (current == null) {
            result.error("INVALID_STATE", "No foreground activity to request permission from", null)
            return
        }
        if (pendingPermission != null) {
            result.error("INVALID_STATE", "A camera permission request is already in progress", null)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            current,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    // endregion

    private companion object {
        const val CAMERA_REQUEST_CODE = 0x5350 // "SP"
    }
}
