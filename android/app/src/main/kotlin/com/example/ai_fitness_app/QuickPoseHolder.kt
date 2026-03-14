package com.example.ai_fitness_app

import ai.quickpose.core.QuickPose

// Holds ONLY the QuickPose AI instance across Activity launches.
// We DO NOT hold the camera view here to avoid hardware monopoly crashes.
object QuickPoseHolder {
    var quickPose: QuickPose? = null
}