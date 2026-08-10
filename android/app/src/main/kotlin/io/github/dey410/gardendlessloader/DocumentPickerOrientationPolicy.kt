package io.github.dey410.gardendlessloader

import android.app.Activity
import android.content.pm.ActivityInfo

internal object DocumentPickerOrientationPolicy {
    const val COMPACT_BREAKPOINT_DP = 600

    fun isCompact(screenWidthDp: Int, screenHeightDp: Int): Boolean =
        screenWidthDp < COMPACT_BREAKPOINT_DP ||
            screenHeightDp < COMPACT_BREAKPOINT_DP
}

internal fun Activity.prepareForDocumentPicker() {
    val configuration = resources.configuration
    requestedOrientation = if (
        DocumentPickerOrientationPolicy.isCompact(
            configuration.screenWidthDp,
            configuration.screenHeightDp,
        )
    ) {
        ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
    } else {
        ActivityInfo.SCREEN_ORIENTATION_FULL_USER
    }
}

internal fun Activity.restoreLandscapeOrientation() {
    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
}
