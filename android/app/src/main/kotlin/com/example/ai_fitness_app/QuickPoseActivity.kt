package com.example.ai_fitness_app

import ai.quickpose.core.*
import ai.quickpose.camera.QuickPoseCameraSwitchView
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class QuickPoseActivity : ComponentActivity() {

    companion object {
        const val EXTRA_EXERCISE    = "exercise"
        const val ACTION_RESULT     = "com.example.ai_fitness_app.QUICKPOSE_RESULT"
        const val ACTION_SESSION    = "com.example.ai_fitness_app.QUICKPOSE_SESSION"
        const val EXTRA_REP_COUNT   = "rep_count"
        const val EXTRA_FEEDBACK    = "feedback"
        const val EXTRA_STATUS      = "status"

        // Session summary extras — broadcast when session ends
        const val EXTRA_SESSION_EXERCISE        = "session_exercise"
        const val EXTRA_SESSION_REPS            = "session_reps"
        const val EXTRA_SESSION_DURATION_MS     = "session_duration_ms"
        const val EXTRA_SESSION_FEEDBACK_KEYS   = "session_feedback_keys"
        const val EXTRA_SESSION_FEEDBACK_VALUES = "session_feedback_values"

        // Quality thresholds — sessions below these are silently discarded
        const val MIN_REPS        = 3
        const val MIN_DURATION_MS = 20_000L   // 20 seconds

        // Keywords that identify camera setup messages — filtered out of the
        // feedback map because they are positional instructions, not form corrections.
        // Using keyword matching so it works even if QuickPose changes exact wording.
        val SETUP_KEYWORDS = setOf(
            "back", "closer", "further", "forward", "camera",
            "centre", "center", "frame", "step", "move", "distance",
            "right", "left", "position", "align"
        )
    }

    private val quickPose get() = QuickPoseHolder.quickPose
        ?: throw IllegalStateException("QuickPose not initialised")

    private lateinit var cameraView: QuickPoseCameraSwitchView

    private val counter = QuickPoseThresholdCounter()
    private var currentExercise = "squat"

    // ── Session tracking ──────────────────────────────────────────────────
    private var sessionStartMs   = 0L
    private var latestRepCount   = 0
    // Feedback frequency map — key: feedback string, value: occurrence count
    private val feedbackFrequency = mutableMapOf<String, Int>()

    // Ghost rep guard
    private var lastRepTime = 0L

    private lateinit var repCountText:  TextView
    private lateinit var feedbackText:  TextView
    private lateinit var exerciseLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // setDecorFitsSystemWindows requires API 30+ — S9+ runs API 29
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        currentExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: "squat"
        cameraView = QuickPoseCameraSwitchView(this, quickPose)
        setContentView(buildUI())
    }

    private fun buildUI(): View {
        val root = FrameLayout(this)
        root.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        root.setBackgroundColor(Color.BLACK)

        root.addView(cameraView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Back button
        root.addView(ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            setPadding(24, 24, 24, 24)
            contentDescription = "Back"
            setOnClickListener { finishCleanly() }
        }, FrameLayout.LayoutParams(120, 120).apply {
            gravity = Gravity.TOP or Gravity.START
            topMargin = 80; leftMargin = 32
        })

        // Exercise label
        exerciseLabel = TextView(this).apply {
            text     = exerciseDisplayName(currentExercise)
            textSize = 14f
            setTextColor(Color.argb(200, 255, 255, 255))
            typeface = Typeface.DEFAULT_BOLD
            gravity  = Gravity.CENTER
            setBackgroundColor(Color.argb(120, 0, 0, 0))
            setPadding(32, 12, 32, 12)
        }
        root.addView(exerciseLabel, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; topMargin = 88 })

        // Rep counter
        val repContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
        }
        repCountText = TextView(this).apply {
            text = "0"; textSize = 96f
            setTextColor(Color.rgb(185, 255, 43))
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        }
        repContainer.addView(repCountText)
        repContainer.addView(TextView(this).apply {
            text = "reps"; textSize = 18f
            setTextColor(Color.argb(150, 255, 255, 255)); gravity = Gravity.CENTER
        })
        root.addView(repContainer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER })

        // Feedback banner
        feedbackText = TextView(this).apply {
            textSize = 14f; setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(200, 255, 94, 0))
            setPadding(32, 16, 32, 16); visibility = View.GONE
        }
        root.addView(feedbackText, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = 160; leftMargin = 48; rightMargin = 48
        })

        return root
    }

    override fun onResume() {
        super.onResume()
        resetSessionData()
        startQuickPose(currentExercise)
    }

    override fun onPause() {
        super.onPause()
        quickPose.stop()
        try { cameraView.stop() } catch (e: Exception) {}
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { finishCleanly() }

    private fun finishCleanly() {
        quickPose.stop()
        try { cameraView.stop() } catch (e: Exception) {}
        broadcastSessionIfValid()
        finish()
    }

    // ── Reset all session tracking data ──────────────────────────────────
    private fun resetSessionData() {
        sessionStartMs = System.currentTimeMillis()
        latestRepCount = 0
        feedbackFrequency.clear()
        lastRepTime    = 0L
        counter.reset()
    }

    // ── Check quality thresholds and broadcast session summary if valid ───
    private fun broadcastSessionIfValid() {
        val durationMs = System.currentTimeMillis() - sessionStartMs

        val meetsReps     = latestRepCount >= MIN_REPS
        val meetsDuration = durationMs     >= MIN_DURATION_MS

        println("=== SESSION END: reps=$latestRepCount, duration=${durationMs}ms ===")
        println("=== QUALITY CHECK: reps=$meetsReps, duration=$meetsDuration ===")

        if (!meetsReps || !meetsDuration) {
            println("=== SESSION DISCARDED: below quality threshold ===")
            return
        }

        // Flatten the feedback map into two parallel arrays for Intent extras
        // (Intent doesn't support Map directly)
        val feedbackKeys   = feedbackFrequency.keys.toTypedArray()
        val feedbackValues = feedbackFrequency.values.map { it }.toIntArray()

        println("=== SESSION SAVED: broadcasting to Flutter ===")

        sendBroadcast(Intent(ACTION_SESSION).apply {
            putExtra(EXTRA_SESSION_EXERCISE,        currentExercise)
            putExtra(EXTRA_SESSION_REPS,            latestRepCount)
            putExtra(EXTRA_SESSION_DURATION_MS,     durationMs)
            putExtra(EXTRA_SESSION_FEEDBACK_KEYS,   feedbackKeys)
            putExtra(EXTRA_SESSION_FEEDBACK_VALUES, feedbackValues)
            setPackage(packageName)
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val newExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: return
        if (newExercise != currentExercise) {
            // Save the current exercise session before switching
            quickPose.stop()
            broadcastSessionIfValid()

            currentExercise = newExercise
            runOnUiThread {
                repCountText.text       = "0"
                feedbackText.visibility = View.GONE
                exerciseLabel.text      = exerciseDisplayName(newExercise)
            }
            lifecycleScope.launch {
                resetSessionData()
                startQuickPose(newExercise)
            }
        }
    }

    private fun featureFor(name: String): Feature = when (name) {
        "squat"        -> Feature.Fitness(FitnessFeature.Squats)
        "pushup"       -> Feature.Fitness(FitnessFeature.PushUps)
        "bicep_curl"   -> Feature.Fitness(FitnessFeature.BicepCurls)
        "jumping_jack" -> Feature.Fitness(FitnessFeature.JumpingJacks)
        "lunge_left"   -> Feature.Fitness(FitnessFeature.Lunges(Side.LEFT))
        "lunge_right"  -> Feature.Fitness(FitnessFeature.Lunges(Side.RIGHT))
        "sit_up"       -> Feature.Fitness(FitnessFeature.SitUps)
        "plank"        -> Feature.Fitness(FitnessFeature.Plank)
        "glute_bridge" -> Feature.Fitness(FitnessFeature.GluteBridge)
        else           -> Feature.Fitness(FitnessFeature.Squats)
    }

    private fun exerciseDisplayName(name: String): String = when (name) {
        "squat"        -> "Squat"
        "pushup"       -> "Push Up"
        "bicep_curl"   -> "Bicep Curl"
        "jumping_jack" -> "Jumping Jack"
        "lunge_left"   -> "Left Lunge"
        "lunge_right"  -> "Right Lunge"
        "sit_up"       -> "Sit Up"
        "plank"        -> "Plank"
        "glute_bridge" -> "Glute Bridge"
        else           -> name
    }

    private fun startQuickPose(exerciseName: String) {
        lifecycleScope.launch {
            cameraView.start(useFrontCamera = true)

            quickPose.start(
                arrayOf(featureFor(exerciseName)),
                onFrame = { status, _, features, feedback, _ ->

                    // ── Rep counting with ghost rep guard ─────────────────
                    features?.forEach { (feature, result) ->
                        if (feature is Feature.Fitness) {
                            val counterState = counter.count(result.value)
                            val now = System.currentTimeMillis()
                            // Only accept a new rep if 500ms has passed since the last one
                            if (counterState.count > latestRepCount &&
                                (now - lastRepTime) > 500L) {
                                latestRepCount = counterState.count
                                lastRepTime    = now
                            }
                        }
                    }

                    // ── Feedback accumulation ─────────────────────────────
                    // Filter out camera setup messages — these are positional
                    // instructions (stand back, move closer etc.) not form
                    // corrections. They pollute the debrief with useless info.
                    val feedbackMsg = feedback?.values?.firstOrNull()?.displayString ?: ""
                    if (feedbackMsg.isNotEmpty()) {
                        val lowerMsg = feedbackMsg.lowercase()
                        val isSetupMessage = SETUP_KEYWORDS.any { lowerMsg.contains(it) }
                        if (!isSetupMessage) {
                            feedbackFrequency[feedbackMsg] =
                                (feedbackFrequency[feedbackMsg] ?: 0) + 1
                        }
                    }

                    val statusStr = if (status is Status.Success) "success" else "loading"

                    // ── Update UI ─────────────────────────────────────────
                    runOnUiThread {
                        repCountText.text = latestRepCount.toString()
                        if (feedbackMsg.isNotEmpty()) {
                            feedbackText.text       = feedbackMsg
                            feedbackText.visibility = View.VISIBLE
                        } else {
                            feedbackText.visibility = View.GONE
                        }
                    }

                    // ── Broadcast live results to Flutter ─────────────────
                    sendBroadcast(Intent(ACTION_RESULT).apply {
                        putExtra(EXTRA_REP_COUNT, latestRepCount)
                        putExtra(EXTRA_FEEDBACK,  feedbackMsg)
                        putExtra(EXTRA_STATUS,    statusStr)
                        setPackage(packageName)
                    })
                }
            )
        }
    }
}