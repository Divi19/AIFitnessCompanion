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
        const val EXTRA_EXERCISE            = "exercise"
        const val ACTION_RESULT             = "com.example.ai_fitness_app.QUICKPOSE_RESULT"
        const val ACTION_SESSION            = "com.example.ai_fitness_app.QUICKPOSE_SESSION"
        const val EXTRA_REP_COUNT           = "rep_count"
        const val EXTRA_FEEDBACK            = "feedback"
        const val EXTRA_STATUS              = "status"
        const val EXTRA_SESSION_EXERCISE    = "session_exercise"
        const val EXTRA_SESSION_REPS        = "session_reps"
        const val EXTRA_SESSION_DURATION_MS = "session_duration_ms"
        const val EXTRA_SESSION_FEEDBACK_KEYS   = "session_feedback_keys"
        const val EXTRA_SESSION_FEEDBACK_VALUES = "session_feedback_values"
        const val EXTRA_SESSION_AVG_ANGLE   = "session_avg_joint_angle"

        const val MIN_REPS        = 3
        const val MIN_DURATION_MS = 20_000L

        val SETUP_KEYWORDS = setOf(
            "back", "closer", "further", "forward", "camera",
            "centre", "center", "frame", "step", "move", "distance",
            "right", "left", "position", "align"
        )

        const val FORM_FEEDBACK_WINDOW = 25

        const val LM_LEFT_SHOULDER  = 11
        const val LM_RIGHT_SHOULDER = 12
        const val LM_LEFT_ELBOW     = 13
        const val LM_RIGHT_ELBOW    = 14
        const val LM_LEFT_WRIST     = 15
        const val LM_RIGHT_WRIST    = 16
        const val LM_LEFT_HIP       = 23
        const val LM_RIGHT_HIP      = 24
        const val LM_LEFT_KNEE      = 25
        const val LM_RIGHT_KNEE     = 26
        const val LM_LEFT_ANKLE     = 27
        const val LM_RIGHT_ANKLE    = 28
        const val LM_LEFT_TOE       = 31
        const val LM_RIGHT_TOE      = 32
    }

    // ── QuickPose ─────────────────────────────────────────────────────────────
    private val quickPose get() = QuickPoseHolder.quickPose
        ?: throw IllegalStateException("QuickPose not initialised")
    private lateinit var cameraView: QuickPoseCameraSwitchView

    // ── Exercise configuration ────────────────────────────────────────────────
    // Each exercise has its own signal thresholds tuned to how QuickPose
    // reports that exercise's range of motion.
    //
    // isInverted = true means the signal is HIGH at the working position
    // and LOW at the resting position. This is opposite to squat/pushup
    // where signal is LOW at the bottom (working) position.
    //
    // bottomThreshold — signal value that confirms the working position reached
    // topThreshold    — signal value that confirms the resting position reached
    // midThreshold    — signal value used to detect leaving the working position
    // minIntervalMs   — minimum ms between reps (prevents rapid false counts)
    data class ExerciseConfig(
        val bottomThreshold : Float,
        val topThreshold    : Float,
        val midThreshold    : Float,
        val minIntervalMs   : Long,
        val isInverted      : Boolean,
        // Minimum consecutive frames signal must stay at depth
        // before depth is confirmed. Prevents noise from triggering.
        val minDepthFrames   : Int = 3
    )

    // Signal directions confirmed against QuickPose documentation:
    // Normal  (signal LOW at bottom): squat, pushup, lunge, jumping jack
    // Inverted (signal HIGH at work): bicep_curl, sit_up, glute_bridge
    //
    // Jumping jacks have a shorter minIntervalMs because it is a fast exercise.
    // Bicep curl, sit up and glute bridge thresholds marked with TODO —
    // verify with debug prints on first test run and adjust if needed.
    private val exerciseConfigs = mapOf(
        "squat" to ExerciseConfig(
            bottomThreshold   = 0.20f, // Stricter — must go deeper
            topThreshold      = 0.78f,
            midThreshold      = 0.45f,
            minIntervalMs     = 700L,
            isInverted        = false,
            minDepthFrames    = 4
        ),
        "pushup" to ExerciseConfig(
            bottomThreshold   = 0.20f,
            topThreshold      = 0.78f,
            midThreshold      = 0.45f,
            minIntervalMs     = 600L,
            isInverted        = false,
            minDepthFrames    = 3
        ),
        "lunge_left" to ExerciseConfig(
            bottomThreshold   = 0.20f,
            topThreshold      = 0.78f,
            midThreshold      = 0.45f,
            minIntervalMs     = 700L,
            isInverted        = false,
            minDepthFrames    = 3
        ),
        "lunge_right" to ExerciseConfig(
            bottomThreshold   = 0.20f,
            topThreshold      = 0.78f,
            midThreshold      = 0.45f,
            minIntervalMs     = 700L,
            isInverted        = false,
            minDepthFrames    = 3
        ),
        "jumping_jack" to ExerciseConfig(
            bottomThreshold   = 0.20f,
            topThreshold      = 0.78f,
            midThreshold      = 0.45f,
            minIntervalMs     = 350L, // Fast exercise
            isInverted        = false,
            minDepthFrames    = 2
        ),
        "bicep_curl" to ExerciseConfig(
            bottomThreshold   = 0.78f, // HIGH = fully curled
            topThreshold      = 0.22f, // LOW  = fully extended
            midThreshold      = 0.55f,
            minIntervalMs     = 500L,
            isInverted        = true,
            minDepthFrames    = 3
        ),
        "sit_up" to ExerciseConfig(
            bottomThreshold   = 0.78f,
            topThreshold      = 0.22f,
            midThreshold      = 0.55f,
            minIntervalMs     = 600L,
            isInverted        = true,
            minDepthFrames    = 3
        ),
        "glute_bridge" to ExerciseConfig(
            bottomThreshold   = 0.78f,
            topThreshold      = 0.22f,
            midThreshold      = 0.55f,
            minIntervalMs     = 500L,
            isInverted        = true,
            minDepthFrames    = 3
        ),
    )

    // ── Rep counting state machine ────────────────────────────────────────────
    enum class RepState {
        WAITING_FOR_BOTTOM, // Waiting for user to reach working position
        AT_BOTTOM,          // User is at working position (proper depth)
        RETURNING_TO_TOP    // User is returning to resting position
    }

    private var repState           = RepState.WAITING_FOR_BOTTOM
    private var confirmedRepCount  = 0
    private var reachedProperDepth = false
    private var lastRepTimestamp   = 0L
    
    // Consecutive frames signal has stayed at proper depth
    // Must reach minDepthFrames before depth is confirmed
    private var depthFrameCount    = 0
    // Consecutive frames signal has stayed at top position
    // Prevents noise from briefly touching topThreshold
    private var topFrameCount      = 0


    // ── State ─────────────────────────────────────────────────────────────────
    private var currentExercise         = "squat"
    private var lastBroadcastedRepCount = 0
    private var lastBroadcastedFeedback = ""
    private var isAtProperDepth         = false

    // ── Timer (plank only) ────────────────────────────────────────────────────
    private var timerJob       : kotlinx.coroutines.Job? = null
    private var elapsedSeconds = 0
    private val timerExercises = setOf("plank")

    private var isAtProperDepth = false
    private val DEPTH_THRESHOLD = 0.15f

    private var sessionStartMs       = 0L
    private var latestRepCount       = 0
    private val feedbackFrequency    = mutableMapOf<String, Int>()
    private var lastRepTime          = 0L
    private var formFeedbackCooldown = 0
    private var prevCounterValue     = 0f
    // Guard flag — ensures the session broadcast fires at most once per session
    private var sessionBroadcasted   = false

    private val jointAngles = mutableListOf<Float>()
    private var repAngleCaptured = false
    private var currentRepMinAngle: Float? = null

    private lateinit var repCountText:  TextView
    private lateinit var feedbackText:  TextView
    private lateinit var exerciseLabel: TextView
    private lateinit var repContainer:  LinearLayout

    data class LM(val x: Float, val y: Float, val z: Float, val visibility: Float)

    private fun extractLM(obj: Any?): LM? {
        if (obj == null) return null
        return try {
            val cls = obj.javaClass
            fun getFloat(name: String): Float? = try {
                cls.getField(name).getFloat(obj)
            } catch (_: Exception) { try {
                val getter = "get${name.replaceFirstChar { it.uppercase() }}"
                cls.getMethod(getter).invoke(obj) as? Float
            } catch (_: Exception) { null } }

            val x = getFloat("x") ?: return null
            val y = getFloat("y") ?: return null
            val z = getFloat("z") ?: 0f
            val v = getFloat("visibility") ?: 1f
            LM(x, y, z, v)
        } catch (_: Exception) { null }
    }

    private fun lm(list: List<*>, index: Int): LM? {
        if (index >= list.size) return null
        val raw = extractLM(list[index]) ?: return null
        return if (raw.visibility < 0.7f) null else raw
    }

    private fun getPoseLandmarks(landmarks: Any?): List<*> {
        if (landmarks == null) return emptyList<Any>()
        return try {
            @Suppress("UNCHECKED_CAST")
            landmarks.javaClass.getMethod("getPoseLandmarks").invoke(landmarks) as? List<*>
                ?: emptyList<Any>()
        } catch (_: Exception) { emptyList<Any>() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)

        currentExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: "squat"
        cameraView      = QuickPoseCameraSwitchView(this, quickPose)
        setContentView(buildUI())
    }

    private fun buildUI(): View {
        val root = FrameLayout(this)
        root.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        root.setBackgroundColor(Color.BLACK)

        val cameraParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        root.addView(cameraView, cameraParams)

        val backBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            setPadding(24, 24, 24, 24)
            contentDescription = "Back"
            setOnClickListener { finishCleanly() }
        }
        val backParams = FrameLayout.LayoutParams(120, 120).apply {
            gravity = Gravity.TOP or Gravity.START
            topMargin = 80
            leftMargin = 32
        }
        root.addView(backBtn, backParams)

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

        repContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
        }
        repCountText = TextView(this).apply {
            text = "0"; textSize = 96f
            setTextColor(Color.rgb(185, 255, 43))
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        }
        repContainer.addView(repCountText)

        val unitLabel = TextView(this).apply {
            text = if (isTimerExercise(currentExercise)) "seconds" else "reps"
            textSize = 18f
            setTextColor(Color.argb(150, 255, 255, 255))
            gravity = Gravity.CENTER
            tag = "unit_label"
        }
        repContainer.addView(unitLabel)

        root.addView(repContainer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER })

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
        // ── FIX: broadcast BEFORE stopping so latestRepCount is still valid ──
        broadcastSessionIfValid()
        stopTimer()
        quickPose.stop()
        try { cameraView.stop() } catch (_: Exception) {}
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { finishCleanly() }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val newExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: return
        if (newExercise == currentExercise) return

        // Stop current session cleanly before switching
        quickPose.stop()
        stopTimer()
        broadcastSessionIfValid()

        currentExercise         = newExercise
        lastBroadcastedRepCount = 0
        lastBroadcastedFeedback = ""
        isAtProperDepth         = false
        depthFrameCount = 0
        topFrameCount   = 0

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

    // ─────────────────────────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildUI(): View {
        val root = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.BLACK)
        }

        // Camera preview — fills entire screen
        root.addView(cameraView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Back button
        val backBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            setPadding(24, 24, 24, 24)
            contentDescription = "Back"
            setOnClickListener { finishCleanly() }
        }
        root.addView(backBtn, FrameLayout.LayoutParams(120, 120).apply {
            gravity    = Gravity.TOP or Gravity.START
            topMargin  = 80
            leftMargin = 32
        })

        // Exercise name label
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
        ).apply {
            gravity   = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = 88
        })

        // Rep counter — shows rep number or countdown timer
        repContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity     = Gravity.CENTER
        }
        repCountText = TextView(this).apply {
            text     = "0"
            textSize = 96f
            setTextColor(Color.rgb(185, 255, 43))
            typeface = Typeface.DEFAULT_BOLD
            gravity  = Gravity.CENTER
        }
        repContainer.addView(repCountText)
        repContainer.addView(TextView(this).apply {
            text     = if (isTimerExercise(currentExercise)) "seconds" else "reps"
            textSize = 18f
            setTextColor(Color.argb(150, 255, 255, 255))
            gravity  = Gravity.CENTER
            tag      = "unit_label"
        })
        root.addView(repContainer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER })

        // Feedback banner — shows form tips and encouragement
        feedbackText = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.WHITE)
            typeface   = Typeface.DEFAULT_BOLD
            gravity    = Gravity.CENTER
            setPadding(32, 16, 32, 16)
            visibility = View.GONE
        }
        root.addView(feedbackText, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity      = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            bottomMargin = 160
            leftMargin   = 48
            rightMargin  = 48
        })

        return root
    }

    // ─────────────────────────────────────────────────────────────────────────
    // QuickPose
    // ─────────────────────────────────────────────────────────────────────────

    private fun startQuickPose(exerciseName: String) {
        lifecycleScope.launch {
            cameraView.start(useFrontCamera = true)

            // Greet the user when workout begins
            val startMsg = "Let's begin, you got this!"
            runOnUiThread {
                showTemporaryFeedback(startMsg, Color.argb(200, 0, 150, 80))
            }
            broadcastAudioMessage(startMsg)

            if (isTimerExercise(exerciseName)) {
                startTimerExercise(exerciseName)
            } else {
                startRepExercise(exerciseName)
            }
        }
    }

    // Handles timer-based exercises (plank).
    // QuickPose still runs for form feedback display —
    // the timer runs independently via a coroutine.
    private fun startTimerExercise(exerciseName: String) {
        startTimer()

        quickPose.start(
            arrayOf(featureFor(exerciseName)),
            onFrame = { _, _, _, feedback, _ ->
                val msg = feedback?.values?.firstOrNull()?.displayString ?: ""
                if (msg != lastBroadcastedFeedback) {
                    lastBroadcastedFeedback = msg
                    runOnUiThread {
                        if (msg.isNotEmpty()) {
                            feedbackText.setBackgroundColor(
                                Color.argb(200, 255, 94, 0)
                            )
                            feedbackText.text       = msg
                            feedbackText.visibility = View.VISIBLE
                        } else {
                            feedbackText.visibility = View.GONE
                        }
                    }
                }
            }
        )
    }

    // Handles rep-based exercises.
    // QuickPose provides result.value (0-1 signal) which our state
    // machine uses to count reps. QuickPose feedback is shown as
    // advisory guidance only — it does NOT block counting because
    // QuickPose fires messages too aggressively on some phrases.
    private fun startRepExercise(exerciseName: String) {
        val config = exerciseConfigs[exerciseName]
            ?: exerciseConfigs["squat"]!!

        quickPose.start(
            arrayOf(featureFor(exerciseName)),
            onFrame = { status, _, features, feedback, _ ->

                val statusStr = if (status is Status.Success) "success" else "loading"

                // ── Advisory form feedback from QuickPose ─────────────
                // Displayed to user but never used to block rep counting.
                // QuickPose's internal thresholds are strict and fire on
                // minor form deviations that don't warrant blocking a rep.
                val feedbackMsg =
                    feedback?.values?.firstOrNull()?.displayString ?: ""

                if (feedbackMsg != lastBroadcastedFeedback) {
                    lastBroadcastedFeedback = feedbackMsg
                    if (feedbackMsg.isNotEmpty()) {
                        feedbackFrequency[feedbackMsg] =
                            (feedbackFrequency[feedbackMsg] ?: 0) + 1
                    }
                    runOnUiThread {
                        if (feedbackMsg.isNotEmpty()) {
                            feedbackText.setBackgroundColor(
                                Color.argb(200, 255, 94, 0) // Orange advisory
                            )
                            feedbackText.text       = feedbackMsg
                            feedbackText.visibility = View.VISIBLE
                        } else {
                            feedbackText.visibility = View.GONE
                        }
                    }
                }

                // ── Rep counting via state machine ────────────────────
                if (features != null && features.isNotEmpty()) {
                    features.forEach { (feature, result) ->
                        if (feature is Feature.Fitness &&
                            result.value != null) {

                            val signal = result.value
                            val now    = System.currentTimeMillis()

                            // Debug print remove after verifying thresholds
                            println("=== $exerciseName | signal=$signal | state=$repState | depthFrames=$depthFrameCount ===")

                            isAtProperDepth = if (config.isInverted)
                                signal >= config.bottomThreshold
                            else
                                signal <= config.bottomThreshold

                        processRepStateMachine(signal, config, now)
                                                }
                    }
                }

                // Single broadcast per frame
                sendBroadcast(Intent(ACTION_RESULT).apply {
                    putExtra(EXTRA_REP_COUNT,   lastBroadcastedRepCount)
                    putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
                    putExtra(EXTRA_STATUS,      statusStr)
                    putExtra("isAtProperDepth", isAtProperDepth)
                    putExtra("isTimer",         false)
                    setPackage(packageName)
                })
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State machine
    // ─────────────────────────────────────────────────────────────────────────

    // Processes one frame of signal data through the rep counting state machine.
    //
    // The machine has three states:
    //   WAITING_FOR_BOTTOM — user at rest, waiting to start movement
    //   AT_BOTTOM          — user reached proper working depth
    //   RETURNING_TO_TOP   — user returning to rest position
    //
    // A rep is only counted when all three conditions are met:
    //   1. Signal reached proper depth (bottomThreshold)
    //   2. Signal returned to resting position (topThreshold)
    //   3. Minimum time between reps has elapsed (minIntervalMs)
        private fun processRepStateMachine(
            signal    : Float,
            config    : ExerciseConfig,
            now       : Long
        ) {
        
            when (repState) {

                RepState.WAITING_FOR_BOTTOM -> {
                    val atBottom = if (config.isInverted)
                        signal >= config.bottomThreshold
                    else
                        signal <= config.bottomThreshold

                    if (atBottom) {
                        depthFrameCount++
                        // Only confirm depth after minimum consecutive frames
                        // This prevents a single noisy frame from triggering
                        if (depthFrameCount >= config.minDepthFrames) {
                            repState           = RepState.AT_BOTTOM
                            reachedProperDepth = true
                            depthFrameCount    = 0
                        }
                    } else {
                        // Signal left the bottom zone — reset frame counter
                        depthFrameCount = 0
                    }

                    runOnUiThread {
                        repCountText.setTextColor(
                            if (isAtProperDepth && depthFrameCount > 0)
                                Color.rgb(185, 255, 43)
                            else
                                Color.rgb(255, 255, 255)
                        )
                    }
                }

                RepState.AT_BOTTOM -> {
                    val leftBottom = if (config.isInverted)
                        signal <= config.midThreshold
                    else
                        signal >= config.midThreshold

                    if (leftBottom) {
                        repState      = RepState.RETURNING_TO_TOP
                        topFrameCount = 0
                    }

                    runOnUiThread {
                        repCountText.setTextColor(Color.rgb(185, 255, 43))
                    }
                }

                RepState.RETURNING_TO_TOP -> {
                    val atTop = if (config.isInverted)
                        signal <= config.topThreshold
                    else
                        signal >= config.topThreshold

                    if (atTop) {
                        topFrameCount++

                        // Require 2 consecutive frames at top before committing
                     if (topFrameCount >= 2) {
                        val timeSinceLast = now - lastRepTimestamp

                        if (reachedProperDepth &&
                            timeSinceLast >= config.minIntervalMs) {
                            // ── Valid full rep ────────────────────────────
                            confirmedRepCount++
                            lastRepTimestamp        = now
                            lastBroadcastedRepCount = confirmedRepCount
                            latestRepCount          = confirmedRepCount

                            runOnUiThread {
                                repCountText.text = confirmedRepCount.toString()
                                repCountText.setTextColor(Color.rgb(185, 255, 43))
                            }

                            if (confirmedRepCount % 5 == 0) {
                                val msg = "Great work! $confirmedRepCount reps!"
                                runOnUiThread {
                                    showTemporaryFeedback(
                                        msg,
                                        Color.argb(200, 0, 180, 80)
                                    )
                                }
                                broadcastAudioMessage(msg)
                            }

                        } else if (!reachedProperDepth) {
                            // ── Half rep ─────────────────────────────────
                            val halfRepMsg = "Keep going, deeper for a full rep"
                            runOnUiThread {
                                showTemporaryFeedback(
                                    halfRepMsg,
                                    Color.argb(200, 255, 94, 0)
                                )
                            }
                            broadcastAudioMessage(halfRepMsg)
                        }

                        // Reset for next rep
                        repState           = RepState.WAITING_FOR_BOTTOM
                        reachedProperDepth = false
                        depthFrameCount    = 0
                        topFrameCount      = 0
                    }
                    } else {
                        topFrameCount = 0

                        // Check if user went back down
                        val wentBackDown = if (config.isInverted)
                            signal >= config.bottomThreshold
                        else
                            signal <= config.bottomThreshold

                        if (wentBackDown) {
                            repState           = RepState.AT_BOTTOM
                            reachedProperDepth = true
                            depthFrameCount    = 0
                        }
                    }

                    runOnUiThread {
                        repCountText.setTextColor(
                            if (isAtProperDepth)
                                Color.rgb(185, 255, 43)
                            else
                                Color.rgb(255, 255, 255)
                        )
                    }
                }
            }
        }
    // ─────────────────────────────────────────────────────────────────────────
    // Timer (plank)
    // ─────────────────────────────────────────────────────────────────────────

    private fun startTimer() {
        stopTimer()
        elapsedSeconds = 0

        timerJob = lifecycleScope.launch {
            // 10 second setup countdown — user gets into position
            for (i in 10 downTo 1) {
                runOnUiThread {
                    repCountText.text = i.toString()
                    repCountText.setTextColor(Color.rgb(255, 255, 255))
                    repContainer
                        .findViewWithTag<TextView>("unit_label")
                        ?.text = "get ready..."
                }
                kotlinx.coroutines.delay(1000)
            }

            // Switch label to "seconds" and start counting
            runOnUiThread {
                repContainer
                    .findViewWithTag<TextView>("unit_label")
                    ?.text = "seconds"
            }

            while (true) {
                runOnUiThread {
                    repCountText.text = elapsedSeconds.toString()
                    repCountText.setTextColor(Color.rgb(185, 255, 43))
                }
                sendBroadcast(Intent(ACTION_RESULT).apply {
                    putExtra(EXTRA_REP_COUNT,   elapsedSeconds)
                    putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
                    putExtra(EXTRA_STATUS,      "success")
                    putExtra("isAtProperDepth", true)
                    putExtra("isTimer",         true)
                    setPackage(packageName)
                })
                kotlinx.coroutines.delay(1000)
                elapsedSeconds++
            }
        }
    }

    private fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Session
    // ─────────────────────────────────────────────────────────────────────────

    private fun resetSessionData() {
        sessionStartMs     = System.currentTimeMillis()
        latestRepCount     = 0
        confirmedRepCount  = 0
        reachedProperDepth = false
        lastRepTimestamp   = 0L
        depthFrameCount    = 0
        topFrameCount      = 0
        repState           = RepState.WAITING_FOR_BOTTOM
        feedbackFrequency.clear()
        lastRepTime          = 0L
        formFeedbackCooldown = 0
        prevCounterValue     = 0f
        lastBroadcastedRepCount = 0
        sessionBroadcasted   = false
        counter.reset()
        jointAngles.clear()
        repAngleCaptured = false
        currentRepMinAngle = null
    }

    private fun broadcastSessionIfValid() {
        // Guard: only ever broadcast once per session
        if (sessionBroadcasted) return
        
        val durationMs    = System.currentTimeMillis() - sessionStartMs
        val meetsReps     = latestRepCount >= MIN_REPS
        val meetsDuration = durationMs     >= MIN_DURATION_MS

        println("=== SESSION END: reps=$latestRepCount, duration=${durationMs}ms ===")
        println("=== QUALITY CHECK: reps=$meetsReps, duration=$meetsDuration ===")

        if (!meetsReps || !meetsDuration) {
            println("=== SESSION DISCARDED: below quality threshold ===")
            return
        }

        val avgAngle = if (jointAngles.isNotEmpty())
            jointAngles.sum() / jointAngles.size
        else -1f

        println("=== SESSION ANGLES: samples=${jointAngles.size}, avg=${avgAngle}° ===")

        val feedbackKeys   = feedbackFrequency.keys.toTypedArray()
        val feedbackValues = feedbackFrequency.values.map { it }.toIntArray()
        println("=== SESSION SAVED: broadcasting to Flutter ===")
        sessionBroadcasted = true
        if (!meetsReps || !meetsDuration) return

        sendBroadcast(Intent(ACTION_SESSION).apply {
            putExtra(EXTRA_SESSION_EXERCISE,        currentExercise)
            putExtra(EXTRA_SESSION_REPS,            latestRepCount)
            putExtra(EXTRA_SESSION_DURATION_MS,     durationMs)
            putExtra(EXTRA_SESSION_FEEDBACK_KEYS,
                feedbackFrequency.keys.toTypedArray())
            putExtra(EXTRA_SESSION_FEEDBACK_VALUES,
                feedbackFrequency.values.toIntArray())
            setPackage(packageName)
        })
    }

    private fun finishCleanly() {
        quickPose.stop()
        try { cameraView.stop() } catch (_: Exception) {}
        broadcastSessionIfValid()
        finish()
    }

    // ── 3D angle calculation ──────────────────────────────────────────────
    // Uses full X/Y/Z coordinates so the angle is correct regardless of
    // whether the user faces the camera straight-on or at an angle.
    // MediaPipe provides Z as a depth estimate from a monocular camera —
    // less precise than X/Y but far better than ignoring it entirely.
    private fun angleDeg(
        ax: Float, ay: Float, az: Float,
        bx: Float, by: Float, bz: Float,
        cx: Float, cy: Float, cz: Float
    ): Float {
        val zScale = 3.0f
        val abx = ax - bx; val aby = ay - by; val abz = (az - bz) * zScale
        val cbx = cx - bx; val cby = cy - by; val cbz = (cz - bz) * zScale
        val dot  = abx * cbx + aby * cby + abz * cbz
        val magA = sqrt(abx * abx + aby * aby + abz * abz)
        val magC = sqrt(cbx * cbx + cby * cby + cbz * cbz)
        if (magA == 0f || magC == 0f) return 180f
        return Math.toDegrees(
            acos((dot / (magA * magC)).toDouble().coerceIn(-1.0, 1.0))
        ).toFloat()
    }

    private fun captureRepAngle(exercise: String, p: List<*>): Float? {
        if (p.isEmpty()) return null
        return when (exercise) {
            "squat" -> {
                val lHip   = lm(p, LM_LEFT_HIP)    ?: return null
                val lKnee  = lm(p, LM_LEFT_KNEE)   ?: return null
                val lAnkle = lm(p, LM_LEFT_ANKLE)  ?: return null
                val rHip   = lm(p, LM_RIGHT_HIP)   ?: return null
                val rKnee  = lm(p, LM_RIGHT_KNEE)  ?: return null
                val rAnkle = lm(p, LM_RIGHT_ANKLE) ?: return null
                val left  = angleDeg(lHip.x, lHip.y, lHip.z, lKnee.x, lKnee.y, lKnee.z, lAnkle.x, lAnkle.y, lAnkle.z)
                val right = angleDeg(rHip.x, rHip.y, rHip.z, rKnee.x, rKnee.y, rKnee.z, rAnkle.x, rAnkle.y, rAnkle.z)
                (left + right) / 2f
            }
            "pushup" -> {
                val lShoulder = lm(p, LM_LEFT_SHOULDER)  ?: return null
                val lElbow    = lm(p, LM_LEFT_ELBOW)     ?: return null
                val lWrist    = lm(p, LM_LEFT_WRIST)     ?: return null
                val rShoulder = lm(p, LM_RIGHT_SHOULDER) ?: return null
                val rElbow    = lm(p, LM_RIGHT_ELBOW)    ?: return null
                val rWrist    = lm(p, LM_RIGHT_WRIST)    ?: return null
                val left  = angleDeg(lShoulder.x, lShoulder.y, lShoulder.z, lElbow.x, lElbow.y, lElbow.z, lWrist.x, lWrist.y, lWrist.z)
                val right = angleDeg(rShoulder.x, rShoulder.y, rShoulder.z, rElbow.x, rElbow.y, rElbow.z, rWrist.x, rWrist.y, rWrist.z)
                (left + right) / 2f
            }
            "lunge_left" -> {
                val hip   = lm(p, LM_LEFT_HIP)   ?: return null
                val knee  = lm(p, LM_LEFT_KNEE)  ?: return null
                val ankle = lm(p, LM_LEFT_ANKLE) ?: return null
                angleDeg(hip.x, hip.y, hip.z, knee.x, knee.y, knee.z, ankle.x, ankle.y, ankle.z)
            }
            "lunge_right" -> {
                val hip   = lm(p, LM_RIGHT_HIP)   ?: return null
                val knee  = lm(p, LM_RIGHT_KNEE)  ?: return null
                val ankle = lm(p, LM_RIGHT_ANKLE) ?: return null
                angleDeg(hip.x, hip.y, hip.z, knee.x, knee.y, knee.z, ankle.x, ankle.y, ankle.z)
            }
            else -> null
        }
    }

    private fun checkDepthAtRepCompletion(exercise: String, p: List<*>): String? {
        if (p.isEmpty()) return null
        return when (exercise) {
            "squat"                     -> checkSquatDepth(p)
            "lunge_left", "lunge_right" -> checkLungeDepth(p, exercise)
            "pushup"                    -> checkPushupDepth(p)
            else                        -> null
        }
    }

    private fun checkSquatDepth(p: List<*>): String? {
        val lHip   = lm(p, LM_LEFT_HIP)    ?: return null
        val lKnee  = lm(p, LM_LEFT_KNEE)   ?: return null
        val lAnkle = lm(p, LM_LEFT_ANKLE)  ?: return null
        val rHip   = lm(p, LM_RIGHT_HIP)   ?: return null
        val rKnee  = lm(p, LM_RIGHT_KNEE)  ?: return null
        val rAnkle = lm(p, LM_RIGHT_ANKLE) ?: return null

        val leftAngle  = angleDeg(lHip.x, lHip.y, lHip.z, lKnee.x, lKnee.y, lKnee.z, lAnkle.x, lAnkle.y, lAnkle.z)
        val rightAngle = angleDeg(rHip.x, rHip.y, rHip.z, rKnee.x, rKnee.y, rKnee.z, rAnkle.x, rAnkle.y, rAnkle.z)
        val avgAngle   = (leftAngle + rightAngle) / 2f
        println("=== SQUAT DEPTH: kneeAngle=$avgAngle ===")
        return if (avgAngle > 110f) "Go deeper — hips below knees" else null
    }

    private fun checkLungeDepth(p: List<*>, exercise: String): String? {
        val isLeft  = exercise == "lunge_left"
        val hip     = lm(p, if (isLeft) LM_LEFT_HIP   else LM_RIGHT_HIP)   ?: return null
        val knee    = lm(p, if (isLeft) LM_LEFT_KNEE  else LM_RIGHT_KNEE)  ?: return null
        val ankle   = lm(p, if (isLeft) LM_LEFT_ANKLE else LM_RIGHT_ANKLE) ?: return null
        val toe     = lm(p, if (isLeft) LM_LEFT_TOE   else LM_RIGHT_TOE)   ?: return null

        val kneeAngle = angleDeg(hip.x, hip.y, hip.z, knee.x, knee.y, knee.z, ankle.x, ankle.y, ankle.z)
        if (kneeAngle > 120f) return "Lunge deeper — front knee to 90 degrees"
        if (abs(knee.x - toe.x) > 0.08f) return "Keep your front knee behind your toes"
        return null
    }

    private fun checkPushupDepth(p: List<*>): String? {
        val lShoulder = lm(p, LM_LEFT_SHOULDER)  ?: return null
        val lElbow    = lm(p, LM_LEFT_ELBOW)     ?: return null
        val lWrist    = lm(p, LM_LEFT_WRIST)     ?: return null
        val rShoulder = lm(p, LM_RIGHT_SHOULDER) ?: return null
        val rElbow    = lm(p, LM_RIGHT_ELBOW)    ?: return null
        val rWrist    = lm(p, LM_RIGHT_WRIST)    ?: return null

        val leftAngle  = angleDeg(lShoulder.x, lShoulder.y, lShoulder.z, lElbow.x, lElbow.y, lElbow.z, lWrist.x, lWrist.y, lWrist.z)
        val rightAngle = angleDeg(rShoulder.x, rShoulder.y, rShoulder.z, rElbow.x, rElbow.y, rElbow.z, rWrist.x, rWrist.y, rWrist.z)
        val avgAngle   = (leftAngle + rightAngle) / 2f
        println("=== PUSHUP DEPTH: elbowAngle=$avgAngle ===")
        return if (avgAngle > 120f) "Go lower — chest closer to the ground" else null
    }

    private fun checkLiveForm(exercise: String, p: List<*>, counterValue: Float): String? {
        if (p.isEmpty() || counterValue < 0.3f) return null
        return when (exercise) {
            "bicep_curl"                -> checkBicepElbowRaising(p)
            "lunge_left", "lunge_right" -> checkLungeKneeLive(p, exercise)
            else                        -> null
        }
    }

    private fun checkBicepElbowRaising(p: List<*>): String? {
        val lShoulder = lm(p, LM_LEFT_SHOULDER)  ?: return null
        val rShoulder = lm(p, LM_RIGHT_SHOULDER) ?: return null
        val lElbow    = lm(p, LM_LEFT_ELBOW)     ?: return null
        val rElbow    = lm(p, LM_RIGHT_ELBOW)    ?: return null

        val leftRaise  = lShoulder.y - lElbow.y
        val rightRaise = rShoulder.y - rElbow.y
        val maxRaise   = maxOf(leftRaise, rightRaise)
        return if (maxRaise > 0.08f) "Keep elbows tucked — don't raise them" else null
    }

    private fun checkLungeKneeLive(p: List<*>, exercise: String): String? {
        val knee = lm(p, if (exercise == "lunge_left") LM_LEFT_KNEE else LM_RIGHT_KNEE) ?: return null
        val toe  = lm(p, if (exercise == "lunge_left") LM_LEFT_TOE  else LM_RIGHT_TOE)  ?: return null
        return if (abs(knee.x - toe.x) > 0.08f) "Keep front knee behind your toes" else null
    }
    // ─────────────────────────────────────────────────────────────────────────
    // UI helpers
    // ─────────────────────────────────────────────────────────────────────────

    // Shows a temporary message in the feedback banner.
    // Auto-hides after 2 seconds.
    // Used for encouragement milestones and half rep warnings.
    private fun showTemporaryFeedback(message: String, bgColor: Int) {
        feedbackText.setBackgroundColor(bgColor)
        feedbackText.text       = message
        feedbackText.visibility = View.VISIBLE
        feedbackText.removeCallbacks(null)
        feedbackText.postDelayed(
            { feedbackText.visibility = View.GONE },
            2000
        )
    }

    // Sends a dedicated audio broadcast to Flutter.
    // Uses a separate "audioMessage" key so Flutter's audio service
    // can speak it via TTS without interfering with the feedback banner.
    private fun broadcastAudioMessage(message: String) {
        sendBroadcast(Intent(ACTION_RESULT).apply {
            putExtra("audioMessage",    message)
            putExtra(EXTRA_REP_COUNT,   lastBroadcastedRepCount)
            putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
            putExtra(EXTRA_STATUS,      "success")
            putExtra("isAtProperDepth", isAtProperDepth)
            putExtra("isTimer",         false)
            setPackage(packageName)
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Exercise mappings
    // ─────────────────────────────────────────────────────────────────────────

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

    private fun isTimerExercise(name: String): Boolean = name in timerExercises

    private fun startQuickPose(exerciseName: String) {
        lifecycleScope.launch {
            cameraView.start(useFrontCamera = true)

            if (isTimerExercise(exerciseName)) {
                startTimer()
                quickPose.start(
                    arrayOf(featureFor(exerciseName)),
                    onFrame = { _, _, _, feedback, _ ->
                        val feedbackMsg = feedback?.values?.firstOrNull()?.displayString ?: ""
                        if (feedbackMsg != lastBroadcastedFeedback) {
                            lastBroadcastedFeedback = feedbackMsg
                            runOnUiThread {
                                if (feedbackMsg.isNotEmpty()) {
                                    feedbackText.text       = feedbackMsg
                                    feedbackText.visibility = View.VISIBLE
                                } else {
                                    feedbackText.visibility = View.GONE
                                }
                            }
                        }
                    }
                )
            } else {
                quickPose.start(
                    arrayOf(featureFor(exerciseName)),
                    onFrame = { status, _, features, feedback, landmarks ->

                        val statusStr = if (status is Status.Success) "success" else "loading"

                        val hasRequiredFormIssue = feedback?.values?.any {
                            it.isRequired == true
                        } ?: false

                        val poseList = getPoseLandmarks(landmarks)

                        if (features != null && features.isNotEmpty()) {
                            features.forEach { (feature, result) ->
                                if (feature is Feature.Fitness && result.value != null) {
                                    val counterValue = result.value
                                    isAtProperDepth  = counterValue <= DEPTH_THRESHOLD

                                    if (counterValue <= DEPTH_THRESHOLD) {
                                        val angle = captureRepAngle(exerciseName, poseList)
                                        if (angle != null) {
                                            // Keep updating with the smallest angle seen —
                                            // smallest = most bent = deepest point of rep
                                            if (currentRepMinAngle == null || angle < currentRepMinAngle!!) {
                                                currentRepMinAngle = angle
                                            }
                                        }
                                        repAngleCaptured = true
                                    }
                                    if (counterValue > DEPTH_THRESHOLD && repAngleCaptured) {
                                        // Rising back up — commit the deepest angle captured
                                        if (currentRepMinAngle != null) {
                                            jointAngles.add(currentRepMinAngle!!)
                                            println("=== ANGLE CAPTURE: exercise=$exerciseName angle=$currentRepMinAngle° total=${jointAngles.size} ===")
                                        }
                                        currentRepMinAngle = null
                                        repAngleCaptured   = false
                                    }

                                    if (!hasRequiredFormIssue) {
                                        val newCount = counter.count(counterValue).count
                                        if (newCount != lastBroadcastedRepCount) {
                                            // ── FIX: keep latestRepCount in sync so
                                            //    broadcastSessionIfValid() has the real count ──
                                            latestRepCount          = newCount
                                            lastBroadcastedRepCount = newCount
                                            runOnUiThread {
                                                repCountText.text = newCount.toString()
                                                updateRepCounterStyle(
                                                    isAtDepth   = isAtProperDepth,
                                                    formBlocked = false
                                                )
                                            }
                                        } else {
                                            runOnUiThread {
                                                updateRepCounterStyle(
                                                    isAtDepth   = isAtProperDepth,
                                                    formBlocked = false
                                                )
                                            }
                                        }
                                    } else {
                                        runOnUiThread {
                                            updateRepCounterStyle(
                                                isAtDepth   = false,
                                                formBlocked = true
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        val feedbackMsg = feedback?.values?.firstOrNull()?.displayString ?: ""
                        if (feedbackMsg != lastBroadcastedFeedback) {
                            lastBroadcastedFeedback = feedbackMsg

                            // ── Track feedback frequency for form score ──
                            val isSetupMsg = SETUP_KEYWORDS.any { kw ->
                                feedbackMsg.lowercase().contains(kw)
                            }
                            if (feedbackMsg.isNotEmpty() && !isSetupMsg) {
                                feedbackFrequency[feedbackMsg] =
                                    (feedbackFrequency[feedbackMsg] ?: 0) + 1
                            }

                            runOnUiThread {
                                if (feedbackMsg.isNotEmpty()) {
                                    feedbackText.setBackgroundColor(
                                        if (hasRequiredFormIssue)
                                            Color.argb(200, 220, 50, 50)
                                        else
                                            Color.argb(200, 255, 94, 0)
                                    )
                                    feedbackText.text       = feedbackMsg
                                    feedbackText.visibility = View.VISIBLE
                                } else {
                                    feedbackText.visibility = View.GONE
                                }
                            }
                        }

                        sendBroadcast(Intent(ACTION_RESULT).apply {
                            putExtra(EXTRA_REP_COUNT,   lastBroadcastedRepCount)
                            putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
                            putExtra(EXTRA_STATUS,      statusStr)
                            putExtra("isAtProperDepth", isAtProperDepth)
                            putExtra("formIssueActive", hasRequiredFormIssue)
                            putExtra("isTimer",         false)
                            setPackage(packageName)
                        })
                    }
                )
            }
        }
    }

    private fun updateRepCounterStyle(isAtDepth: Boolean, formBlocked: Boolean) {
        repCountText.setTextColor(
            when {
                formBlocked -> Color.rgb(255, 94, 0)
                isAtDepth   -> Color.rgb(185, 255, 43)
                else        -> Color.rgb(255, 255, 255)
            }
        )
    }

    private fun startTimer() {
        stopTimer()
        elapsedSeconds = 0

        timerJob = lifecycleScope.launch {
            for (i in 10 downTo 1) {
                runOnUiThread {
                    repCountText.text = i.toString()
                    repCountText.setTextColor(Color.rgb(255, 255, 255))
                    val unitLabel = repContainer.findViewWithTag<TextView>("unit_label")
                    unitLabel?.text = "get ready..."
                }
                kotlinx.coroutines.delay(1000)
            }

            runOnUiThread {
                val unitLabel = repContainer.findViewWithTag<TextView>("unit_label")
                unitLabel?.text = "seconds"
            }

            while (true) {
                runOnUiThread {
                    repCountText.text = elapsedSeconds.toString()
                    repCountText.setTextColor(Color.rgb(185, 255, 43))
                }

                sendBroadcast(Intent(ACTION_RESULT).apply {
                    putExtra(EXTRA_REP_COUNT,   elapsedSeconds)
                    putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
                    putExtra(EXTRA_STATUS,      "success")
                    putExtra("isAtProperDepth", true)
                    putExtra("formIssueActive", false)
                    putExtra("isTimer",         true)
                    setPackage(packageName)
                })

                kotlinx.coroutines.delay(1000)
                elapsedSeconds++
            }
        }
    }

    private fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }
}