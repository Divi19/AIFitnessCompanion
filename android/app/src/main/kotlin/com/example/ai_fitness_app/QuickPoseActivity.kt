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
import kotlin.math.*

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

        const val MIN_REPS        = 3
        const val MIN_DURATION_MS = 20_000L

        // Camera setup messages — shown on screen but excluded from debrief map
        val SETUP_KEYWORDS = setOf(
            "back", "closer", "further", "forward", "camera",
            "centre", "center", "frame", "step", "move", "distance",
            "right", "left", "position", "align"
        )

        // Form quality gate — blocks rep counting for N frames after bad form detected
        const val FORM_FEEDBACK_WINDOW = 25

        // MediaPipe 33-point pose landmark indices
        // poseLandmarks is a flat List<Landmark> ordered by these indices
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

    private val quickPose get() = QuickPoseHolder.quickPose
        ?: throw IllegalStateException("QuickPose not initialised")
    private lateinit var cameraView: QuickPoseCameraSwitchView

    private val counter = QuickPoseThresholdCounter()
    private var currentExercise = "squat"

    // ── Session tracking ──────────────────────────────────────────────────
    private var sessionStartMs       = 0L
    private var latestRepCount       = 0
    private val feedbackFrequency    = mutableMapOf<String, Int>()
    private var lastRepTime          = 0L
    private var formFeedbackCooldown = 0

    // Tracks the counter float value previous frame — used to detect rep start/end
    private var prevCounterValue = 0f

    private lateinit var repCountText:  TextView
    private lateinit var feedbackText:  TextView
    private lateinit var exerciseLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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

    private fun resetSessionData() {
        sessionStartMs       = System.currentTimeMillis()
        latestRepCount       = 0
        feedbackFrequency.clear()
        lastRepTime          = 0L
        formFeedbackCooldown = 0
        prevCounterValue     = 0f
        counter.reset()
    }

    private fun broadcastSessionIfValid() {
        val durationMs    = System.currentTimeMillis() - sessionStartMs
        val meetsReps     = latestRepCount >= MIN_REPS
        val meetsDuration = durationMs     >= MIN_DURATION_MS

        println("=== SESSION END: reps=$latestRepCount, duration=${durationMs}ms ===")
        println("=== QUALITY CHECK: reps=$meetsReps, duration=$meetsDuration ===")

        if (!meetsReps || !meetsDuration) {
            println("=== SESSION DISCARDED: below quality threshold ===")
            return
        }

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

    // ── Landmark helpers ──────────────────────────────────────────────────

    // Safe access into poseLandmarks list by index
    // Returns null if list is empty, too short, or landmark has low visibility
    private fun lm(poseLandmarks: List<Landmark>, index: Int): Landmark? {
        if (poseLandmarks.size <= index) return null
        val l = poseLandmarks[index]
        // Only use landmark if visibility is reasonably high (>0.5)
        // Avoids false depth rejections from occluded/guessed landmarks
        if (l.visibility < 0.5f) return null
        return l
    }

    // Angle at point B given three 2D points A, B, C
    private fun angleDeg(
        ax: Float, ay: Float,
        bx: Float, by: Float,
        cx: Float, cy: Float
    ): Float {
        val abx = ax - bx; val aby = ay - by
        val cbx = cx - bx; val cby = cy - by
        val dot  = abx * cbx + aby * cby
        val magA = sqrt(abx * abx + aby * aby)
        val magC = sqrt(cbx * cbx + cby * cby)
        if (magA == 0f || magC == 0f) return 180f
        return Math.toDegrees(
            acos((dot / (magA * magC)).toDouble().coerceIn(-1.0, 1.0))
        ).toFloat()
    }

    // ── Depth checks — run at rep completion ─────────────────────────────
    // Returns a corrective message if depth was insufficient, null if fine.
    // Only called when poseLandmarks is non-empty (QuickPose has confident detection).
    private fun checkDepthAtRepCompletion(
        exercise: String,
        poseLandmarks: List<Landmark>
    ): String? {
        if (poseLandmarks.isEmpty()) return null
        return when (exercise) {
            "squat"                   -> checkSquatDepth(poseLandmarks)
            "lunge_left", "lunge_right" -> checkLungeDepth(poseLandmarks, exercise)
            "pushup"                  -> checkPushupDepth(poseLandmarks)
            else                      -> null
        }
    }

    private fun checkSquatDepth(p: List<Landmark>): String? {
        // Knee angle (hip-knee-ankle). Good depth = angle < 110°.
        // Above 110° means the user didn't get low enough.
        val lHip   = lm(p, LM_LEFT_HIP)    ?: return null
        val lKnee  = lm(p, LM_LEFT_KNEE)   ?: return null
        val lAnkle = lm(p, LM_LEFT_ANKLE)  ?: return null
        val rHip   = lm(p, LM_RIGHT_HIP)   ?: return null
        val rKnee  = lm(p, LM_RIGHT_KNEE)  ?: return null
        val rAnkle = lm(p, LM_RIGHT_ANKLE) ?: return null

        val leftAngle  = angleDeg(lHip.x, lHip.y, lKnee.x, lKnee.y, lAnkle.x, lAnkle.y)
        val rightAngle = angleDeg(rHip.x, rHip.y, rKnee.x, rKnee.y, rAnkle.x, rAnkle.y)
        val avgAngle   = (leftAngle + rightAngle) / 2f

        println("=== SQUAT DEPTH: kneeAngle=$avgAngle ===")
        return if (avgAngle > 110f) "Go deeper — hips below knees" else null
    }

    private fun checkLungeDepth(p: List<Landmark>, exercise: String): String? {
        val isLeft  = exercise == "lunge_left"
        val hipIdx  = if (isLeft) LM_LEFT_HIP   else LM_RIGHT_HIP
        val kneeIdx = if (isLeft) LM_LEFT_KNEE  else LM_RIGHT_KNEE
        val ankIdx  = if (isLeft) LM_LEFT_ANKLE else LM_RIGHT_ANKLE
        val toeIdx  = if (isLeft) LM_LEFT_TOE   else LM_RIGHT_TOE

        val hip   = lm(p, hipIdx)  ?: return null
        val knee  = lm(p, kneeIdx) ?: return null
        val ankle = lm(p, ankIdx)  ?: return null
        val toe   = lm(p, toeIdx)  ?: return null

        val kneeAngle = angleDeg(hip.x, hip.y, knee.x, knee.y, ankle.x, ankle.y)
        if (kneeAngle > 120f) return "Lunge deeper — front knee to 90 degrees"

        // Knee-over-toe check using normalised x coordinates
        val kneeOverToe = abs(knee.x - toe.x)
        if (kneeOverToe > 0.08f) return "Keep your front knee behind your toes"

        return null
    }

    private fun checkPushupDepth(p: List<Landmark>): String? {
        // Elbow angle (shoulder-elbow-wrist). Good depth = angle < 120°.
        val lShoulder = lm(p, LM_LEFT_SHOULDER)  ?: return null
        val lElbow    = lm(p, LM_LEFT_ELBOW)     ?: return null
        val lWrist    = lm(p, LM_LEFT_WRIST)     ?: return null
        val rShoulder = lm(p, LM_RIGHT_SHOULDER) ?: return null
        val rElbow    = lm(p, LM_RIGHT_ELBOW)    ?: return null
        val rWrist    = lm(p, LM_RIGHT_WRIST)    ?: return null

        val leftAngle  = angleDeg(lShoulder.x, lShoulder.y, lElbow.x, lElbow.y, lWrist.x, lWrist.y)
        val rightAngle = angleDeg(rShoulder.x, rShoulder.y, rElbow.x, rElbow.y, rWrist.x, rWrist.y)
        val avgAngle   = (leftAngle + rightAngle) / 2f

        println("=== PUSHUP DEPTH: elbowAngle=$avgAngle ===")
        return if (avgAngle > 120f) "Go lower — chest closer to the ground" else null
    }

    // ── Live form checks — run every active frame ─────────────────────────
    // Catches issues QuickPose doesn't detect natively.
    // Only runs when counterValue > 0.3 (mid-rep, not resting position).
    private fun checkLiveForm(
        exercise: String,
        poseLandmarks: List<Landmark>,
        counterValue: Float
    ): String? {
        if (poseLandmarks.isEmpty() || counterValue < 0.3f) return null
        return when (exercise) {
            "bicep_curl"                -> checkBicepElbowRaising(poseLandmarks)
            "lunge_left", "lunge_right" -> checkLungeKneeLive(poseLandmarks, exercise)
            else                        -> null
        }
    }

    private fun checkBicepElbowRaising(p: List<Landmark>): String? {
        // If elbow y is significantly above shoulder y, the user is raising their arm.
        // In normalised coords y increases downward, so lower y value = higher on screen.
        val lShoulder = lm(p, LM_LEFT_SHOULDER)  ?: return null
        val rShoulder = lm(p, LM_RIGHT_SHOULDER) ?: return null
        val lElbow    = lm(p, LM_LEFT_ELBOW)     ?: return null
        val rElbow    = lm(p, LM_RIGHT_ELBOW)    ?: return null

        // Positive value = elbow is higher on screen than shoulder
        val leftRaise  = lShoulder.y - lElbow.y
        val rightRaise = rShoulder.y - rElbow.y
        val maxRaise   = maxOf(leftRaise, rightRaise)

        return if (maxRaise > 0.08f) "Keep elbows tucked — don't raise them" else null
    }

    private fun checkLungeKneeLive(p: List<Landmark>, exercise: String): String? {
        val kneeIdx = if (exercise == "lunge_left") LM_LEFT_KNEE else LM_RIGHT_KNEE
        val toeIdx  = if (exercise == "lunge_left") LM_LEFT_TOE  else LM_RIGHT_TOE

        val knee = lm(p, kneeIdx) ?: return null
        val toe  = lm(p, toeIdx)  ?: return null

        return if (abs(knee.x - toe.x) > 0.08f) "Keep front knee behind your toes" else null
    }

    // ── Feature and display name maps ─────────────────────────────────────
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

    // ── Main QuickPose loop ───────────────────────────────────────────────
    private fun startQuickPose(exerciseName: String) {
        lifecycleScope.launch {
            cameraView.start(useFrontCamera = true)

            quickPose.start(
                arrayOf(featureFor(exerciseName)),
                onFrame = { status, _, features, feedback, landmarks ->

                    // ── Get pose landmarks from QuickPose Landmarks object ─
                    // poseLandmarks is a flat List<Landmark> of 33 MediaPipe points.
                    // It is empty when QuickPose doesn't have a confident detection —
                    // depth/live checks are skipped entirely in that case.
                    val poseLandmarks = landmarks?.getPoseLandmarks() ?: emptyList()

                    // ── Get counter value for this frame ──────────────────
                    var counterValue = 0f
                    features?.forEach { (feature, result) ->
                        if (feature is Feature.Fitness) counterValue = result.value
                    }

                    // Detect rep start — counter drops back toward 0 after being high
                    prevCounterValue = counterValue

                    // ── QuickPose native feedback ─────────────────────────
                    val quickPoseFeedback = feedback?.values?.firstOrNull()?.displayString ?: ""
                    val isSetupMsg    = quickPoseFeedback.isNotEmpty() &&
                        SETUP_KEYWORDS.any { quickPoseFeedback.lowercase().contains(it) }
                    val isFormFeedback = quickPoseFeedback.isNotEmpty() && !isSetupMsg

                    if (isFormFeedback) {
                        formFeedbackCooldown = FORM_FEEDBACK_WINDOW
                        feedbackFrequency[quickPoseFeedback] =
                            (feedbackFrequency[quickPoseFeedback] ?: 0) + 1
                    } else if (formFeedbackCooldown > 0) {
                        formFeedbackCooldown--
                    }

                    // ── Live form check (runs every active frame) ─────────
                    val liveFormMsg = checkLiveForm(exerciseName, poseLandmarks, counterValue)
                    if (liveFormMsg != null) {
                        formFeedbackCooldown = FORM_FEEDBACK_WINDOW
                        feedbackFrequency[liveFormMsg] =
                            (feedbackFrequency[liveFormMsg] ?: 0) + 1
                    }

                    // ── Rep counting with form gate + depth check ─────────
                    var repRejectedMsg: String? = null

                    features?.forEach { (feature, result) ->
                        if (feature is Feature.Fitness) {
                            val counterState = counter.count(result.value)
                            val now = System.currentTimeMillis()

                            if (counterState.count > latestRepCount &&
                                (now - lastRepTime) > 500L) {

                                when {
                                    // ── Form quality gate ─────────────────
                                    formFeedbackCooldown > 0 -> {
                                        repRejectedMsg = "Fix your form to count this rep"
                                        feedbackFrequency[repRejectedMsg!!] =
                                            (feedbackFrequency[repRejectedMsg!!] ?: 0) + 1
                                    }
                                    // ── Depth check ───────────────────────
                                    // Only runs when landmarks are available
                                    poseLandmarks.isNotEmpty() -> {
                                        val depthMsg = checkDepthAtRepCompletion(
                                            exerciseName, poseLandmarks
                                        )
                                        if (depthMsg != null) {
                                            repRejectedMsg = depthMsg
                                            feedbackFrequency[depthMsg] =
                                                (feedbackFrequency[depthMsg] ?: 0) + 1
                                        } else {
                                            // Valid rep — count it
                                            latestRepCount = counterState.count
                                            lastRepTime    = now
                                        }
                                    }
                                    // ── Landmarks empty — count rep but note it ─
                                    // If QuickPose can't see the body well enough
                                    // for landmarks, we still count the rep (QuickPose
                                    // verified it) but skip depth check silently
                                    else -> {
                                        latestRepCount = counterState.count
                                        lastRepTime    = now
                                    }
                                }
                            }
                        }
                    }

                    // Priority: rep rejection > live form > QuickPose native feedback
                    val shownFeedback = repRejectedMsg
                        ?: liveFormMsg?.takeIf { quickPoseFeedback.isEmpty() }
                        ?: quickPoseFeedback

                    val statusStr = if (status is Status.Success) "success" else "loading"

                    runOnUiThread {
                        repCountText.text = latestRepCount.toString()
                        if (shownFeedback.isNotEmpty()) {
                            feedbackText.text       = shownFeedback
                            feedbackText.visibility = View.VISIBLE
                        } else {
                            feedbackText.visibility = View.GONE
                        }
                    }

                    sendBroadcast(Intent(ACTION_RESULT).apply {
                        putExtra(EXTRA_REP_COUNT, latestRepCount)
                        putExtra(EXTRA_FEEDBACK,  shownFeedback)
                        putExtra(EXTRA_STATUS,    statusStr)
                        setPackage(packageName)
                    })
                }
            )
        }
    }
}