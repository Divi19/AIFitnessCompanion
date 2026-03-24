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

    private val METHOD_CHANNEL   = "com.example.ai_fitness_app/quickpose"
    private val EVENT_CHANNEL    = "com.example.ai_fitness_app/quickpose_events"
    private val SESSION_CHANNEL  = "com.example.ai_fitness_app/quickpose_session"
    private val SDK_KEY          = "01KKNZJ3ZF08HF5HXP2Z1WEFNP"

    private var eventSink:   EventChannel.EventSink? = null
    private var sessionSink: EventChannel.EventSink? = null

    // ── Live frame results receiver ───────────────────────────────────────
    private val resultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getBooleanExtra("stop", false)) return
            val repCount = intent.getIntExtra(QuickPoseActivity.EXTRA_REP_COUNT, 0)
            val feedback = intent.getStringExtra(QuickPoseActivity.EXTRA_FEEDBACK) ?: ""
            val status   = intent.getStringExtra(QuickPoseActivity.EXTRA_STATUS)   ?: "loading"
            val isTimer  = intent.getBooleanExtra("isTimer", false)
            runOnUiThread {
                eventSink?.success(mapOf(
                    "repCount"      to repCount,
                    "feedback"      to feedback,
                    "status"        to status,
                    "isTimer"       to isTimer,
                    "exerciseState" to "",
                    "fps"           to 0
                ))
            }
        }
    }

    // ── Session summary receiver ──────────────────────────────────────────
    private val sessionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val exercise     = intent.getStringExtra(QuickPoseActivity.EXTRA_SESSION_EXERCISE) ?: return
            val reps         = intent.getIntExtra(QuickPoseActivity.EXTRA_SESSION_REPS, 0)
            val durationMs   = intent.getLongExtra(QuickPoseActivity.EXTRA_SESSION_DURATION_MS, 0L)
            val feedbackKeys = intent.getStringArrayExtra(QuickPoseActivity.EXTRA_SESSION_FEEDBACK_KEYS) ?: emptyArray()
            val feedbackVals = intent.getIntArrayExtra(QuickPoseActivity.EXTRA_SESSION_FEEDBACK_VALUES) ?: intArrayOf()

            // ── FIX: read avgJointAngle from the broadcast ────────────────
            // -1f is the sentinel meaning "no landmarks captured this session"
            // We pass it through as-is; QuickPoseService.dart normalises it to null
            val rawAngle     = intent.getFloatExtra(QuickPoseActivity.EXTRA_SESSION_AVG_ANGLE, -1f)
            val avgAngle: Double? = if (rawAngle >= 0f) rawAngle.toDouble() else null

            val feedbackMap  = feedbackKeys.zip(feedbackVals.toList()).toMap()

            println("=== MAIN: Session received — $exercise, $reps reps, ${durationMs}ms ===")
            println("=== MAIN: Feedback — $feedbackMap ===")
            println("=== MAIN: avgJointAngle — raw=$rawAngle stored=$avgAngle ===")

            runOnUiThread {
                sessionSink?.success(mapOf(
                    "exercise"       to exercise,
                    "reps"           to reps,
                    "durationMs"     to durationMs,
                    "feedbackMap"    to feedbackMap,
                    // ── FIX: was missing entirely — this is why the widget never appeared
                    "avgJointAngle"  to avgAngle
                ))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (QuickPoseHolder.quickPose == null) {
            QuickPoseHolder.quickPose = QuickPose(applicationContext, sdkKey = SDK_KEY)
        }

        // ── Live results EventChannel ─────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerReceiverCompat(resultReceiver, IntentFilter(QuickPoseActivity.ACTION_RESULT))
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    try { unregisterReceiver(resultReceiver) } catch (_: Exception) {}
                }
            })

        // ── Session summary EventChannel ──────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SESSION_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sessionSink = events
                    registerReceiverCompat(sessionReceiver, IntentFilter(QuickPoseActivity.ACTION_SESSION))
                }
                override fun onCancel(arguments: Any?) {
                    sessionSink = null
                    try { unregisterReceiver(sessionReceiver) } catch (_: Exception) {}
                }
            })

        // ── MethodChannel ─────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCamera" -> {
                        val exercise = call.argument<String>("exercise") ?: "squat"
                        startActivity(Intent(this, QuickPoseActivity::class.java).apply {
                            putExtra(QuickPoseActivity.EXTRA_EXERCISE, exercise)
                        })
                        result.success(null)
                    }
                    "switchExercise" -> {
                        val exercise = call.argument<String>("exercise") ?: "squat"
                        startActivity(Intent(this, QuickPoseActivity::class.java).apply {
                            putExtra(QuickPoseActivity.EXTRA_EXERCISE, exercise)
                            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }
                    "stopCamera" -> result.success(null)
                    else         -> result.notImplemented()
                }
            }
    }

    private fun registerReceiverCompat(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(resultReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(sessionReceiver) } catch (_: Exception) {}
        QuickPoseHolder.quickPose?.stop()
        QuickPoseHolder.quickPose = null
    }
}