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

    private lateinit var repCountText:  TextView
    private lateinit var feedbackText:  TextView
    private lateinit var exerciseLabel: TextView

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
        // Force overlay to render on top of camera preview consistently
        cameraView.setZOrderMediaOverlay(true)
        
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
        startQuickPose(currentExercise)
    }

    override fun onPause() {
        super.onPause()
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
            lastBroadcastedRepCount = 0
            lastBroadcastedFeedback = ""
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

    private fun startQuickPose(exerciseName: String) {
        lifecycleScope.launch {
            cameraView.start(useFrontCamera = true)

            quickPose.start(
                arrayOf(featureFor(exerciseName)),
                onFrame = { status, _, features, feedback, _ ->
                    val statusStr = if (status is Status.Success) "success" else "loading"

                    // Only update rep count if QuickPose actually detected the body this frame.
                    // If features is null/empty (skeleton lost), we keep the last known count
                    if (features != null && features.isNotEmpty()) {
                        features.forEach { (feature, result) ->
                            if (feature is Feature.Fitness && result.value != null) {
                                val newCount = counter.count(result.value).count
                                if (newCount != lastBroadcastedRepCount) {
                                    // Count changed — update UI and broadcast immediately
                                    lastBroadcastedRepCount = newCount
                                    runOnUiThread {
                                        repCountText.text = newCount.toString()
                                    }
                                }
                            }
                        }
                    }
                    // If features is null, we intentionally do nothing  UI keeps showing
                    // lastBroadcastedRepCount which is still displayed from the previous setState

                    // Feedback: only update if it actually changed
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

                    // Only broadcast when something actually changed reduces noise to Flutter
                    sendBroadcast(Intent(ACTION_RESULT).apply {
                        putExtra(EXTRA_REP_COUNT, lastBroadcastedRepCount)
                        putExtra(EXTRA_FEEDBACK,  lastBroadcastedFeedback)
                        putExtra(EXTRA_STATUS,    statusStr)
                        setPackage(packageName)
                    })
                }
            )
        }
    }
}