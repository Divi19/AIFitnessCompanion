package com.example.ai_fitness_app

import ai.quickpose.core.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.example.ai_fitness_app/quickpose"
    private val EVENT_CHANNEL  = "com.example.ai_fitness_app/quickpose_events"
    private val SDK_KEY        = "01KKNZJ3ZF08HF5HXP2Z1WEFNP"

    private var eventSink: EventChannel.EventSink? = null

    private val resultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getBooleanExtra("stop", false)) return
            val repCount = intent.getIntExtra(QuickPoseActivity.EXTRA_REP_COUNT, 0)
            val feedback = intent.getStringExtra(QuickPoseActivity.EXTRA_FEEDBACK) ?: ""
            val status   = intent.getStringExtra(QuickPoseActivity.EXTRA_STATUS)   ?: "loading"
            
            runOnUiThread {
                eventSink?.success(mapOf(
                    "repCount"      to repCount,
                    "feedback"      to feedback,
                    "status"        to status,
                    "exerciseState" to "",
                    "fps"           to 0
                ))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Initialize the heavy AI engine ONCE using the Application Context
        // This keeps the model hot in memory without touching the physical camera
        if (QuickPoseHolder.quickPose == null) {
            QuickPoseHolder.quickPose = QuickPose(applicationContext, sdkKey = SDK_KEY)
        }

        // 2. EventChannel setup (Receives broadcasts from QuickPoseActivity)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    val filter = IntentFilter(QuickPoseActivity.ACTION_RESULT)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(resultReceiver, filter, RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(resultReceiver, filter)
                    }
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    try { unregisterReceiver(resultReceiver) } catch (_: Exception) {}
                }
            })

        // 3. MethodChannel setup (Commands from Flutter to open the Native UI)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCamera" -> {
                        val exercise = call.argument<String>("exercise") ?: "squat"
                        val intent = Intent(this, QuickPoseActivity::class.java).apply {
                            putExtra(QuickPoseActivity.EXTRA_EXERCISE, exercise)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "switchExercise" -> {
                        val exercise = call.argument<String>("exercise") ?: "squat"
                        val intent = Intent(this, QuickPoseActivity::class.java).apply {
                            putExtra(QuickPoseActivity.EXTRA_EXERCISE, exercise)
                            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "stopCamera" -> { result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(resultReceiver) } catch (_: Exception) {}
        QuickPoseHolder.quickPose?.stop()
        QuickPoseHolder.quickPose  = null
    }
}