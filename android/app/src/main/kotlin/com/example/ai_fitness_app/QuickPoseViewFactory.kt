package com.example.ai_fitness_app

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class QuickPoseViewFactory(
    private val lifecycleOwner: LifecycleOwner,
    private val eventSink: EventChannel.EventSink?,
    private val sdkKey: String
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    // Flutter calls this when it needs to create the native view
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return QuickPoseView(
            context = context,
            lifecycleOwner = lifecycleOwner,
            eventSink = eventSink,
            sdkKey = sdkKey
        )
    }
}