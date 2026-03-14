package com.example.ai_fitness_app

import ai.quickpose.core.*
import ai.quickpose.camera.*
import android.content.Context
import android.view.View
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.launch

class QuickPoseView(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val eventSink: EventChannel.EventSink?,
    private val sdkKey: String
) : PlatformView {

    private val quickPose = QuickPose(context, sdkKey = sdkKey)
    private val cameraSwitchView = QuickPoseCameraSwitchView(context, quickPose)
    private val counter = QuickPoseThresholdCounter()

    private var currentFeature: Feature = Feature.Fitness(FitnessFeature.Squats)

    init {
        startQuickPose()
    }

    override fun getView(): View = cameraSwitchView

    override fun dispose() {
        quickPose.stop()
    }

    private fun startQuickPose() {
        lifecycleOwner.lifecycleScope.launch {
            cameraSwitchView.start(useFrontCamera = true)

            quickPose.start(
                arrayOf(currentFeature),
                onFrame = { status, overlay, features, feedback, landmarks ->
                    val result = parseResults(status, features, feedback)
                    eventSink?.success(result)
                }
            )
        }
    }

    fun switchExercise(exerciseName: String) {
        quickPose.stop()
        counter.reset()

        currentFeature = when (exerciseName) {
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

        lifecycleOwner.lifecycleScope.launch {
            quickPose.start(
                arrayOf(currentFeature),
                onFrame = { status, overlay, features, feedback, landmarks ->
                    val result = parseResults(status, features, feedback)
                    eventSink?.success(result)
                }
            )
        }
    }

    private fun parseResults(
        status: Status,
        features: Map<Feature, FeatureResult>?,
        feedback: Map<Feature, PoseFeedback>?
    ): Map<String, Any> {
        var repCount = 0
        var exerciseProgress = 0.0

        features?.forEach { (feature, result) ->
            if (feature is Feature.Fitness) {
                exerciseProgress = result.value.toDouble()
                val counterState = counter.count(result.value)
                repCount = counterState.count
            }
        }

        val feedbackMessage = feedback?.values?.firstOrNull()?.displayString ?: ""

        val statusString = when (status) {
            is Status.Success -> "success"
            else -> "loading"
        }

        return mapOf(
            "status"        to statusString,
            "repCount"      to repCount,
            "exerciseState" to (if (exerciseProgress > 0.8) "contracted" else "extended"),
            "feedback"      to feedbackMessage
        )
    }
}