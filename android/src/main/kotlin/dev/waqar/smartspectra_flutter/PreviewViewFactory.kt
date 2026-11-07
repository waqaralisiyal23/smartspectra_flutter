package dev.waqar.smartspectra_flutter

import android.content.Context
import android.view.View
import androidx.camera.core.Preview
import androidx.camera.view.PreviewView
import com.presagetech.smartspectra.SmartSpectraSdk
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates [SmartSpectraPreviewView]s for the `smartspectra_flutter/preview` view type. */
internal class PreviewViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        SmartSpectraPreviewView(context)
}

/**
 * Hosts a CameraX [PreviewView] and hands its surface provider to the SDK.
 *
 * Uses TextureView-backed COMPATIBLE mode so it composes correctly inside
 * Flutter's platform-view layers.
 */
internal class SmartSpectraPreviewView(context: Context) : PlatformView {
    private val sdk = SmartSpectraSdk.shared
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val surfaceProvider: Preview.SurfaceProvider = previewView.surfaceProvider

    init {
        sdk.config.previewSurfaceProvider = surfaceProvider
    }

    override fun getView(): View = previewView

    override fun dispose() {
        if (sdk.config.previewSurfaceProvider === surfaceProvider) {
            sdk.config.previewSurfaceProvider = null
        }
    }
}
