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
        const val EXTRA_EXERCISE  = "exercise"
        const val ACTION_RESULT   = "com.example.ai_fitness_app.QUICKPOSE_RESULT"
        const val EXTRA_REP_COUNT = "rep_count"
        const val EXTRA_FEEDBACK  = "feedback"
        const val EXTRA_STATUS    = "status"
    }

    private val quickPose get() = QuickPoseHolder.quickPose
        ?: throw IllegalStateException("QuickPose not initialised")

    // NEW: Camera view is tied strictly to this activity's lifecycle
    private lateinit var cameraView: QuickPoseCameraSwitchView

    // enterThreshold: signal must reach this HIGH value to start a rep (top of movement)
    // exitThreshold:  signal must drop to this LOW value to complete a rep (bottom of movement)
    // Both values are 0-1 normalised. Wider gap = harder to accidentally trigger a rep.
    private val counter = QuickPoseThresholdCounter(
        enterThreshold = 0.8f,
        exitThreshold  = 0.2f
    )

    private var currentExercise = "squat"
    private var lastBroadcastedRepCount = 0  // Stores last known count so missed frames don't reset to 0
    private var lastBroadcastedFeedback  = "" // Stores last known feedback for same reason

    // Timer support for duration-based exercises like plank
    private var timerJob: kotlinx.coroutines.Job? = null
    private var elapsedSeconds = 0

    // Exercises that use a timer instead of rep counter
    private val timerExercises = setOf("plank")

    // Tracks whether the user is currently at proper depth
    // Used to drive the visual rep quality indicator
    private var isAtProperDepth = false

    // Proper depth threshold — signal must drop below this value
    // to be considered at full depth. Matches exitThreshold on the counter.
    // 0.3 gives a slightly generous window so the indicator lights up
    // just before the counter commits the rep.
    private val DEPTH_THRESHOLD = 0.3f

    private lateinit var repCountText:  TextView
    private lateinit var feedbackText:  TextView
    private lateinit var exerciseLabel: TextView
    private lateinit var repContainer:  LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.setDecorFitsSystemWindows(false)

        // Force the SurfaceView to render on top without competing with the window compositor
        window.addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        
        currentExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: "squat"
        
        // Initialize the camera view securely inside this Activity context
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

        // Add the locally created camera view directly to the root
        val cameraParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        root.addView(cameraView, cameraParams)
        
        // Back button
        val backBtn = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            setPadding(24, 24, 24, 24)
            contentDescription = "Back"
            setOnClickListener { finishCleanly() }
        }
        root.addView(backBtn, FrameLayout.LayoutParams(120, 120).apply {
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
        repContainer = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
        }
       repCountText = TextView(this).apply {
            text = "0"; textSize = 96f
            setTextColor(Color.rgb(185, 255, 43))
            typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER
        }
        repContainer.addView(repCountText)

        // Label changes between "reps" and "seconds" depending on exercise type
        val unitLabel = TextView(this).apply {
            text = if (isTimerExercise(currentExercise)) "seconds" else "reps"
            textSize = 18f
            setTextColor(Color.argb(150, 255, 255, 255))
            gravity = Gravity.CENTER
            tag = "unit_label" // Tag so we can find and update it later
        }
        repContainer.addView(unitLabel)

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
        startQuickPose(currentExercise)
    }

    override fun onPause() {
        super.onPause()
        stopTimer()
        quickPose.stop()
        try {
            cameraView.stop() // NEW: Explicitly release the camera hardware
        } catch (e: Exception) {}
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { finishCleanly() }

    private fun finishCleanly() {
        quickPose.stop()
        try {
            cameraView.stop() // NEW: Free the camera lock immediately
        } catch (e: Exception) {}
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val newExercise = intent.getStringExtra(EXTRA_EXERCISE) ?: return
        if (newExercise != currentExercise) {
            currentExercise = newExercise
            counter.reset()
            stopTimer()
            elapsedSeconds = 0
            lastBroadcastedRepCount = 0
            lastBroadcastedFeedback = ""
            isAtProperDepth         = false
            quickPose.stop()
            runOnUiThread {
                repCountText.text       = "0"
                feedbackText.visibility = View.GONE
                exerciseLabel.text      = exerciseDisplayName(newExercise)
            }
            lifecycleScope.launch { startQuickPose(newExercise) }
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

    private fun isTimerExercise(name: String): Boolean {
        return name in timerExercises
    }

private fun startQuickPose(exerciseName: String) {
    lifecycleScope.launch {
        cameraView.start(useFrontCamera = true)

        if (isTimerExercise(exerciseName)) {
            // Timer-based exercise — start the timer immediately
            // QuickPose still runs for form feedback but we ignore rep values
            startTimer()

            quickPose.start(
                arrayOf(featureFor(exerciseName)),
                onFrame = { _, _, _, feedback, _ ->
                    // For timer exercises we only care about feedback
                    // Rep counting is handled by the timer coroutine above
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
            // Rep-based exercise — original counting logic
            quickPose.start(
                arrayOf(featureFor(exerciseName)),
                onFrame = { status, _, features, feedback, _ ->

                    val statusStr = if (status is Status.Success) "success" else "loading"

                    val hasRequiredFormIssue = feedback?.values?.any {
                        it.isRequired == true
                    } ?: false

                    if (features != null && features.isNotEmpty()) {
                        features.forEach { (feature, result) ->
                            if (feature is Feature.Fitness && result.value != null) {
                                isAtProperDepth = result.value <= DEPTH_THRESHOLD

                                if (!hasRequiredFormIssue) {
                                    val newCount = counter.count(result.value).count
                                    if (newCount != lastBroadcastedRepCount) {
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


/// Updates the rep counter text color based on current exercise state.
///
/// isAtDepth = true  → Lime green (user hit proper depth, good rep)
/// formBlocked = true → Orange    (form issue is blocking the count)
/// default            → White     (neutral / returning to start position)
private fun updateRepCounterStyle(isAtDepth: Boolean, formBlocked: Boolean) {
    repCountText.setTextColor(
        when {
            formBlocked -> Color.rgb(255, 94, 0)    // Orange — form blocking count
            isAtDepth   -> Color.rgb(185, 255, 43)  // Lime green — proper depth reached
            else        -> Color.rgb(255, 255, 255) // White — neutral position
        }
    )
}

/// Starts the elapsed seconds timer for duration-based exercises.
/// Includes a 10-second setup delay before counting begins so the
/// user has time to get into position.
private fun startTimer() {
    stopTimer() // Cancel any existing timer first
    elapsedSeconds = 0

    timerJob = lifecycleScope.launch {
        // 10-second setup countdown — tell user to get ready
        for (i in 10 downTo 1) {
            runOnUiThread {
                repCountText.text = i.toString()
                repCountText.setTextColor(Color.rgb(255, 255, 255)) // White during countdown
                // Update unit label to show "get ready"
                val unitLabel = repContainer.findViewWithTag<TextView>("unit_label")
                unitLabel?.text = "get ready..."
            }
            kotlinx.coroutines.delay(1000)
        }

        // Setup done — start counting elapsed seconds
        runOnUiThread {
            val unitLabel = repContainer.findViewWithTag<TextView>("unit_label")
            unitLabel?.text = "seconds"
        }

        while (true) {
            runOnUiThread {
                repCountText.text = elapsedSeconds.toString()
                repCountText.setTextColor(Color.rgb(185, 255, 43)) // Lime green when active
            }

            // Broadcast timer value to Flutter
            sendBroadcast(Intent(ACTION_RESULT).apply {
                putExtra(EXTRA_REP_COUNT,   elapsedSeconds)
                putExtra(EXTRA_FEEDBACK,    lastBroadcastedFeedback)
                putExtra(EXTRA_STATUS,      "success")
                putExtra("isAtProperDepth", true)
                putExtra("formIssueActive", false)
                putExtra("isTimer",         true) // Flutter uses this to show timer UI
                setPackage(packageName)
            })

            kotlinx.coroutines.delay(1000)
            elapsedSeconds++
        }
    }
}

/// Cancels the running timer.
private fun stopTimer() {
    timerJob?.cancel()
    timerJob = null
}
}