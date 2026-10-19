package io.github.dey410.gardendlessloader.game

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import kotlin.math.floor

internal object GameViewportSize {
    private const val MIN_ASPECT_RATIO = 16.0 / 10.0
    private const val MAX_ASPECT_RATIO = 17.0 / 9.0

    /** Show all keeps the whole 17:9 picture; the other fits allow 16:10–17:9. */
    fun fit(width: Int, height: Int, screenFit: GameScreenFit): Pair<Int, Int> {
        if (width <= 0 || height <= 0) return 0 to 0
        val minAspectRatio =
            if (screenFit == GameScreenFit.SHOW_ALL) MAX_ASPECT_RATIO else MIN_ASPECT_RATIO
        val aspectRatio = width.toDouble() / height
        return when {
            aspectRatio > MAX_ASPECT_RATIO ->
                floor(height * MAX_ASPECT_RATIO).toInt() to height
            aspectRatio < minAspectRatio ->
                width to floor(width / minAspectRatio).toInt()
            else -> width to height
        }
    }
}

internal class GameViewportLayout(
    context: Context,
    private val screenFit: GameScreenFit,
) : FrameLayout(context) {
    init {
        setBackgroundColor(Color.BLACK)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)
        if (childCount == 0) return

        val (viewportWidth, viewportHeight) = GameViewportSize.fit(width, height, screenFit)
        val childWidthSpec = MeasureSpec.makeMeasureSpec(viewportWidth, MeasureSpec.EXACTLY)
        val childHeightSpec = MeasureSpec.makeMeasureSpec(viewportHeight, MeasureSpec.EXACTLY)
        for (index in 0 until childCount) {
            getChildAt(index).measure(childWidthSpec, childHeightSpec)
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val height = bottom - top
        for (index in 0 until childCount) {
            val child: View = getChildAt(index)
            if (screenFit == GameScreenFit.STRETCH && child.measuredWidth > 0 && child.measuredHeight > 0) {
                // The page keeps the balanced viewport; scaling from the top-left
                // corner stretches it over the whole window.
                child.layout(0, 0, child.measuredWidth, child.measuredHeight)
                child.pivotX = 0f
                child.pivotY = 0f
                child.scaleX = width.toFloat() / child.measuredWidth
                child.scaleY = height.toFloat() / child.measuredHeight
                continue
            }
            val childLeft = (width - child.measuredWidth) / 2
            val childTop = (height - child.measuredHeight) / 2
            child.layout(
                childLeft,
                childTop,
                childLeft + child.measuredWidth,
                childTop + child.measuredHeight,
            )
        }
    }
}
