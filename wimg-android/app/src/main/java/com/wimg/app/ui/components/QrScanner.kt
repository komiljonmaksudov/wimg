package com.wimg.app.ui.components

import android.annotation.SuppressLint
import android.hardware.Camera
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.google.zxing.BinaryBitmap
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera preview that reads one QR code and hands its text to [onCode].
 * Uses the platform camera and ZXing's decoder, which the app already ships
 * for drawing the key: no extra library. Needs the CAMERA permission.
 */
@Suppress("DEPRECATION")
@SuppressLint("ClickableViewAccessibility")
@Composable
fun QrScanner(modifier: Modifier = Modifier, onCode: (String) -> Unit) {
    val state = remember { ScannerState() }
    DisposableEffect(Unit) { onDispose { state.stop() } }
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            SurfaceView(ctx).apply {
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(h: SurfaceHolder) = state.start(h, onCode)
                    override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) = Unit
                    override fun surfaceDestroyed(h: SurfaceHolder) = state.stop()
                })
            }
        },
    )
}

@Suppress("DEPRECATION")
private class ScannerState {
    private var camera: Camera? = null
    private val decoding = AtomicBoolean(false)
    private val done = AtomicBoolean(false)
    private val worker = Executors.newSingleThreadExecutor()
    private val reader = QRCodeReader()

    fun start(holder: SurfaceHolder, onCode: (String) -> Unit) {
        val cam = runCatching { Camera.open() }.getOrNull() ?: return
        camera = cam
        runCatching {
            cam.setDisplayOrientation(90)
            val p = cam.parameters
            if (Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE in p.supportedFocusModes) p.focusMode = Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE
            cam.parameters = p
            cam.setPreviewDisplay(holder)
            val size = cam.parameters.previewSize
            cam.setPreviewCallback { data, _ ->
                if (done.get() || !decoding.compareAndSet(false, true)) return@setPreviewCallback
                worker.execute {
                    val text = runCatching {
                        val src = PlanarYUVLuminanceSource(data, size.width, size.height, 0, 0, size.width, size.height, false)
                        reader.decode(BinaryBitmap(HybridBinarizer(src))).text
                    }.getOrNull()
                    reader.reset()
                    decoding.set(false)
                    if (text != null && done.compareAndSet(false, true)) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post { onCode(text) }
                    }
                }
            }
            cam.startPreview()
        }
    }

    fun stop() {
        camera?.let { runCatching { it.setPreviewCallback(null); it.stopPreview(); it.release() } }
        camera = null
    }
}
