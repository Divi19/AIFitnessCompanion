package com.example.ai_fitness_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Channel names — these must exactly match what you use in Dart
    private val METHOD_CHANNEL = "com.example.ai_fitness_app/quickpose"
    private val EVENT_CHANNEL  = "com.example.ai_fitness_app/quickpose_events"
    private val VIEW_TYPE      = "com.example.ai_fitness_app/quickpose_view"

    // Your QuickPose SDK key from dev.quickpose.ai
    private val SDK_KEY = "01KKNZJ3ZF08HF5HXP2Z1WEFNP"

    // Reference to the QuickPoseView so MethodChannel can call switchExercise
    private var quickPoseView: QuickPoseView? = null

    // EventChannel sink — holds the stream back to Flutter
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. EventChannel — streams rep count + feedback to Flutter ──────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // ── 2. Register the PlatformView for embedding camera in Flutter ───
        flutterEngine.platformViewsController.registry.registerViewFactory(
            VIEW_TYPE,
            QuickPoseViewFactory(
                lifecycleOwner = this,
                eventSink = eventSink,
                sdkKey = SDK_KEY
            )
        )

        // ── 3. MethodChannel — receives commands from Flutter ──────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "switchExercise" -> {
                        val exercise = call.argument<String>("exercise") ?: "squat"
                        quickPoseView?.switchExercise(exercise)
                        result.success(null)
                    }
                    "stopCamera" -> {
                        quickPoseView = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}